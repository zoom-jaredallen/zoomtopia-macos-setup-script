import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif

final class PolicyTests: XCTestCase {
    func testVersionPolicyNeverDowngrades() throws {
        XCTAssertEqual(try PackagePolicy.decision(installed: nil, approved: "7.2.0.88195"), .install)
        XCTAssertEqual(try PackagePolicy.decision(installed: "7.1.9", approved: "7.2.0.88195"), .install)
        XCTAssertEqual(try PackagePolicy.decision(installed: "7.2.0.88195", approved: "7.2.0.88195"), .skip)
        XCTAssertEqual(try PackagePolicy.decision(installed: "7.10", approved: "7.2.0.88195"), .skip)
        XCTAssertEqual(try PackagePolicy.decision(installed: "153.0.8010.53", approved: "153.0.8010.53"), .skip)
        XCTAssertEqual(try PackagePolicy.decision(installed: "152.0.1", approved: "153.0.8010.53"), .install)
        XCTAssertEqual(try PackagePolicy.decision(installed: "154.0.1", approved: "153.0.8010.53"), .skip)
        XCTAssertThrowsError(try PackagePolicy.decision(installed: "unknown", approved: "7.2"))
    }
    func testRejectsUnsafeRelativePathsAndURLs() throws {
        for path in ["../outside", "/tmp/file", "assets/../../file", "assets//file", "assets/./file", "a\\b", "a\nfile"] {
            XCTAssertThrowsError(try SafeFiles.validateRelativePath(path), path)
        }
        XCTAssertNoThrow(try SafeFiles.validateRelativePath("assets/wallpaper.jpg"))
        XCTAssertTrue(DownloadPolicy.allows(URL(string: "https://cdn.zoom.us/prod/file.pkg")!, hosts: ["cdn.zoom.us"]))
        for url in ["http://cdn.zoom.us/file", "https://cdn.zoom.us.evil.test/file", "https://user@cdn.zoom.us/file", "https://cdn.zoom.us:444/file"] {
            XCTAssertFalse(DownloadPolicy.allows(URL(string: url)!, hosts: ["cdn.zoom.us"]))
        }
    }
    func testCopyRejectsSymlinkAndHashMismatch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("input")
        let output = root.appendingPathComponent("output")
        try Data("abc".utf8).write(to: input)
        let hash = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try SafeFiles.copyVerified(from: input, to: output, sha256: hash, maxBytes: 3)
        XCTAssertEqual(try Data(contentsOf: output), Data("abc".utf8))
        try FileManager.default.removeItem(at: output)
        XCTAssertThrowsError(try SafeFiles.copyVerified(from: input, to: output, sha256: String(repeating: "0", count: 64), maxBytes: 3))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        XCTAssertThrowsError(try SafeFiles.copyVerified(from: link, to: output, sha256: hash, maxBytes: 3))
        XCTAssertThrowsError(try SafeFiles.copyVerified(from: input, to: output, sha256: hash, maxBytes: 2))
    }
    func testReadinessRequiresAllTerminalStepsAndNoBlockingWarnings() {
        let checks: Set<String> = ["camera", "microphone", "screen-recording", "audio-test"]
        let good = ["validate": "passed", "privacy": "actionRequired", "verify": "actionRequired"]
        XCTAssertTrue(Readiness.canFinish(exitCode: 0, states: good, requiredSteps: Set(good.keys), confirmations: checks))
        XCTAssertFalse(Readiness.canFinish(exitCode: 1, states: good, requiredSteps: Set(good.keys), confirmations: checks))
        XCTAssertFalse(Readiness.canFinish(exitCode: 0, states: good, requiredSteps: Set(good.keys), confirmations: ["camera"]))
        XCTAssertFalse(Readiness.canFinish(exitCode: 0, states: good, requiredSteps: Set(good.keys).union(["zoom"]), confirmations: checks))
        for state in ["warning", "actionRequired", "failed", "running", "pending"] {
            var states = good; states["updates"] = state
            XCTAssertFalse(Readiness.canFinish(exitCode: 0, states: states, requiredSteps: Set(states.keys), confirmations: checks))
        }
    }
}
