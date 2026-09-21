import Foundation
#if !STANDALONE_TESTS
import XCTest
@testable import SetupCore
#endif

final class LatestPackageTests: XCTestCase {
    func testSignedMetadataSelectsEachAppAndRejectsAmbiguity() throws {
        let catalog = try PackageCatalog.load(URL(fileURLWithPath: "AppResources/package-catalog.json"))
        for spec in catalog.packages {
            let latest = spec.id == "chrome" ? "154.0.1.2" : "7.3.0.99999"
            func xml(_ contents: String) -> Data { Data("<installer-gui-script>\(contents)</installer-gui-script>".utf8) }
            let app = "<bundle id='\(spec.bundleID)' \(spec.versionKey)='\(latest)'/>"
            XCTAssertEqual(try LatestPackage.version(distribution: xml("<bundle id='unrelated' CFBundleVersion='1'/>" + app), spec: spec), latest)
            XCTAssertEqual(try LatestPackage.version(distribution: xml(app + app), spec: spec), latest)
            XCTAssertThrowsError(try LatestPackage.version(distribution: xml("<bundle id='other' CFBundleVersion='99'/>"), spec: spec))
            XCTAssertThrowsError(try LatestPackage.version(distribution: xml(app + "<bundle id='\(spec.bundleID)' \(spec.versionKey)='999'/ >"), spec: spec))
            for invalid in ["1.0", "unknown", "7.2 (88195)"] {
                XCTAssertThrowsError(try LatestPackage.version(distribution: xml("<bundle id='\(spec.bundleID)' \(spec.versionKey)='\(invalid)'/>"), spec: spec))
            }
            XCTAssertThrowsError(try LatestPackage.version(distribution: xml(app + "<bundle id='\(spec.bundleID)' \(spec.versionKey)='999'/>"), spec: spec))
        }
    }
}
