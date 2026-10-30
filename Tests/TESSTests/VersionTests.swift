import XCTest
@testable import TESS

final class VersionTests: XCTestCase {
    private func v(_ s: String) -> AppVersion { AppVersion(s)! }

    func testParsing() {
        XCTAssertEqual(v("v0.9.2-beta").description, "0.9.2-beta")
        XCTAssertEqual(v("0.9.2 beta").description, "0.9.2-beta")
        XCTAssertEqual(v("1.2").description, "1.2.0")
        XCTAssertEqual(v("1.0.0-rc.1").displayName, "1.0.0 rc 1")
        XCTAssertNil(AppVersion("abc"))
        XCTAssertNil(AppVersion("1.x.0"))
        XCTAssertNil(AppVersion(""))
    }

    func testOrdering() {
        let ordered = ["0.9.0-beta", "0.9.1-beta", "0.9.1", "0.10.0", "1.0.0-beta", "1.0.0-beta.2",
                       "1.0.0-beta.10", "1.0.0-rc.1", "1.0.0", "1.0.1", "2.0.0"]
        for (lower, higher) in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(v(lower), v(higher), "\(lower) should be older than \(higher)")
            XCTAssertFalse(v(higher) < v(lower), "\(higher) should not be older than \(lower)")
        }
    }

    func testEquality() {
        XCTAssertEqual(v("0.9.2-beta"), v("v0.9.2 beta"))
        XCTAssertFalse(v("0.9.2-beta") < v("0.9.2-beta"))
        XCTAssertNotEqual(v("0.9.2"), v("0.9.2-beta"))
    }

    func testPrerelease() {
        XCTAssertTrue(v("0.9.2-beta").isPrerelease)
        XCTAssertFalse(v("1.0.0").isPrerelease)
    }
}
