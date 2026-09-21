import Foundation

@main
struct PreviewTests {
    @MainActor static func main() {
        let savedSummary = UserDefaults.standard.data(forKey: "setupSummary")
        let savedRestart = UserDefaults.standard.string(forKey: "restartBoot")
        let controller = SetupController()
        #if ZOOMTOPIA_DEVELOPMENT
        precondition(controller.isPreview)
        if ProcessInfo.processInfo.arguments.contains("--ready-preview") || ProcessInfo.processInfo.environment["ZOOMTOPIA_READY_PREVIEW"] == "1" {
            precondition(controller.phase == .ready)
        } else {
            precondition(controller.phase == .permissions)
            precondition(!controller.allPermissionStepsConfirmed)
            let checks = Readiness.requiredChecks.sorted()
            for (index, check) in checks.enumerated() {
                controller.setPermissionConfirmed(check, confirmed: true)
                precondition(controller.allPermissionStepsConfirmed == (index == checks.count - 1))
            }
            controller.finishPermissionAssistant()
            precondition(controller.phase == .ready)
        }
        controller.returnToSetupSummary()
        let steps = controller.steps
        controller.requestStart()
        controller.start()
        controller.retryWallpaper()
        controller.checkUpdates()
        controller.recordRestartRequest()
        precondition(!controller.isBusy && !controller.isPreparing && !controller.showingPreflight)
        precondition(controller.steps == steps && controller.restartBoot == nil)
        #else
        precondition(!controller.isPreview && controller.phase == .setup)
        #endif
        precondition(UserDefaults.standard.data(forKey: "setupSummary") == savedSummary)
        precondition(UserDefaults.standard.string(forKey: "restartBoot") == savedRestart)
        print("Preview isolation passed")
    }
}
