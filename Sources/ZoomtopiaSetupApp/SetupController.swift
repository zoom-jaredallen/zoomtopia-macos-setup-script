import AppKit
import Foundation

enum StepState: String, Codable {
    case pending, running, passed, skipped, warning, failed, actionRequired
}

enum AppPhase {
    case setup
    case permissions
    case ready
}

struct SetupStep: Identifiable, Codable {
    let id: String
    var title: String
    var state: StepState
    var detail: String
}

private struct StatusEvent: Decodable {
    let id: String
    let title: String
    let state: StepState
    let detail: String
    let index: Int
    let total: Int
}

private struct CommandResult {
    let exitCode: Int32
    let output: String
}

@MainActor
final class SetupController: ObservableObject {
    @Published var steps: [SetupStep] = SetupController.initialSteps
    @Published var isRunning = false
    @Published var isComplete = false
    @Published var showingError = false
    @Published var errorMessage = ""
    @Published var phase: AppPhase = .setup
    @Published var confirmedPermissionIDs: Set<String> = []

    private var completedCount = 0
    private var totalCount = SetupController.initialSteps.count
    private var statusURL: URL?

    static let logPath = "/var/log/zoomtopia-setup.log"

    init() {
        if ProcessInfo.processInfo.environment["ZOOMTOPIA_READY_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--ready-preview") {
            phase = .ready
            isComplete = true
        } else if ProcessInfo.processInfo.environment["ZOOMTOPIA_PERMISSION_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--permission-preview") {
            phase = .permissions
            isComplete = true
        }
    }

    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var summary: String {
        if isRunning { return "Setup is running. Keep this Mac connected to power." }
        if isComplete {
            if steps.contains(where: { $0.state == .failed }) { return "Setup finished with errors. Review the failed steps." }
            if hasActionRequired { return "Automated setup finished. Privacy approval is still required." }
            return "Setup completed successfully."
        }
        return "Install and configure this Mac from the attached USB payload."
    }

    var hasActionRequired: Bool {
        steps.contains { $0.state == .actionRequired }
    }

    var allPermissionStepsConfirmed: Bool {
        Self.requiredPermissionIDs.isSubset(of: confirmedPermissionIDs)
    }

    var zoomApplicationURL: URL? {
        ["/Applications/zoom.us.app", "/Applications/Zoom Workplace.app"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var logExists: Bool {
        FileManager.default.fileExists(atPath: Self.logPath)
    }

    func start() {
        guard !isRunning else { return }

        let payloadURL = resolvePayloadURL()
        let scriptURL = resolveBootstrapURL()
        guard FileManager.default.fileExists(atPath: payloadURL.appendingPathComponent("config/setup-config.json").path) else {
            presentError("The payload was not found at \(payloadURL.path). Place the ZoomtopiaPayload folder beside the app.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            presentError("The bundled setup script is missing or not executable.")
            return
        }

        steps = Self.initialSteps
        phase = .setup
        confirmedPermissionIDs = []
        completedCount = 0
        totalCount = steps.count
        isRunning = true
        isComplete = false

        let status = FileManager.default.temporaryDirectory
            .appendingPathComponent("zoomtopia-status-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: status.path, contents: Data())
        statusURL = status

        let command = [
            "/bin/bash", scriptURL.path,
            "--payload", payloadURL.path,
            "--status", status.path,
            "--log", Self.logPath
        ].map(Self.shellQuote).joined(separator: " ")
        let appleScript = "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges"

        Task {
            let monitor = Task { await monitorStatus(at: status) }
            let result = await Task.detached(priority: .userInitiated) {
                Self.runAppleScript(appleScript)
            }.value
            monitor.cancel()
            await readStatus(at: status)
            isRunning = false
            isComplete = true
            if result.exitCode != 0 && !steps.contains(where: { $0.state == .failed }) {
                presentError(result.output.isEmpty ? "Setup was cancelled or failed." : result.output)
            } else if !steps.contains(where: { $0.state == .failed }) {
                phase = .permissions
            }
        }
    }

    func showPermissionAssistant() {
        guard isComplete else { return }
        phase = .permissions
    }

    func setPermissionConfirmed(_ id: String, confirmed: Bool) {
        if confirmed {
            confirmedPermissionIDs.insert(id)
        } else {
            confirmedPermissionIDs.remove(id)
        }
    }

    func finishPermissionAssistant() {
        guard allPermissionStepsConfirmed else { return }
        if let index = steps.firstIndex(where: { $0.id == "privacy" }) {
            steps[index].state = .passed
            steps[index].detail = "Camera, Microphone, and Screen Recording confirmed by the operator"
        }
        if let index = steps.firstIndex(where: { $0.id == "verify" }), steps[index].state != .failed {
            steps[index].state = .passed
            steps[index].detail = "Automated checks passed and Zoom tests were confirmed"
        }
        phase = .ready
    }

    func returnToSetupSummary() {
        phase = .setup
    }

    func launchZoom() {
        guard let url = zoomApplicationURL else {
            presentError("Zoom Workplace is not installed yet.")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                Task { @MainActor in self.presentError(error.localizedDescription) }
            }
        }
    }

    func openZoomTest() {
        guard let url = URL(string: "https://zoom.us/test") else { return }
        NSWorkspace.shared.open(url)
    }

    func openCameraSettings() {
        openSystemSettings(anchor: "Privacy_Camera")
    }

    func openMicrophoneSettings() {
        openSystemSettings(anchor: "Privacy_Microphone")
    }

    func openScreenRecordingSettings() {
        openSystemSettings(anchor: "Privacy_ScreenCapture")
    }

    func revealPayload() {
        NSWorkspace.shared.activateFileViewerSelecting([resolvePayloadURL()])
    }

    func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Self.logPath))
    }

