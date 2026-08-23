import Foundation
import XCTest

@testable import PaddrMenu

final class OpenSourceNoticesTests: XCTestCase {
    func testPackagedNoticeIsPreferred() {
        let appURL = URL(fileURLWithPath: "/Applications/Paddr.app", isDirectory: true)
        let packagedNoticeURL = appURL
            .appendingPathComponent("Contents/Resources", isDirectory: true)
            .appendingPathComponent("ThirdPartyNotices.txt")
        var checkoutWasInspected = false

        let resolvedURL = PaddrOpenSourceNotices.url(
            bundledNoticeURL: packagedNoticeURL,
            mainBundleURL: appURL,
            currentDirectoryPath: repositoryRoot.path
        ) { _ in
            checkoutWasInspected = true
            return true
        }

        XCTAssertEqual(resolvedURL, packagedNoticeURL)
        XCTAssertFalse(checkoutWasInspected)
    }

    func testValidSourceCheckoutFallsBackToCanonicalNotice() {
        let expectedURL = repositoryRoot.appendingPathComponent("THIRD_PARTY_NOTICES.md")

        let resolvedURL = PaddrOpenSourceNotices.url(
            bundledNoticeURL: nil,
            mainBundleURL: developmentBundleURL,
            currentDirectoryPath: repositoryRoot.path,
            isRegularFile: isRegularFile(at:)
        )

        XCTAssertEqual(resolvedURL, expectedURL)
    }

    func testInvalidSourceCheckoutReturnsNil() {
        let invalidRoot = repositoryRoot.appendingPathComponent(
            "Tests/PaddrAppSupportTests",
            isDirectory: true
        )

        let resolvedURL = PaddrOpenSourceNotices.url(
            bundledNoticeURL: nil,
            mainBundleURL: developmentBundleURL,
            currentDirectoryPath: invalidRoot.path,
            isRegularFile: isRegularFile(at:)
        )

        XCTAssertNil(resolvedURL)
    }

    func testPackagedMissingNoticeReturnsNilWithoutSourceFallback() {
        let appURL = URL(fileURLWithPath: "/Applications/Paddr.app", isDirectory: true)
        var checkoutWasInspected = false

        let resolvedURL = PaddrOpenSourceNotices.url(
            bundledNoticeURL: nil,
            mainBundleURL: appURL,
            currentDirectoryPath: repositoryRoot.path
        ) { _ in
            checkoutWasInspected = true
            return true
        }

        XCTAssertNil(resolvedURL)
        XCTAssertFalse(checkoutWasInspected)
    }

    private var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .standardizedFileURL
    }

    private var developmentBundleURL: URL {
        repositoryRoot.appendingPathComponent(
            ".build/debug",
            isDirectory: true
        )
    }

    private func isRegularFile(at url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
