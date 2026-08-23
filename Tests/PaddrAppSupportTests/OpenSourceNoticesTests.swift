import Foundation
import XCTest

@testable import PaddrMenu

final class OpenSourceNoticesTests: XCTestCase {
    func testPackagedAndSwiftPackageLookupPathsResolveTheNotice() throws {
        let emptyBundle = Bundle(for: Self.self)
        let packageBundle = PaddrOpenSourceNotices.packageBundle
        XCTAssertNil(PaddrOpenSourceNotices.resourceURL(in: emptyBundle))

        var packagedFallbackWasRequested = false
        let packagedURL = try XCTUnwrap(
            PaddrOpenSourceNotices.url(
                mainBundle: packageBundle
            ) {
                packagedFallbackWasRequested = true
                return emptyBundle
            }
        )
        var developmentFallbackWasRequested = false
        let developmentURL = try XCTUnwrap(
            PaddrOpenSourceNotices.url(
                mainBundle: emptyBundle
            ) {
                developmentFallbackWasRequested = true
                return packageBundle
            }
        )

        XCTAssertFalse(packagedFallbackWasRequested)
        XCTAssertTrue(developmentFallbackWasRequested)
        XCTAssertEqual(packagedURL, developmentURL)
    }

    func testSwiftPackageNoticeMatchesCanonicalReleaseNoticeExactly() throws {
        let packageURL = try XCTUnwrap(
            PaddrOpenSourceNotices.resourceURL(in: PaddrOpenSourceNotices.packageBundle)
        )
        let repositoryURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "THIRD_PARTY_NOTICES.md")

        XCTAssertEqual(
            try Data(contentsOf: packageURL),
            try Data(contentsOf: repositoryURL),
            "Keep the SwiftPM development resource synchronized with the canonical release notice"
        )
    }
}