    func openPrivacySettings() {
        openScreenRecordingSettings()
    }

    private func openSystemSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func monitorStatus(at url: URL) async {
        while !Task.isCancelled {
            await readStatus(at: url)
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
    }

    private func readStatus(at url: URL) async {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }

        var latest: [String: StatusEvent] = [:]
        for line in text.split(separator: "\n") {
            guard let eventData = line.data(using: .utf8),
                  let event = try? JSONDecoder().decode(StatusEvent.self, from: eventData) else { continue }
            latest[event.id] = event
        }

        for event in latest.values {
            totalCount = max(totalCount, event.total)
            if let index = steps.firstIndex(where: { $0.id == event.id }) {
                steps[index].title = event.title
                steps[index].state = event.state
                steps[index].detail = event.detail
            }
        }
        completedCount = latest.values.filter { $0.state != .pending && $0.state != .running }.count
    }

    private func resolvePayloadURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["ZOOMTOPIA_PAYLOAD_ROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("ZoomtopiaPayload", isDirectory: true)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ZoomtopiaPayload", isDirectory: true)
    }

    private func resolveBootstrapURL() -> URL {
        if let resourceURL = Bundle.main.resourceURL {
            let bundled = resourceURL.appendingPathComponent("bootstrap.sh")
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Scripts/bootstrap.sh")
    }

    private func presentError(_ message: String) {
        errorMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        showingError = true
    }

    nonisolated private static func runAppleScript(_ source: String) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return CommandResult(exitCode: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
        } catch {
            return CommandResult(exitCode: 1, output: error.localizedDescription)
        }
    }

    nonisolated private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    nonisolated private static func appleScriptLiteral(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static let initialSteps: [SetupStep] = [
        .init(id: "validate", title: "Validate Mac", state: .pending, detail: ""),
        .init(id: "payload", title: "Verify USB payload", state: .pending, detail: ""),
        .init(id: "chrome", title: "Install Google Chrome", state: .pending, detail: ""),
        .init(id: "zoom", title: "Install Zoom Workplace", state: .pending, detail: ""),
        .init(id: "zoom-config", title: "Configure Zoom Workplace", state: .pending, detail: ""),
        .init(id: "trackpad", title: "Configure trackpad", state: .pending, detail: ""),
        .init(id: "wallpaper", title: "Set Zoomtopia wallpaper", state: .pending, detail: ""),
        .init(id: "aliases", title: "Create desktop icons", state: .pending, detail: ""),
        .init(id: "privacy", title: "Stage Zoom privacy permissions", state: .pending, detail: ""),
        .init(id: "updates", title: "Install macOS updates", state: .pending, detail: ""),
        .init(id: "verify", title: "Final verification", state: .pending, detail: "")
    ]

    private static let requiredPermissionIDs: Set<String> = [
        "camera", "microphone", "screen-recording", "audio-test"
    ]
}
