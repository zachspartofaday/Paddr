import Darwin
import Foundation
import TrackIsBackCore

private struct CLIOptions {
    var configuration = TrackIsBackConfiguration.default
    var configurationURL: URL?
    var profileStoreURL: URL?
    var profileDocument: ConfigurationProfileDocument?
    var writeConfigurationURL: URL?
    var listProfiles = false
    var selectProfile: String?
    var durationSeconds: TimeInterval?
    var dryRun = false
    var observeOnly = false
    var verbose = false
    var showConfiguration = false
    var showHelp = false
}

private func help() -> String {
    """
    Paddr — Steam Controller 2 trackpads for native macOS games

    Usage:
      scripts/paddr.sh [options]
      swift run PaddrCLI -- [options]

    Pad modes:
      disabled | mouse | scroll | dpad

    Main options:
      --profile-store PATH          Use a canonical profile document at PATH instead of the default.
      --list-profiles               List profile names and stable IDs, then exit.
      --select-profile ID|NAME      Persistently select a profile by stable ID or exact name, then exit.
      --config PATH                 Safely load a legacy raw configuration or canonical profile document.
                                    This compatibility input cannot be combined with profile operations.
      --write-config PATH           Write the effective configuration as a canonical profile document.
      --show-config                 Print the effective active configuration and exit.
      --left-mode MODE              Set the left pad mode.
      --right-mode MODE             Set the right pad mode.
      --left-sensitivity N          Left pointer sensitivity, 0.1...20.
      --right-sensitivity N         Right pointer sensitivity, 0.1...20.
      --left-mouse-acceleration N   Left pointer acceleration, 0...1.
      --right-mouse-acceleration N  Right pointer acceleration, 0...1.
      --left-scroll-sensitivity N   Left scroll sensitivity, 0...1.
      --right-scroll-sensitivity N  Right scroll sensitivity, 0...1.
      --left-tap ACTION|none        Tap a key, mouse-left, or mouse-right; likewise --right-tap.
      --left-mouse-deadzone N       Center tap radius from 0...1; likewise --right-mouse-deadzone.
      --left-up ACTION              Left D-pad up-zone action; likewise --left-right/--left-down/--left-left.
      --right-up ACTION             Right D-pad up-zone action; likewise --right-right/--right-down/--right-left.
      --left-deadzone N             Left D-pad center deadzone from 0..<1.
      --right-deadzone N            Right D-pad center deadzone from 0..<1.
      --left-layout LAYOUT          radial-four, four-corners, horizontal-two, vertical-two, or grid-nine.
      --right-layout LAYOUT         Set the right button-zone layout.
      --left-grid-POSITION ACTION   Set a 3×3 action: top-left, top, top-right, left, center,
                                    right, bottom-left, bottom, or bottom-right. Right side also supported.
      --tap-max-ms N                Tap duration for both pads, 1...5000 ms.
      --tap-max-movement N          Tap movement for both pads, 0...100000 raw units.
      --duration SECONDS            Stop after a finite duration; otherwise run until Control-C.
      --observe-only                Parse/log actions without posting mouse, scroll, or key events.
      --verbose                     Print resolved actions.
      --dry-run                     Show permissions, device, and configuration without opening HID.
      -h, --help                    Show this help.

    Keys:
      Letters, digits, up/down/left/right, space, return, tab, escape, delete, shift,
      control, option, command, or a raw macOS virtual key code written as code:N.
      Any button zone can instead use mouse-left or mouse-right.

    Examples:
      scripts/paddr.sh
      scripts/paddr.sh --left-mode dpad --left-up w --left-right d --left-down s --left-left a
      scripts/paddr.sh --left-mode dpad --left-up mouse-left --left-down mouse-right
      scripts/paddr.sh --right-mode mouse --right-sensitivity 1.5 --right-tap space

    Safety:
      Puck/dongle mode only. Paddr opens IOHID without seizing it and has no feature-report API;
      it never changes lizard mode, IMU, haptics, rumble, firmware, or Apple's native gamepad mapping.
    """
}

private func value(after option: String, in args: [String]) throws -> String? {
    guard let index = args.firstIndex(of: option) else { return nil }
    guard index + 1 < args.count else { throw TrackIsBackError.configuration("\(option) requires a value.") }
    return args[index + 1]
}

private func url(_ path: String) -> URL {
    URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
}

