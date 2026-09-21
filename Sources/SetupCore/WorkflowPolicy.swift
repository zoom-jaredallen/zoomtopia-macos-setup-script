import Foundation

public enum SetupMode: String, Codable {
    case full, limited
    public var allowsReadiness: Bool { self == .full }
}

/// Persistence is a recovery hint, never proof that this Mac is still provisioned.
public enum WorkflowPolicy {
    public static func canOpenPermissions(zoomState: String?, running: Bool) -> Bool {
        !running && ["passed", "skipped"].contains(zoomState ?? "")
    }
    public static func canFinish(mode: SetupMode, needsRevalidation: Bool, restartBoot: String?, currentBoot: String,
                                 exitCode: Int32?, states: [String: String], requiredSteps: Set<String>, confirmations: Set<String>) -> Bool {
        mode.allowsReadiness && !needsRevalidation && restartBoot == nil
            && Readiness.canFinish(exitCode: exitCode, states: states, requiredSteps: requiredSteps, confirmations: confirmations)
    }
}
