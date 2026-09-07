import AppKit
import Darwin
import Foundation

/// Samples host CPU load, VM stats, and per-app energy (not battery).
final class MacSystemService {
    private var previousCPU: (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)?
    private var previousAppEnergyNJ: [pid_t: UInt64] = [:]
    private var previousEnergySampleAt: Date?
    private var recentAppWatts: [Double] = []

    private let energyRollingWindow = 8
    /// `rusage_info_v6` as UInt64 words (464 bytes).
    private let rusageV6WordCount = 58
    private let rusageFlavorV6: Int32 = 6
    private let energyNJWordIndex = 42

    init() {
        previousCPU = hostCPUTicks()
    }

    func snapshot() -> MacSystemSnapshot {
        MacSystemSnapshot(
            cpuPercent: sampleCPUPercent(),
            memoryUsedBytes: sampleMemoryUsedBytes(),
            memoryTotalBytes: ProcessInfo.processInfo.physicalMemory,
            energy: sampleAppEnergy(),
            sampledAt: Date()
        )
    }

    private func sampleCPUPercent() -> Double {
        guard let ticks = hostCPUTicks() else { return 0 }
        defer { previousCPU = ticks }

        guard let previous = previousCPU else { return 0 }

        let user = Double(ticks.user &- previous.user)
        let system = Double(ticks.system &- previous.system)
        let idle = Double(ticks.idle &- previous.idle)
        let nice = Double(ticks.nice &- previous.nice)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, max(0, (user + system + nice) / total * 100))
    }

    private func hostCPUTicks() -> (user: UInt64, system: UInt64, idle: UInt64, nice: UInt64)? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return (
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
    }

    private func sampleMemoryUsedBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let page = UInt64(pageSize)

        if result == KERN_SUCCESS {
            let usedPages = UInt64(stats.active_count)
                + UInt64(stats.wire_count)
                + UInt64(stats.compressor_page_count)
            return min(ProcessInfo.processInfo.physicalMemory, usedPages * page)
        }

        return 0
    }

    /// Rolling average of process-attributed power across running apps (nanojoules → watts).
    private func sampleAppEnergy() -> MacEnergyReading {
        let now = Date()
        var current: [pid_t: UInt64] = [:]
        var deltaNJ: Double = 0

        for app in NSWorkspace.shared.runningApplications {
            let pid = app.processIdentifier
            guard pid > 0, let energyNJ = processEnergyNanojoules(pid: pid) else { continue }
            current[pid] = energyNJ
            if let previous = previousAppEnergyNJ[pid], energyNJ >= previous {
                deltaNJ += Double(energyNJ - previous)
            }
        }

        let elapsed = previousEnergySampleAt.map { now.timeIntervalSince($0) } ?? 0
        previousAppEnergyNJ = current
        previousEnergySampleAt = now

        guard elapsed > 0.25, elapsed < 4 else {
            return latestAverageWatts()
        }

        let instantWatts = max(0, deltaNJ / elapsed / 1_000_000_000)
        recentAppWatts.append(instantWatts)
        if recentAppWatts.count > energyRollingWindow {
            recentAppWatts.removeFirst()
        }
        return latestAverageWatts()
    }

    private func latestAverageWatts() -> MacEnergyReading {
        guard !recentAppWatts.isEmpty else { return .unavailable }
        let average = recentAppWatts.reduce(0, +) / Double(recentAppWatts.count)
        return .watts(average)
    }

    private func processEnergyNanojoules(pid: pid_t) -> UInt64? {
        var words = [UInt64](repeating: 0, count: rusageV6WordCount)
        let status = words.withUnsafeMutableBufferPointer { buffer -> Int32 in
            guard let base = buffer.baseAddress else { return -1 }
            return base.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { pointer in
                proc_pid_rusage(pid, rusageFlavorV6, pointer)
            }
        }
        guard status == 0 else { return nil }
        return words[energyNJWordIndex]
    }
}
