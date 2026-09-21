import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif

private final class FailingProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.serverCertificateUntrusted)) }
    override func stopLoading() {}
}

final class DownloadTests: XCTestCase {
    func testTransportFailureDoesNotPromoteAFile() async throws {
        let catalog = try PackageCatalog.load(URL(fileURLWithPath: "AppResources/package-catalog.json"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingProtocol.self]
        do {
            try await PackageDownload(spec: catalog.packages[0], destination: output, configuration: config, progress: { _ in }).run()
            XCTAssertTrue(false, "A TLS failure must fail the download")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .serverCertificateUntrusted)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testAlreadyCancelledDownloadDoesNotCreateAFile() async throws {
        let catalog = try PackageCatalog.load(URL(fileURLWithPath: "AppResources/package-catalog.json"))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailingProtocol.self]
        let operation = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await PackageDownload(spec: catalog.packages[0], destination: output, configuration: config, progress: { _ in }).run()
        }
        do { try await operation.value; XCTAssertTrue(false) }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
}
