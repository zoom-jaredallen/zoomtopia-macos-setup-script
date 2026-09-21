import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif

final class AcquisitionTests: XCTestCase {
    func testRetriesOnlyTransientFailuresAndStopsAfterThreeAttempts() {
        XCTAssertTrue(DownloadPolicy.shouldRetry(URLError(.timedOut), attempt: 1))
        XCTAssertFalse(DownloadPolicy.shouldRetry(URLError(.timedOut), attempt: 3))
        XCTAssertFalse(DownloadPolicy.shouldRetry(URLError(.cancelled), attempt: 1))
        XCTAssertFalse(DownloadPolicy.shouldRetry(URLError(.serverCertificateUntrusted), attempt: 1))
        XCTAssertFalse(DownloadPolicy.shouldRetry(SetupFailure("bad hash"), attempt: 1))
    }
    func testLockPreventsConcurrentPreparationAndCanBeReacquired() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var lock: RunLock? = try RunLock(url: root.appendingPathComponent("lock"))
        XCTAssertThrowsError(try RunLock(url: root.appendingPathComponent("lock")))
        XCTAssertTrue(lock != nil)
        lock = nil
        XCTAssertNoThrow(try RunLock(url: root.appendingPathComponent("lock")))
    }
    func testResourceManifestRejectsUnlistedConfiguration() throws {
        let manifest = ResourceManifest(files: [ResourceEntry(path: "assets/wallpaper.jpg", sha256: String(repeating: "a", count: 64), size: 3)])
        XCTAssertThrowsError(try manifest.validate())
    }
}
