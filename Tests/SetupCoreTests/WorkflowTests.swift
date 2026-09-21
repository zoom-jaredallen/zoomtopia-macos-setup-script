import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif
final class WorkflowTests: XCTestCase {
    func testWarningsDoNotBlockPermissionAccessButStillBlockReadiness() {
        XCTAssertTrue(WorkflowPolicy.canOpenPermissions(zoomState: "passed", running: false))
        XCTAssertTrue(WorkflowPolicy.canOpenPermissions(zoomState: "skipped", running: false))
        XCTAssertFalse(WorkflowPolicy.canOpenPermissions(zoomState: "failed", running: false))
        XCTAssertFalse(WorkflowPolicy.canOpenPermissions(zoomState: "notRun", running: false))
        XCTAssertFalse(WorkflowPolicy.canOpenPermissions(zoomState: "passed", running: true))
        let states = ["zoom": "passed", "wallpaper": "warning", "updates": "actionRequired"]
        XCTAssertFalse(WorkflowPolicy.canFinish(mode: .full, needsRevalidation: false, restartBoot: nil, currentBoot: "boot1", exitCode: 0, states: states, requiredSteps: Set(states.keys), confirmations: Readiness.requiredChecks))
    }
    func testLimitedRestoredAndSameBootRunsCannotClaimReady() {
        let states = ["zoom": "passed", "wallpaper": "passed", "updates": "passed"]
        func ready(_ mode: SetupMode, _ restored: Bool, _ boot: String?) -> Bool {
            WorkflowPolicy.canFinish(mode: mode, needsRevalidation: restored, restartBoot: boot, currentBoot: "boot1", exitCode: 0, states: states, requiredSteps: Set(states.keys), confirmations: Readiness.requiredChecks)
        }
        XCTAssertTrue(ready(.full, false, nil))
        XCTAssertFalse(ready(.limited, false, nil))
        XCTAssertFalse(ready(.full, true, nil))
        XCTAssertFalse(ready(.full, false, "boot1"))
        XCTAssertFalse(ready(.full, false, "previous-boot")) // A clean post-boot check must clear the checkpoint first.
    }
}
