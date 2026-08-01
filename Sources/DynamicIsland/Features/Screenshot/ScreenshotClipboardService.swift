import AppKit
import CryptoKit
import Foundation

@MainActor
final class ScreenshotClipboardService {
    var onScreenshotsChanged: (([ScreenshotItem]) -> Void)?
    var onNewScreenshot: (() -> Void)?
    var onAccessibilityStatusChanged: ((Bool) -> Void)?

    private(set) var items: [ScreenshotItem] = []
    private(set) var isAccessibilityTrusted = false

    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFileDescriptor: Int32 = -1
    private var knownSourcePaths: Set<String> = []
    private var pasteboardTimer: Timer?
    private var scanTimer: Timer?
    private var keyMonitor: Any?
    private var pasteboardArmDeadline: Date?
    private var isWritingToPasteboard = false
    private var lastPasteboardChangeCount = NSPasteboard.general.changeCount
    private var recentHashes: Set<String> = []
    private var wasAccessibilityTrusted = false
    private var lastScreencaptureStamp: String?
    private var lastScreencapturePrefsmtime: Date?
    private var defaultsPollTimer: Timer?

    private let storageDirectory: URL
    private let manifestURL: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageDirectory = base
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("Screenshots", isDirectory: true)
        manifestURL = storageDirectory.appendingPathComponent("manifest.json")
    }

    func start() {
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        loadPersisted()
        refreshAccessibilityStatus()
        seedKnownSourceFiles()
        startDirectoryWatcher()
        startKeyMonitor()
        startPasteboardPolling()
        startScreencaptureDefaultsPolling()
        // Clipboard-destination mode needs Accessibility for shortcut arming; hint early.
        if isScreenshotTargetClipboard && !isAccessibilityTrusted {
            onAccessibilityStatusChanged?(false)
        }
        onScreenshotsChanged?(items)
    }

    func stop() {
        directorySource?.cancel()
        directorySource = nil
        if directoryFileDescriptor >= 0 {
            close(directoryFileDescriptor)
            directoryFileDescriptor = -1
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        pasteboardTimer?.invalidate()
        pasteboardTimer = nil
        scanTimer?.invalidate()
        scanTimer = nil
        defaultsPollTimer?.invalidate()
        defaultsPollTimer = nil
    }

    /// macOS ⇧⌘5 Options → Save to Clipboard (or equivalent).
    private var isScreenshotTargetClipboard: Bool {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        let target = defaults?.string(forKey: "target-screenshot")
            ?? defaults?.string(forKey: "target")
        return target == "clipboard"
    }

    func refreshAccessibilityStatus() {
        let trusted = AXIsProcessTrusted()
        let changed = trusted != isAccessibilityTrusted
        isAccessibilityTrusted = trusted
        if changed {
            onAccessibilityStatusChanged?(trusted)
        }
        // Update before starting the monitor to avoid refresh ↔ startKeyMonitor recursion.
        let becameTrusted = trusted && !wasAccessibilityTrusted
        wasAccessibilityTrusted = trusted
        if becameTrusted {
            startKeyMonitor()
        }
    }

    /// Opens Privacy → Accessibility settings and prompts for trust.
    func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshAccessibilityStatus()
    }

    func armPasteboardWindow(durationNanoseconds: UInt64 = ScreenshotClipboardLayout.pasteboardArmNanoseconds) {
        let seconds = TimeInterval(durationNanoseconds) / 1_000_000_000
        let candidate = Date().addingTimeInterval(seconds)
        // Extend, don't shorten, if already armed longer.
        if let existing = pasteboardArmDeadline, existing > candidate {
            return
        }
        pasteboardArmDeadline = candidate
        lastPasteboardChangeCount = NSPasteboard.general.changeCount
    }

    func copyToPasteboard(_ item: ScreenshotItem) -> Bool {
        guard let image = item.image else { return false }
        isWritingToPasteboard = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.isWritingToPasteboard = false
                self?.lastPasteboardChangeCount = NSPasteboard.general.changeCount
            }
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        if let data = try? Data(contentsOf: item.fileURL) {
            pasteboard.setData(data, forType: .png)
        }
        lastPasteboardChangeCount = pasteboard.changeCount
        return true
    }

    func remove(_ item: ScreenshotItem) {
        items.removeAll { $0.id == item.id }
        try? FileManager.default.removeItem(at: item.fileURL)
        persist()
        onScreenshotsChanged?(items)
    }

    /// Collapse helper: post ⇧⌘5. Returns false if Accessibility is unavailable.
    @discardableResult
    func postScreenshotUIShortcut() -> Bool {
        refreshAccessibilityStatus()
        guard isAccessibilityTrusted else { return false }

        armPasteboardWindow(durationNanoseconds: ScreenshotClipboardLayout.screenshotUIPasteboardArmNanoseconds)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 0x17 // kVK_ANSI_5

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }

        keyDown.flags = [.maskShift, .maskCommand]
        keyUp.flags = [.maskShift, .maskCommand]
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - Persistence

    private struct ManifestEntry: Codable {
        let id: UUID
        let createdAt: Date
        let fileName: String
        let contentHash: String
    }

    private func loadPersisted() {
        guard
            let data = try? Data(contentsOf: manifestURL),
            let entries = try? JSONDecoder().decode([ManifestEntry].self, from: data)
        else {
            items = []
            return
        }

        items = entries.compactMap { entry in
            let url = storageDirectory.appendingPathComponent(entry.fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ScreenshotItem(
                id: entry.id,
                createdAt: entry.createdAt,
                fileURL: url,
                contentHash: entry.contentHash
            )
        }
        .sorted { $0.createdAt < $1.createdAt }

        recentHashes = Set(items.map(\.contentHash))
        trimToLimit(notify: false)
    }

    private func persist() {
        let entries = items.map {
            ManifestEntry(
                id: $0.id,
                createdAt: $0.createdAt,
                fileName: $0.fileURL.lastPathComponent,
                contentHash: $0.contentHash
            )
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func trimToLimit(notify: Bool) {
        while items.count > ScreenshotClipboardLayout.maxItems {
            let removed = items.removeFirst()
            try? FileManager.default.removeItem(at: removed.fileURL)
            recentHashes.remove(removed.contentHash)
        }
        if notify {
            persist()
            onScreenshotsChanged?(items)
        } else {
            persist()
        }
    }

    // MARK: - Directory watcher

    private func screenshotSaveDirectory() -> URL {
        let defaults = UserDefaults(suiteName: "com.apple.screencapture")
        for key in ["location", "location-last"] {
            if let path = defaults?.string(forKey: key), !path.isEmpty {
                return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop", isDirectory: true)
    }

    private func seedKnownSourceFiles() {
        let dir = screenshotSaveDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for file in files where isLikelyScreenshotFile(file) {
            knownSourcePaths.insert(file.path)
        }
    }

    private func startDirectoryWatcher() {
        let dir = screenshotSaveDirectory()
        let path = dir.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        directoryFileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .extend, .attrib, .link, .delete],
            queue: DispatchQueue.main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.scanForNewScreenshotFiles()
            }
        }
        source.setCancelHandler { [weak self] in
            if let self, self.directoryFileDescriptor >= 0 {
                close(self.directoryFileDescriptor)
                self.directoryFileDescriptor = -1
            }
        }
        directorySource = source
        source.resume()

        // Periodic scan covers delayed writes / permission races.
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanForNewScreenshotFiles()
                self?.refreshAccessibilityStatus()
            }
        }
        if let scanTimer {
            RunLoop.main.add(scanTimer, forMode: .common)
        }
    }

    private func scanForNewScreenshotFiles() {
        let dir = screenshotSaveDirectory()
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let now = Date()
        for file in files {
            guard isLikelyScreenshotFile(file) else { continue }
            if knownSourcePaths.contains(file.path) { continue }

            let values = try? file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let stamp = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            // Ignore ancient files discovered after a location change.
            guard now.timeIntervalSince(stamp) < 120 else {
                knownSourcePaths.insert(file.path)
                continue
            }

            knownSourcePaths.insert(file.path)
            ingestFile(at: file)
        }
    }

    private func isLikelyScreenshotFile(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) else { return false }
        let name = url.lastPathComponent
        if name.localizedCaseInsensitiveContains("Screenshot") { return true }
        if name.localizedCaseInsensitiveContains("Screen Shot") { return true }
        // Localized macOS names often still include "Screenshot" / "Captura".
        if name.localizedCaseInsensitiveContains("Captura") { return true }
        return false
    }

    // MARK: - Pasteboard / keys

    private func startPasteboardPolling() {
        pasteboardTimer?.invalidate()
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPasteboard()
            }
        }
        if let pasteboardTimer {
            RunLoop.main.add(pasteboardTimer, forMode: .common)
        }
    }

    private func pollPasteboard() {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        guard changeCount != lastPasteboardChangeCount else { return }
        lastPasteboardChangeCount = changeCount

        guard !isWritingToPasteboard else { return }
        guard let deadline = pasteboardArmDeadline, Date() <= deadline else { return }
        guard let image = readImage(from: pasteboard) else { return }

        pasteboardArmDeadline = nil
        ingestImage(image)
    }

    private func readImage(from pasteboard: NSPasteboard) -> NSImage? {
        if let data = pasteboard.data(forType: .png), let image = NSImage(data: data) {
            return image
        }
        if let data = pasteboard.data(forType: .tiff), let image = NSImage(data: data) {
            return image
        }
        if let images = pasteboard.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage],
           let image = images.first {
            return image
        }
        return nil
    }

    private func startKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }

        guard AXIsProcessTrusted() else {
            isAccessibilityTrusted = false
            return
        }
        isAccessibilityTrusted = true

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                self?.handleKeyEvent(event)
            }
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // kVK_ANSI_3 / 4 / 5
        let isThreeFourFive = keyCode == 0x14 || keyCode == 0x15 || keyCode == 0x17
        guard isThreeFourFive else { return }

        let hasShift = flags.contains(.shift)
        let hasCommand = flags.contains(.command)
        guard hasShift && hasCommand else { return }

        // ⇧⌘3/4/5 (with or without ⌃) — when Save-to is Clipboard, 3/4 land on pasteboard
        // without requiring Control. ⇧⌘5 opens the UI and may also save to clipboard.
        if keyCode == 0x17 {
            armPasteboardWindow(durationNanoseconds: ScreenshotClipboardLayout.screenshotUIPasteboardArmNanoseconds)
        } else {
            armPasteboardWindow()
        }
    }

    /// Watch screencapture prefs: when a capture completes, macOS updates stamps/selection.
    /// This arms pasteboard ingest even without Accessibility (clipboard destination).
    private func startScreencaptureDefaultsPolling() {
        let snapshot = readScreencapturePrefsSnapshot()
        lastScreencaptureStamp = snapshot.stamp
        lastScreencapturePrefsmtime = snapshot.mtime

        defaultsPollTimer?.invalidate()
        defaultsPollTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollScreencaptureDefaults()
            }
        }
        if let defaultsPollTimer {
            RunLoop.main.add(defaultsPollTimer, forMode: .common)
        }
    }

    private var screencapturePrefsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.apple.screencapture.plist")
    }

    private func readScreencapturePrefsSnapshot() -> (stamp: String, mtime: Date?, targetClipboard: Bool) {
        let url = screencapturePrefsURL
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let dict = NSDictionary(contentsOf: url) as? [String: Any] ?? [:]
        let analytics = dict["last-analytics-stamp"] as? String ?? ""
        let selection = dict["last-selection"] as? [String: Any] ?? [:]
        let w = selection["Width"] as? NSNumber
        let h = selection["Height"] as? NSNumber
        let x = selection["X"] as? NSNumber
        let y = selection["Y"] as? NSNumber
        let stamp = "\(analytics)|\(w?.stringValue ?? "")x\(h?.stringValue ?? "")@\(x?.stringValue ?? ""),\(y?.stringValue ?? "")"
        let target = (dict["target-screenshot"] as? String) ?? (dict["target"] as? String)
        return (stamp, mtime, target == "clipboard")
    }

    private func pollScreencaptureDefaults() {
        let snapshot = readScreencapturePrefsSnapshot()
        let stampChanged = snapshot.stamp != lastScreencaptureStamp
        let mtimeChanged = snapshot.mtime != nil && snapshot.mtime != lastScreencapturePrefsmtime
        guard stampChanged || mtimeChanged else { return }

        lastScreencaptureStamp = snapshot.stamp
        lastScreencapturePrefsmtime = snapshot.mtime

        // A capture just happened. Prefer file scan; also arm pasteboard for clipboard target.
        scanForNewScreenshotFiles()
        if snapshot.targetClipboard || isScreenshotTargetClipboard {
            armPasteboardWindow(durationNanoseconds: ScreenshotClipboardLayout.screenshotUIPasteboardArmNanoseconds)
            // Image may already be on the pasteboard — try immediately.
            attemptImmediatePasteboardIngest()
        }
    }

    private func attemptImmediatePasteboardIngest() {
        guard !isWritingToPasteboard else { return }
        let pasteboard = NSPasteboard.general
        lastPasteboardChangeCount = pasteboard.changeCount
        guard let image = readImage(from: pasteboard) else { return }
        pasteboardArmDeadline = nil
        ingestImage(image)
    }

    // MARK: - Ingest

    private func ingestFile(at sourceURL: URL) {
        guard let data = try? Data(contentsOf: sourceURL) else { return }
        guard let image = NSImage(data: data) else { return }
        let stored = pngData(from: image) ?? data
        let hash = Self.hash(stored)
        guard !recentHashes.contains(hash) else { return }
        commit(pngData: stored, hash: hash)
    }

    private func ingestImage(_ image: NSImage) {
        guard let data = pngData(from: image) else { return }
        let hash = Self.hash(data)
        guard !recentHashes.contains(hash) else { return }
        commit(pngData: data, hash: hash)
    }

    private func commit(pngData: Data, hash: String) {
        let id = UUID()
        let fileURL = storageDirectory.appendingPathComponent("\(id.uuidString).png")
        do {
            try pngData.write(to: fileURL, options: .atomic)
        } catch {
            return
        }

        let item = ScreenshotItem(
            id: id,
            createdAt: Date(),
            fileURL: fileURL,
            contentHash: hash
        )
        recentHashes.insert(hash)
        items.append(item)
        trimToLimit(notify: false)
        persist()
        onScreenshotsChanged?(items)
        onNewScreenshot?()
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
