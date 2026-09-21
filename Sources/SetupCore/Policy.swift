import Foundation

public struct SetupFailure: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public enum PackageDecision: Equatable { case install, skip, blocked }

public enum PackagePolicy {
    public static func decision(installed: String?, approved: String) throws -> PackageDecision {
        let target = try version(approved)
        guard let installed else { return .install }
        let current = try version(installed)
        for i in 0..<max(current.count, target.count) {
            let lhs = i < current.count ? current[i] : 0
            let rhs = i < target.count ? target[i] : 0
            if lhs < rhs { return .install }
            if lhs > rhs { return .blocked }
        }
        return .skip
    }
    private static func version(_ text: String) throws -> [Int] {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 8,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { throw SetupFailure("Invalid version: \(text)") }
        return parts.map { Int($0)! }
    }
}

public enum DownloadPolicy {
    public static func allows(_ url: URL, hosts: [String]) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && url.fragment == nil
            && (url.port == nil || url.port == 443) && hosts.contains(url.host?.lowercased() ?? "")
    }
    public static func shouldRetry(_ error: Error, attempt: Int) -> Bool {
        guard attempt < 3 else { return false }
        guard let error = error as? URLError else { return false }
        return [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet, .dnsLookupFailed].contains(error.code)
    }
}

public enum Readiness {
    public static let requiredChecks: Set<String> = ["camera", "microphone", "screen-recording", "audio-test"]
    public static func provisioningPassed(exitCode: Int32?, states: [String: String], requiredSteps: Set<String>) -> Bool {
        guard exitCode == 0, requiredSteps.isSubset(of: Set(states.keys)) else { return false }
        return requiredSteps.allSatisfy { id in
            guard let state = states[id] else { return false }
            return state == "passed" || state == "skipped" || (["privacy", "verify"].contains(id) && state == "actionRequired")
        }
    }
    public static func canFinish(exitCode: Int32?, states: [String: String], requiredSteps: Set<String>, confirmations: Set<String>) -> Bool {
        provisioningPassed(exitCode: exitCode, states: states, requiredSteps: requiredSteps)
            && requiredChecks.isSubset(of: confirmations)
    }
}