private func parse(_ rawArguments: [String]) throws -> CLIOptions {
    var args = rawArguments
    if args.first == "--" { args.removeFirst() }
    if args.contains("-h") || args.contains("--help") {
        var options = CLIOptions()
        options.showHelp = true
        return options
    }
    for option in ["--config", "--profile-store"] where args.filter({ $0 == option }).count > 1 {
        throw TrackIsBackError.configuration("\(option) may only be specified once.")
    }
    let explicitConfigurationURL = try value(after: "--config", in: args).map(url)
    let profileStoreURL = try value(after: "--profile-store", in: args).map(url)
    let selectProfile = try value(after: "--select-profile", in: args)
    let listsProfiles = args.contains("--list-profiles")
    guard !(listsProfiles && selectProfile != nil) else {
        throw TrackIsBackError.configuration(
            "--list-profiles and --select-profile are mutually exclusive."
        )
    }
    let isProfileOperation = listsProfiles || selectProfile != nil
    if isProfileOperation {
        guard explicitConfigurationURL == nil else {
            throw TrackIsBackError.configuration(
                "--config cannot be combined with profile operations; use --profile-store for canonical storage."
            )
        }
        var operationIndex = 0
        while operationIndex < args.count {
            switch args[operationIndex] {
            case "--list-profiles":
                operationIndex += 1
            case "--profile-store", "--select-profile":
                guard operationIndex + 1 < args.count else {
                    throw TrackIsBackError.configuration(
                        "\(args[operationIndex]) requires a value."
                    )
                }
                operationIndex += 2
            default:
                throw TrackIsBackError.configuration(
                    "Profile list/select operations cannot be combined with runtime or mapping options."
                )
            }
        }
    }

    let configuration: TrackIsBackConfiguration
    let profileDocument: ConfigurationProfileDocument?
    if let explicitConfigurationURL {
        configuration = try ConfigurationStore.load(from: explicitConfigurationURL)
        profileDocument = nil
    } else {
        let loaded = try ConfigurationProfileStore.load(from: profileStoreURL)
        profileDocument = loaded.document
        configuration = loaded.document.activeProfile?.configuration ?? .default
        if let diagnostic = loaded.diagnostic {
            fputs("Warning: \(diagnostic)\n", stderr)
        }
    }
    var options = CLIOptions(configuration: configuration)
    options.configurationURL = explicitConfigurationURL
    options.profileStoreURL = profileStoreURL
    options.profileDocument = profileDocument
    options.listProfiles = listsProfiles
    options.selectProfile = selectProfile

    func parseDouble(_ raw: String, option: String) throws -> Double {
        guard let value = Double(raw), value.isFinite else {
            throw TrackIsBackError.configuration("\(option) requires a finite number.")
        }
        return value
    }

    func setPad(_ side: PadSide, _ update: (inout PadConfiguration) -> Void) {
        if side == .left { update(&options.configuration.left) }
        else { update(&options.configuration.right) }
    }

    var index = 0
    while index < args.count {
        let argument = args[index]
        func nextValue() throws -> String {
            index += 1
            guard index < args.count else { throw TrackIsBackError.configuration("\(argument) requires a value.") }
            return args[index]
        }

        switch argument {
        case "-h", "--help": options.showHelp = true
        case "--dry-run": options.dryRun = true
        case "--observe-only": options.observeOnly = true
        case "--verbose": options.verbose = true
        case "--show-config": options.showConfiguration = true
        case "--list-profiles": options.listProfiles = true
        case "--select-profile": options.selectProfile = try nextValue()
        case "--profile-store": options.profileStoreURL = url(try nextValue())
        case "--config": _ = try nextValue()
        case "--write-config": options.writeConfigurationURL = url(try nextValue())
        case "--duration":
            let duration = try parseDouble(nextValue(), option: argument)
            guard duration > 0 else { throw TrackIsBackError.configuration("--duration must be positive.") }
            options.durationSeconds = duration
        case "--tap-max-ms":
            let value = try parseDouble(nextValue(), option: argument)
            options.configuration.left.tapMaximumMilliseconds = value
            options.configuration.right.tapMaximumMilliseconds = value
        case "--tap-max-movement":
            let value = try parseDouble(nextValue(), option: argument)
            options.configuration.left.tapMaximumMovement = value
            options.configuration.right.tapMaximumMovement = value
        case "--left-mode", "--right-mode":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            guard let mode = PadMode(rawValue: try nextValue()) else {
                throw TrackIsBackError.configuration("\(argument) requires disabled, mouse, scroll, or dpad.")
            }
            setPad(side) { $0.mode = mode }
        case "--left-sensitivity", "--right-sensitivity":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let value = try parseDouble(nextValue(), option: argument)
            setPad(side) { $0.sensitivity = value }
        case "--left-mouse-acceleration", "--right-mouse-acceleration":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let value = try parseDouble(nextValue(), option: argument)
            setPad(side) { $0.mouseAcceleration = value }
        case "--left-scroll-sensitivity", "--right-scroll-sensitivity":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let value = try parseDouble(nextValue(), option: argument)
            guard ConfigurationLimits.scrollSensitivity.contains(value) else {
                throw TrackIsBackError.configuration("\(argument) must be between 0 and 1.")
            }
            setPad(side) { $0.scrollSensitivity = value }
        case "--left-mouse-deadzone", "--right-mouse-deadzone":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let value = try parseDouble(nextValue(), option: argument)
            setPad(side) { $0.mouseDeadzone = value }
        case "--left-deadzone", "--right-deadzone":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let value = try parseDouble(nextValue(), option: argument)
            setPad(side) { $0.dpadDeadzone = value }
        case "--left-layout", "--right-layout":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            guard let layout = PadZoneLayout(rawValue: try nextValue()) else {
                throw TrackIsBackError.configuration(
                    "\(argument) requires radial-four, four-corners, horizontal-two, vertical-two, or grid-nine."
                )
            }
            setPad(side) { $0.zoneLayout = layout }
        case "--left-tap", "--right-tap":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let key = try nextValue()
            setPad(side) { $0.tapKey = key.lowercased() == "none" ? nil : key }
        case "--left-up", "--left-right", "--left-down", "--left-left",
             "--right-up", "--right-right", "--right-down", "--right-left":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let direction = argument.split(separator: "-").last.map(String.init) ?? ""
            let key = try nextValue()
            setPad(side) { pad in
                switch direction {
                case "up": pad.dpadKeys.up = key
                case "right": pad.dpadKeys.right = key
                case "down": pad.dpadKeys.down = key
                default: pad.dpadKeys.left = key
                }
            }
        case "--left-grid-top-left", "--left-grid-top", "--left-grid-top-right",
             "--left-grid-left", "--left-grid-center", "--left-grid-right",
             "--left-grid-bottom-left", "--left-grid-bottom", "--left-grid-bottom-right",
             "--right-grid-top-left", "--right-grid-top", "--right-grid-top-right",
             "--right-grid-left", "--right-grid-center", "--right-grid-right",
             "--right-grid-bottom-left", "--right-grid-bottom", "--right-grid-bottom-right":
            let side: PadSide = argument.hasPrefix("--left") ? .left : .right
            let prefix = side == .left ? "--left-grid-" : "--right-grid-"
            let position = String(argument.dropFirst(prefix.count))
            let key = try nextValue()
            setPad(side) { pad in
                switch position {
                case "top-left": pad.gridKeys.topLeft = key
                case "top": pad.gridKeys.top = key
                case "top-right": pad.gridKeys.topRight = key
                case "left": pad.gridKeys.left = key
                case "center": pad.gridKeys.center = key
                case "right": pad.gridKeys.right = key
                case "bottom-left": pad.gridKeys.bottomLeft = key
                case "bottom": pad.gridKeys.bottom = key
                default: pad.gridKeys.bottomRight = key
                }
            }
        default:
            throw TrackIsBackError.configuration("Unknown option: \(argument)")
        }
        index += 1
    }

    options.configuration = try options.configuration.validated()
    return options
}

