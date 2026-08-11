import AppKit
import TrackIsBackCore

@main
@MainActor
struct TrackIsBackMenuMain {
    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            let configuration = (try? ConfigurationStore.load()) ?? .default
            print("PuckPadsMenu smoke test")
            print("left=\(configuration.left.mode.rawValue), right=\(configuration.right.mode.rawValue)")
            print("device=\(TritonHIDDevice.probe()?.description ?? "not found")")
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
