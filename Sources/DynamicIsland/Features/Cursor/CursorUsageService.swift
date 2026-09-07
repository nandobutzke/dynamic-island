import Foundation

actor CursorUsageService {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchUsage(sessionToken: String) async throws -> CursorUsageSnapshot {
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else {
            throw CursorUsageError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(
            "WorkosCursorSessionToken=\(sessionToken)",
            forHTTPHeaderField: "Cookie"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CursorUsageError.invalidResponse
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw CursorUsageError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw CursorUsageError.httpStatus(http.statusCode)
        }

        return try Self.parse(data: data)
    }

    static func parse(data: Data) throws -> CursorUsageSnapshot {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorUsageError.decodeFailed
        }

        let membership = (json["membershipType"] as? String) ?? "pro"
        let isUnlimited = (json["isUnlimited"] as? Bool) ?? false

        var autoPercent: Double?
        var apiPercent: Double?
        var onDemandEnabled = false

        // Shape A: planUsage at root (Connect / dashboard variants)
        if let planUsage = json["planUsage"] as? [String: Any] {
            autoPercent = double(from: planUsage["autoPercentUsed"])
            apiPercent = double(from: planUsage["apiPercentUsed"])
        }

        // Shape B: individualUsage.plan (usage-summary)
        if let individual = json["individualUsage"] as? [String: Any] {
            if let plan = individual["plan"] as? [String: Any] {
                autoPercent = autoPercent ?? double(from: plan["autoPercentUsed"])
                apiPercent = apiPercent ?? double(from: plan["apiPercentUsed"])
            }
            if let onDemand = individual["onDemand"] as? [String: Any] {
                onDemandEnabled = (onDemand["enabled"] as? Bool) ?? false
            }
        }

        // Shape C: flat percentages on root
        autoPercent = autoPercent
            ?? double(from: json["autoPercentUsed"])
            ?? double(from: json["cursorModelsPercentUsed"])
        apiPercent = apiPercent
            ?? double(from: json["apiPercentUsed"])
            ?? double(from: json["namedPercentUsed"])

        // Fallback: parse display messages like "You've used 75% of ..."
        if autoPercent == nil {
            autoPercent = percent(fromMessage: json["autoModelSelectedDisplayMessage"] as? String)
        }
        if apiPercent == nil {
            apiPercent = percent(fromMessage: json["namedModelSelectedDisplayMessage"] as? String)
        }

        let cursorModels = clamp(autoPercent ?? 0)
        let otherModels = clamp(apiPercent ?? 0)

        let cycleEnd = parseDate(jsonValue(json, key: "billingCycleEnd"))
            ?? parseDate(jsonValue(json, key: "billingCycleStart")).flatMap {
                Calendar.current.date(byAdding: .month, value: 1, to: $0)
            }

        return CursorUsageSnapshot(
            membershipType: membership,
            cursorModelsPercent: cursorModels,
            otherModelsPercent: otherModels,
            billingCycleEnd: cycleEnd,
            onDemandEnabled: onDemandEnabled,
            isUnlimited: isUnlimited,
            fetchedAt: Date()
        )
    }

    private static func jsonValue(_ json: [String: Any], key: String) -> String? {
        if let s = json[key] as? String, !s.isEmpty { return s }
        if let n = json[key] as? NSNumber { return n.stringValue }
        return nil
    }

    private static func double(from value: Any?) -> Double? {
        switch value {
        case let n as Double: return n
        case let n as Int: return Double(n)
        case let n as NSNumber: return n.doubleValue
        case let s as String: return Double(s)
        default: return nil
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private static func percent(fromMessage message: String?) -> Double? {
        guard let message else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)\s*%"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(message.startIndex..., in: message)
        guard let match = regex.firstMatch(in: message, range: range),
              let swiftRange = Range(match.range(at: 1), in: message) else { return nil }
        return Double(message[swiftRange])
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        if let ms = Double(raw), ms > 1_000_000_000_000 {
            return Date(timeIntervalSince1970: ms / 1000)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

enum CursorUsageError: LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case httpStatus(Int)
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Cursor API URL."
        case .invalidResponse: return "Invalid response from Cursor."
        case .unauthorized: return "Cursor session expired. Sign in again."
        case .httpStatus(let code): return "Cursor API error (\(code))."
        case .decodeFailed: return "Could not parse Cursor usage."
        }
    }
}
