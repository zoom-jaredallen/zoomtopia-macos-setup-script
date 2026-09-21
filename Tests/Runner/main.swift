import Foundation

class XCTestCase {}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { if try !value() { fatalError("Expected true: \(message)", file: file, line: line) } } catch { fatalError("Unexpected error: \(error)") }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { if try value() { fatalError("Expected false: \(message)", file: file, line: line) } } catch { fatalError("Unexpected error: \(error)") }
}
func XCTAssertEqual<T: Equatable>(_ value: @autoclosure () throws -> T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    do { if try value() != expected { fatalError("Values differ", file: file, line: line) } } catch { fatalError("Unexpected error: \(error)") }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    do { _ = try value() } catch { return }
    fatalError("Expected error: \(message)", file: file, line: line)
}
func XCTAssertNoThrow<T>(_ value: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try value() } catch { fatalError("Unexpected error: \(error)", file: file, line: line) }
}

do {
    try SigningTests().testRunningIdentityRejectsAnotherExecutable()
    try LatestPackageTests().testSignedMetadataSelectsEachAppAndRejectsAmbiguity()
    let policy = PolicyTests()
    try policy.testVersionPolicyNeverDowngrades()
    try policy.testRejectsUnsafeRelativePathsAndURLs()
    try policy.testCopyRejectsSymlinkAndHashMismatch()
    policy.testReadinessRequiresAllTerminalStepsAndNoBlockingWarnings()
    let acquisition = AcquisitionTests()
    acquisition.testRetriesOnlyTransientFailuresAndStopsAfterThreeAttempts()
    try acquisition.testLockPreventsConcurrentPreparationAndCanBeReacquired()
    try acquisition.testResourceManifestRejectsUnlistedConfiguration()
    print("PASS: policy, URL/path validation, verified copy, and readiness tests")
} catch { fatalError(error.localizedDescription) }
let completed = DispatchSemaphore(value: 0)
Task {
    do {
        let downloads = DownloadTests()
        try await downloads.testTransportFailureDoesNotPromoteAFile()
        try await downloads.testAlreadyCancelledDownloadDoesNotCreateAFile()
        print("PASS: transport failure and cancellation leave no promoted package")
    } catch { fatalError(error.localizedDescription) }
    completed.signal()
}
guard completed.wait(timeout: .now() + 15) == .success else { fatalError("Download tests timed out") }
