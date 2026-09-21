import AppKit
import Foundation
#if canImport(SetupCore)
import SetupCore
#endif

enum StepState: String, Codable {
    case pending, running, passed, skipped, warning, failed, actionRequired, notRun
}

enum AppPhase {
    case setup
    case permissions
    case ready
}

struct SetupStep: Identifiable, Codable, Equatable {
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
    @Published var mode: SetupMode = .full
    @Published var pendingMode: SetupMode = .full
    @Published var showingPreflight = false
    @Published var isCheckingUpdates = false
    @Published var isApplyingWallpaper = false
    @Published var needsRevalidation = false
    @Published var restartBoot: String? = UserDefaults.standard.string(forKey: "restartBoot")
    private let currentBoot: String = {
        var boot = timeval(); var length = MemoryLayout<timeval>.size
        return sysctlbyname("kern.boottime", &boot, &length, nil, 0) == 0 ? String(boot.tv_sec) : "unknown"
    }()
    private var preview = false
    private struct SavedSummary: Codable {
        let schema: Int
        let mode: SetupMode
        let steps: [SetupStep]
    }
    private var busy: Bool { isRunning || isCheckingUpdates || isApplyingWallpaper }
    @Published var isRunning = false
    @Published var isPreparing = false
    @Published var preparationDetail = ""
    @Published var downloadProgress = 0.0
    @Published var offlinePayloadURL: URL?
    private var setupTask: Task<Void, Never>?
    private var provisioningExitCode: Int32?
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
        if let data = UserDefaults.standard.data(forKey: "setupSummary"),
           let saved = try? JSONDecoder().decode(SavedSummary.self, from: data), saved.schema == 1,
           Set(saved.steps.map(\.id)) == Set(Self.initialSteps.map(\.id)) {
            mode = saved.mode; steps = saved.steps; needsRevalidation = true; isComplete = true
        }
        #if ZOOMTOPIA_DEVELOPMENT
        if ProcessInfo.processInfo.environment["ZOOMTOPIA_READY_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--ready-preview") {
            preview = true; needsRevalidation = false; restartBoot = nil; mode = .full
            steps = Self.initialSteps.map { SetupStep(id: $0.id, title: $0.title, state: .passed, detail: "Preview only") }
            provisioningExitCode = 0
            confirmedPermissionIDs = Readiness.requiredChecks
            phase = .ready
            isComplete = true
        } else if ProcessInfo.processInfo.environment["ZOOMTOPIA_PERMISSION_PREVIEW"] == "1"
            || ProcessInfo.processInfo.arguments.contains("--permission-preview") {
            preview = true; needsRevalidation = false; restartBoot = nil; mode = .full
            steps = Self.initialSteps.map { SetupStep(id: $0.id, title: $0.title, state: .passed, detail: "Preview only") }
            provisioningExitCode = 0
            phase = .permissions
            isComplete = true
        }
        #endif
    }

    var isPreview: Bool { preview }

    var isBusy: Bool { busy }
    var canOpenPermissions: Bool {
        WorkflowPolicy.canOpenPermissions(zoomState: steps.first(where: { $0.id == "zoom" })?.state.rawValue, running: busy)
            && !needsRevalidation
    }
    var updatesNeedAttention: Bool {
        steps.contains { $0.id == "updates" && [.warning, .failed, .actionRequired].contains($0.state) }
    }
    var permissionFooterDetail: String {
        if mode == .limited { return "Limited test — readiness is disabled" }
        if needsRevalidation { return "Revalidate this Mac before marking ready" }
        if !provisioningPassed { return "Resolve remaining setup items before marking ready" }
        return allPermissionStepsConfirmed ? "All Zoom checks confirmed" : "Complete all four checks"
    }
    var preflightDetail: String {
        if pendingMode == .limited {
            return "Install or upgrade Chrome and Zoom from their signed vendor installers. Wallpaper, trackpad, managed Zoom preferences, Desktop shortcuts, profiles and macOS updates are excluded. Administrator authorization is still required. This test cannot mark a lab Mac ready."
        }
        return "Install or upgrade Chrome and Zoom; apply the bundled Zoom preferences and wallpaper; enable bottom-right secondary click; add Desktop shortcuts; and check for approved software updates. OS installation and restart take place visibly in Apple Software Update. Major OS upgrades are excluded by default. Privacy approvals and OS authorization may require additional interaction."
    }
    var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(completedCount) / Double(totalCount)
    }

    var summary: String {
        if isCheckingUpdates { return "Checking approved updates; no software is being installed." }
        if needsRevalidation && !isRunning { return "Previous run restored. Run setup to revalidate this Mac; saved results do not establish readiness." }
        if isPreparing { return preparationDetail }
        if isRunning { return steps.first(where: { $0.state == .running }).map { "\($0.title): \($0.detail)" } ?? "Waiting for administrator authorization. Keep this Mac connected to power." }
        if isComplete {
            if steps.contains(where: { $0.state == .failed }) { return "Setup finished with errors. Review the failed steps." }
            if !provisioningPassed { return "Resolve the warnings or incomplete steps, then run setup again." }
            if hasActionRequired { return "Automated setup finished. Privacy approval is still required." }
            return "Setup completed successfully."
        }
        return offlinePayloadURL == nil ? "Check current Chrome and Zoom versions, upgrade if needed, and configure this Mac." : "Use approved installers from the selected offline payload."
    }

    var hasActionRequired: Bool {
        steps.contains { $0.state == .actionRequired }
    }

    var provisioningPassed: Bool {
        Readiness.provisioningPassed(exitCode: provisioningExitCode, states: Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0.state.rawValue) }), requiredSteps: Set(Self.initialSteps.map(\.id)))
    }
    var allPermissionStepsConfirmed: Bool {
        WorkflowPolicy.canFinish(mode: mode, needsRevalidation: needsRevalidation, restartBoot: restartBoot, currentBoot: currentBoot, exitCode: provisioningExitCode, states: Dictionary(uniqueKeysWithValues: steps.map { ($0.id, $0.state.rawValue) }), requiredSteps: Set(Self.initialSteps.map(\.id)), confirmations: confirmedPermissionIDs)
    }

    var zoomApplicationURL: URL? {
        ["/Applications/zoom.us.app", "/Applications/Zoom Workplace.app"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var logExists: Bool {
        FileManager.default.fileExists(atPath: Self.logPath)
    }

    func requestStart() { guard !preview, !busy else { return }; pendingMode = mode; showingPreflight = true }

    func start() {
        guard !preview, !busy else { return }
        showingPreflight = false
        mode = pendingMode
        needsRevalidation = false
        guard let resources = Bundle.main.resourceURL,
              FileManager.default.isExecutableFile(atPath: resources.appendingPathComponent("PayloadVerifier").path) else {
            presentError("The setup app is incomplete. Build or download the complete app bundle.")
            return
        }
        steps = Self.initialSteps
        phase = .setup
        confirmedPermissionIDs = []
        provisioningExitCode = nil
        completedCount = 0
        isRunning = true
        isPreparing = true
        isComplete = false
        downloadProgress = 0
        preparationDetail = "Checking current installers…"
        let offline = offlinePayloadURL ?? ProcessInfo.processInfo.environment["ZOOMTOPIA_PAYLOAD_ROOT"].map { URL(fileURLWithPath: $0) }
        setupTask = Task {
            var statusDirectory: URL?
            defer {
                isRunning = false; isPreparing = false; setupTask = nil
                if let statusDirectory { try? FileManager.default.removeItem(at: statusDirectory) }
                saveSummary()
            }
            do {
                let prepared = try await PayloadPreparation.prepare(resources: resources, offline: offline) { [weak self] _, detail, fraction in
                    Task { @MainActor in
                        guard let self, self.isPreparing else { return }
                        self.preparationDetail = detail; self.downloadProgress = fraction
                    }
                }
                defer { withExtendedLifetime(prepared) {} }
                try Task.checkCancellation()
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zoomtopia-status-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
                statusDirectory = directory
                let status = directory.appendingPathComponent("events.jsonl")
                guard FileManager.default.createFile(atPath: status.path, contents: Data(), attributes: [.posixPermissions: 0o600]) else { throw SetupFailure("Cannot create status file") }
                statusURL = status
                isPreparing = false
                // Snapshot the entire signed bundle under root ownership, verify the snapshot,
                // then execute only that immutable copy across the privilege boundary.
                let requirement = try SigningIdentity.runningRequirement()
                let command = "set -eu; snapshot=$(/usr/bin/mktemp -d /private/var/tmp/zoomtopia-app.XXXXXX); "
                    + "trap '/bin/rm -rf \"$snapshot\"' EXIT; "
                    + "/usr/bin/ditto " + Self.shellQuote(Bundle.main.bundleURL.path) + " \"$snapshot/Setup.app\"; "
                    + "/usr/bin/codesign --verify --deep --strict \"$snapshot/Setup.app\"; "
                    + "/usr/bin/codesign --verify --strict --architecture " + SigningIdentity.runningArchitecture + " -R " + Self.shellQuote("=" + requirement) + " \"$snapshot/Setup.app\"; "
                    + "\"$snapshot/Setup.app/Contents/Resources/PayloadVerifier\" --run " + Self.shellQuote(prepared.url.path) + " " + Self.shellQuote(status.path) + " " + Self.shellQuote(mode.rawValue)
                let appleScript = "do shell script \(Self.appleScriptLiteral(command)) with administrator privileges"
                let monitor = Task { await monitorStatus(at: status) }
                let result = await Task.detached(priority: .userInitiated) { Self.runAppleScript(appleScript) }.value
                monitor.cancel()
                await readStatus(at: status)
                provisioningExitCode = result.exitCode
                isComplete = true
                if mode == .full, result.exitCode == 0 {
                    if steps.first(where: { $0.id == "wallpaper" })?.state == .actionRequired { await applyWallpaper() }
                    enforceRestartCheckpoint()
                    reconcileVerification()
                }
                if result.exitCode != 0 {
                    presentError(result.output.isEmpty ? "Setup was cancelled or failed. Review the setup summary and log." : result.output)
                } else if provisioningPassed && mode == .full {
                    phase = .permissions
                }
            } catch is CancellationError {
                preparationDetail = "Preparation cancelled. Temporary downloads have been removed."
            } catch {
                isComplete = true
                if let index = steps.firstIndex(where: { $0.id == "payload" }) {
                    steps[index].state = .failed; steps[index].detail = error.localizedDescription
                }
                presentError(error.localizedDescription)
            }
        }
    }

    func cancelPreparation() { if isPreparing { setupTask?.cancel() } }

    func chooseOfflinePayload() {
        guard !isRunning else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.message = "Choose a payload containing the approved installer packages. Configuration comes from this signed app."
        if panel.runModal() == .OK { offlinePayloadURL = panel.url }
    }

    func showPermissionAssistant() {
        guard canOpenPermissions else { return }
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
        saveSummary()
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

        let previous = steps
        for event in latest.values {
            totalCount = max(totalCount, event.total)
            if let index = steps.firstIndex(where: { $0.id == event.id }) {
                steps[index].title = event.title
                steps[index].state = event.state
                steps[index].detail = event.detail
            }
        }
        completedCount = latest.values.filter { $0.state != .pending && $0.state != .running }.count
        if previous != steps { saveSummary() }
    }

    func retryWallpaper() {
        guard !preview, !busy, mode == .full else { return }
        isApplyingWallpaper = true
        Task { await applyWallpaper() }
    }

    private func applyWallpaper() async {
        defer { isApplyingWallpaper = false }
        guard mode == .full, let resources = Bundle.main.resourceURL else { return }
        isApplyingWallpaper = true
        setStep("wallpaper", .running, "Applying wallpaper to connected displays")
        do {
            try await Wallpaper.apply(resources: resources)
            setStep("wallpaper", .passed, "Wallpaper applied and verified on connected displays")
        } catch { setStep("wallpaper", .warning, error.localizedDescription) }
        reconcileVerification(); saveSummary()
    }

    func openSoftwareUpdate() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Software-Update-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func recordRestartRequest() {
        guard !preview, !busy, mode == .full else { return }
        restartBoot = currentBoot
        if !preview { UserDefaults.standard.set(currentBoot, forKey: "restartBoot") }
        setStep("updates", .actionRequired, "Operator confirmed macOS requests a restart. Save your work and restart in Software Update, then reopen setup and recheck.")
        reconcileVerification(); saveSummary()
    }

    func checkUpdates() {
        guard !preview, !busy, (mode == .full || (showingPreflight && pendingMode == .full)), let helper = Bundle.main.resourceURL?.appendingPathComponent("PayloadVerifier") else { return }
        isCheckingUpdates = true
        setStep("updates", .running, "Checking current-major OS and recommended application updates")
        Task {
            defer { isCheckingUpdates = false; saveSummary() }
            do {
                let result = try await Task.detached { try Command.run(helper.path, ["--check-updates"]) }.value
                guard result.0 == 0, let data = result.1.data(using: .utf8),
                      let object = try JSONSerialization.jsonObject(with: data) as? [String: String],
                      let rawState = object["state"], let state = StepState(rawValue: rawState),
                      [.passed, .warning, .actionRequired, .failed].contains(state), let detail = object["detail"] else {
                    throw SetupFailure("Update check could not be completed. Open Software Update or retry.")
                }
                setStep("updates", state, detail)
                enforceRestartCheckpoint()
            } catch { setStep("updates", .warning, error.localizedDescription) }
            reconcileVerification()
        }
    }

    private func enforceRestartCheckpoint() {
        guard let restartBoot else { return }
        if restartBoot == currentBoot || currentBoot == "unknown" {
            setStep("updates", .actionRequired, "Restart still required: macOS restart was confirmed during this boot. Restart through Software Update and recheck afterward.")
        } else if steps.first(where: { $0.id == "updates" })?.state == .passed {
            self.restartBoot = nil
            if !preview { UserDefaults.standard.removeObject(forKey: "restartBoot") }
        }
    }

    private func setStep(_ id: String, _ state: StepState, _ detail: String) {
        if let index = steps.firstIndex(where: { $0.id == id }) { steps[index].state = state; steps[index].detail = detail }
    }

    private func reconcileVerification() {
        guard provisioningExitCode == 0 else { return }
        let outstanding = steps.filter { step in
            !["verify", "privacy"].contains(step.id) && ![.passed, .skipped].contains(step.state)
        }
        if mode == .limited {
            setStep("verify", .actionRequired, "Limited test completed; full setup is required for readiness")
        } else if outstanding.isEmpty {
            setStep("verify", .actionRequired, "Automated checks passed; complete the four Zoom confirmations")
        } else {
            setStep("verify", .warning, "Resolve: " + outstanding.map(\.title).joined(separator: ", "))
        }
    }

    private func saveSummary() {
        guard !preview, let data = try? JSONEncoder().encode(SavedSummary(schema: 1, mode: mode, steps: steps)) else { return }
        UserDefaults.standard.set(data, forKey: "setupSummary")
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
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
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
        .init(id: "payload", title: "Verify prepared payload", state: .pending, detail: ""),
        .init(id: "chrome", title: "Install Google Chrome", state: .pending, detail: ""),
        .init(id: "zoom", title: "Install Zoom Workplace", state: .pending, detail: ""),
        .init(id: "zoom-config", title: "Configure Zoom Workplace", state: .pending, detail: ""),
        .init(id: "trackpad", title: "Configure trackpad", state: .pending, detail: ""),
        .init(id: "wallpaper", title: "Set Zoomtopia wallpaper", state: .pending, detail: ""),
        .init(id: "aliases", title: "Create desktop icons", state: .pending, detail: ""),
        .init(id: "privacy", title: "Stage Zoom privacy permissions", state: .pending, detail: ""),
        .init(id: "updates", title: "Check macOS updates", state: .pending, detail: ""),
        .init(id: "verify", title: "Final verification", state: .pending, detail: "")
    ]

}
