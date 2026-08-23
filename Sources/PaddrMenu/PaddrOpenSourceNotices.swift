import Foundation

enum PaddrOpenSourceNotices {
    private static let resourceName = "ThirdPartyNotices"
    private static let resourceExtension = "txt"

    /// Packaged apps install the notice directly in `Bundle.main`; SwiftPM development
    /// launches resolve the package resource bundle instead.
    static var url: URL? {
        url(mainBundle: .main) { .module }
    }

    static var packageBundle: Bundle {
        .module
    }

    static func url(mainBundle: Bundle, packageBundle: () -> Bundle) -> URL? {
        if let packagedURL = resourceURL(in: mainBundle) {
            return packagedURL
        }
        return resourceURL(in: packageBundle())
    }

    static func resourceURL(in bundle: Bundle) -> URL? {
        bundle.url(forResource: resourceName, withExtension: resourceExtension)
    }
}