private func printConfiguration(_ configuration: TrackIsBackConfiguration) throws {
    FileHandle.standardOutput.write(try ConfigurationStore.encoded(configuration))
}

private func printProfiles(_ document: ConfigurationProfileDocument) {
    for profile in document.profiles {
        let marker = profile.id == document.activeProfileID ? "*" : " "
        print("\(marker)\t\(profile.name)\t\(profile.id.rawValue)")
    }
}

private func canonicalDocument(
    for configuration: TrackIsBackConfiguration,
    preserving source: ConfigurationProfileDocument?
) throws -> ConfigurationProfileDocument {
    var document = source ?? .default
    if document.activeProfileID == .default, configuration != .default {
        var candidate = "CLI configuration"
        var suffix = 2
        while document.profile(matching: candidate) != nil {
            candidate = "CLI configuration \(suffix)"
            suffix += 1
        }
        let profile = try document.createProfile(named: candidate, configuration: configuration)
        document.activeProfileID = profile.id
    } else {
        try document.replaceConfiguration(for: document.activeProfileID, with: configuration)
    }
    return document
}

private func run(_ options: CLIOptions) throws {
    print("Accessibility: \(Permissions.accessibilityTrusted(prompt: false) ? "granted" : "needed for live output")")
    guard let deviceSummary = TritonHIDDevice.probe() else {
        throw TrackIsBackError.device("No Steam Controller 2 puck interface was found.")
    }
    print("Selected device: \(deviceSummary.description)")
    print("Left pad: \(options.configuration.left.mode.rawValue), pointer sensitivity \(options.configuration.left.sensitivity), pointer acceleration \(options.configuration.left.mouseAcceleration), scroll sensitivity \(options.configuration.left.scrollSensitivity), tap \(options.configuration.left.tapKey ?? "none")")
    print("Right pad: \(options.configuration.right.mode.rawValue), pointer sensitivity \(options.configuration.right.sensitivity), pointer acceleration \(options.configuration.right.mouseAcceleration), scroll sensitivity \(options.configuration.right.scrollSensitivity), tap \(options.configuration.right.tapKey ?? "none")")
    print("Controller feature reports: unavailable by design")

    if options.dryRun {
        print("Dry run complete: HID was not opened and no CGEvents were posted.")
        return
    }
    if !options.observeOnly, !Permissions.accessibilityTrusted(prompt: true) {
        throw TrackIsBackError.permission("Accessibility is required for mouse, scroll, and keyboard output. Grant it, then rerun.")
    }

    let stop = TrackpadStopToken()
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interruptSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let terminationSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    interruptSource.setEventHandler { stop.requestStop() }
    terminationSource.setEventHandler { stop.requestStop() }
    interruptSource.resume()
    terminationSource.resume()
    defer {
        interruptSource.cancel()
        terminationSource.cancel()
    }

    let deadline = options.durationSeconds.map { Date().addingTimeInterval($0) }
    print(options.observeOnly ? "Observing until stopped." : "Output enabled; press Control-C to stop.")
    let verbose = options.verbose
    let result = try TrackpadRuntime.run(
        configuration: options.configuration,
        observeOnly: options.observeOnly,
        stopToken: stop,
        deadline: deadline,
        onAction: { action in
            if verbose { print("- \(action)") }
        }
    )
    let summary = result.summary
    print("Summary: reports=\(summary.reportCount), actions=\(summary.actionCount), featureReports=0")
}

