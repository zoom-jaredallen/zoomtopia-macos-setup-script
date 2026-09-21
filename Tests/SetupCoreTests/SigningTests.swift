import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif
final class SigningTests: XCTestCase {
    func testRunningIdentityRejectsAnotherExecutable() throws {
        let requirement = try SigningIdentity.runningRequirement()
        let current = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
        let result = try Command.run("/usr/bin/codesign", ["--verify", "--strict", "-R", "=" + requirement, current])
        if result.0 != 0 { throw SetupFailure("Self requirement failed: \(requirement); path \(current); \(result.1)") }
        XCTAssertEqual(result.0, 0)
        XCTAssertTrue(try Command.run("/usr/bin/codesign", ["--verify", "--strict", "-R", "=" + requirement, "/usr/bin/true"]).0 != 0)
    }
}
