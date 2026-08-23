import Foundation

enum PaddrOpenSourceNotices {
    private static let resourceName = "ThirdPartyNotices"
    private static let resourceExtension = "txt"
    private static let packageManifestName = "Package.swift"
    private static let canonicalNoticeName = "THIRD_PARTY_NOTICES.md"

    /// Packaged apps install the notice directly in `Bundle.main`. Supported source-checkout
    /// launches may resolve the canonical notice from their working directory instead.
    static var url: URL? {
        let mainBundle = Bundle.main
        return url(
            bundledNoticeURL: resourceURL(in: mainBundle),
            mainBundleURL: mainBundle.bundleURL,
            currentDirectoryPath: FileManager.default.currentDirectoryPath,
            isRegularFile: { url in
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }
        )
    }

    static func url(
        bundledNoticeURL: URL?,
        mainBundleURL: URL,
        currentDirectoryPath: String,
        isRegularFile: (URL) -> Bool
    ) -> URL? {
        if let bundledNoticeURL {
            return bundledNoticeURL
        }

        guard mainBundleURL.pathExtension.lowercased() != "app" else {
            return nil
        }

        let checkoutRoot = URL(
            fileURLWithPath: currentDirectoryPath,
            isDirectory: true
        ).standardizedFileURL
        let packageManifestURL = checkoutRoot.appendingPathComponent(packageManifestName)
        let canonicalNoticeURL = checkoutRoot.appendingPathComponent(canonicalNoticeName)

        guard
            isRegularFile(packageManifestURL),
            isRegularFile(canonicalNoticeURL)
        else {
            return nil
        }

        return canonicalNoticeURL
    }

    static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }
}
