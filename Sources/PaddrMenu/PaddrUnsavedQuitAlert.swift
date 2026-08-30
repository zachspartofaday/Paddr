import AppKit

enum PaddrUnsavedQuitAction: Equatable {
    case saveAndQuit
    case cancel
    case quitWithoutSaving
}

@MainActor
enum PaddrUnsavedQuitAlert {
    static func make(profileName: String) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Save changes before quitting?")
        alert.informativeText = String(
            localized: "Changes to “\(profileName)” will be lost if you quit without saving.",
            comment: "Unsaved-quit warning; the argument is the active profile name."
        )
        alert.addButton(withTitle: String(localized: "Save & Quit"))
        let cancelButton = alert.addButton(withTitle: String(localized: "Cancel"))
        cancelButton.keyEquivalent = "\u{1b}"
        let discardButton = alert.addButton(withTitle: String(localized: "Quit Without Saving"))
        discardButton.hasDestructiveAction = true
        return alert
    }

    static func action(for response: NSApplication.ModalResponse) -> PaddrUnsavedQuitAction {
        switch response {
        case .alertFirstButtonReturn: .saveAndQuit
        case .alertThirdButtonReturn: .quitWithoutSaving
        default: .cancel
        }
    }
}