do {
    let options = try parse(Array(CommandLine.arguments.dropFirst()))
    if options.showHelp {
        print(help())
        exit(0)
    }
    if options.listProfiles {
        guard let document = options.profileDocument else {
            throw TrackIsBackError.configuration("Profile storage is unavailable.")
        }
        printProfiles(document)
        exit(0)
    }
    if let selector = options.selectProfile {
        guard var document = options.profileDocument else {
            throw TrackIsBackError.configuration("Profile storage is unavailable.")
        }
        guard let profile = document.profile(matching: selector) else {
            throw TrackIsBackError.configuration(
                "No profile matches \(selector). Use --list-profiles to see names and stable IDs."
            )
        }
        try document.activateProfile(id: profile.id)
        try ConfigurationProfileStore.save(document, to: options.profileStoreURL)
        print("Selected profile: \(profile.name) (\(profile.id.rawValue))")
        exit(0)
    }
    if let destination = options.writeConfigurationURL {
        let document = try canonicalDocument(
            for: options.configuration,
            preserving: options.profileDocument
        )
        try ConfigurationProfileStore.save(document, to: destination)
        print("Wrote profile document: \(destination.path)")
        exit(0)
    }
    if options.showConfiguration {
        try printConfiguration(options.configuration)
        exit(0)
    }
    try run(options)
} catch {
    fputs("Error: \(error)\n\n\(help())\n", stderr)
    exit(2)
}
