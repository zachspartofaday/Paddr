import PaddrAppSupport
import SwiftUI
import TrackIsBackCore

struct ProfileControlsView: View {
    @Bindable var model: PaddrMenuModel
    @State private var confirmationSelectionID: ConfigurationProfileID?
    @State private var showsDiscardConfirmation = false
    @State private var namePrompt: NamePrompt?
    @State private var nameDraft = ""
    @State private var pendingDeleteID: ConfigurationProfileID?

    var body: some View {
        HStack(spacing: 8) {
            Text("Profile")
                .paddrTypography(.headline)
                .fixedSize(horizontal: true, vertical: false)

            Picker("Profile", selection: profileSelection) {
                ForEach(model.profiles) { profile in
                    profileLabel(for: profile).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .paddrMenuSelector()
            .frame(width: 220)
            .accessibilityLabel("Profile")
            .accessibilityValue(profileSelectionAccessibilityValue)
            .help("Select the active profile")

            Menu {
                if isDefaultProfile {
                    Button(
                        "Duplicate Default to Edit",
                        systemImage: "plus.square.on.square",
                        action: duplicateActiveProfile
                    )
                    .disabled(model.hasUnsavedChanges)

                    Button("New Profile", systemImage: "plus", action: promptForCreate)
                        .disabled(model.hasUnsavedChanges)
                } else {
                    Button("New Profile", systemImage: "plus", action: promptForCreate)
                        .disabled(model.hasUnsavedChanges)

                    Button(
                        "Duplicate Profile",
                        systemImage: "plus.square.on.square",
                        action: duplicateActiveProfile
                    )
                    .disabled(model.hasUnsavedChanges)
                }

                Divider()

                Button("Rename Profile", systemImage: "pencil", action: promptForRename)
                    .disabled(!model.canEditActiveProfile)

                Button("Delete Profile", systemImage: "trash", role: .destructive) {
                    pendingDeleteID = model.activeProfileID
                }
                .disabled(!model.canEditActiveProfile || model.hasUnsavedChanges)
            } label: {
                if isDefaultProfile {
                    Label("Duplicate to Edit", systemImage: "plus.square.on.square")
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Label("Profile actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .paddrMenuSelector()
            .accessibilityLabel(profileActionsAccessibilityLabel)
            .accessibilityValue(profileActionsAccessibilityValue)
            .help(profileActionsHelp)
        }
        .disabled(!model.canManageProfiles)
        .alert("Discard unsaved changes?", isPresented: $showsDiscardConfirmation) {
            Button("Cancel", role: .cancel) {
                if let id = confirmationSelectionID {
                    _ = model.resolveProfileSelection(id: id, discardChanges: false)
                }
                confirmationSelectionID = nil
            }
            Button("Discard Changes", role: .destructive) {
                if let id = confirmationSelectionID {
                    _ = model.resolveProfileSelection(id: id, discardChanges: true)
                }
                confirmationSelectionID = nil
            }
        } message: {
            Text("Switching profiles replaces the current draft. Unsaved changes will not be copied.")
        }
        .alert(namePrompt?.title ?? "Profile Name", isPresented: namePromptIsPresented) {
            TextField("Profile name", text: $nameDraft)
            Button("Cancel", role: .cancel) { namePrompt = nil }
            Button(namePrompt?.actionTitle ?? "Save") {
                switch namePrompt {
                case .create:
                    _ = model.createProfile(named: nameDraft)
                case .rename:
                    _ = model.renameActiveProfile(to: nameDraft)
                case nil:
                    break
                }
                namePrompt = nil
            }
        } message: {
            Text("Profile names must be nonempty and unique, ignoring case.")
        }
        .confirmationDialog(
            "Delete \(model.activeProfile.name)?",
            isPresented: deleteConfirmationIsPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                if let id = pendingDeleteID {
                    _ = model.deleteProfile(id: id, confirmed: true)
                }
                pendingDeleteID = nil
            }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("Deleting the active profile activates Default first. This cannot be undone.")
        }
    }

    private var isDefaultProfile: Bool { model.activeProfileID == .default }

    @ViewBuilder
    private func profileLabel(for profile: ConfigurationProfile) -> some View {
        if case let .switching(to: pendingID) = model.profileSelectionPresentation,
           pendingID == profile.id {
            Text(
                "Switching to \(profile.name)…",
                comment: "Profile selector value while the selected profile is being saved"
            )
        } else {
            Text(verbatim: profile.name)
        }
    }

    private var profileSelectionAccessibilityValue: Text {
        switch model.profileSelectionPresentation {
        case .active:
            Text(verbatim: model.activeProfile.name)
        case let .switching(to: id):
            Text(
                "Switching to \(profileName(for: id))",
                comment: "Profile selector accessibility value while the selected profile is being saved"
            )
        }
    }

    private func profileName(for id: ConfigurationProfileID) -> String {
        model.profiles.first { $0.id == id }?.name ?? model.activeProfile.name
    }

    private var profileActionsAccessibilityLabel: LocalizedStringResource {
        isDefaultProfile ? "Duplicate Default to Edit" : "Profile actions"
    }

    private var profileActionsAccessibilityValue: LocalizedStringResource {
        isDefaultProfile ? "Default is read-only" : "Editable profile"
    }

    private var profileActionsHelp: LocalizedStringResource {
        isDefaultProfile
            ? "Duplicate Default to create an editable profile"
            : "Create, duplicate, rename, or delete profiles"
    }

    private var profileSelection: Binding<ConfigurationProfileID> {
        Binding(
            get: { model.profileSelectionPresentation.selectedProfileID },
            set: requestProfileSelection
        )
    }

    private var namePromptIsPresented: Binding<Bool> {
        Binding(
            get: { namePrompt != nil },
            set: { if !$0 { namePrompt = nil } }
        )
    }

    private var deleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteID != nil },
            set: { if !$0 { pendingDeleteID = nil } }
        )
    }

    private func requestProfileSelection(id: ConfigurationProfileID) {
        switch model.requestProfileSelection(id: id, source: .configurationWindow) {
        case .confirmationRequired:
            confirmationSelectionID = id
            showsDiscardConfirmation = true
        case .accepted, .blockedByUnsavedChanges, .cancelled, .operationInProgress,
             .profileNotFound, .storageUnavailable, .unchanged:
            break
        }
    }

    private func promptForCreate() {
        nameDraft = "New Profile"
        namePrompt = .create
    }

    private func duplicateActiveProfile() {
        _ = model.duplicateActiveProfile()
    }

    private func promptForRename() {
        nameDraft = model.activeProfile.name
        namePrompt = .rename
    }
}

private enum NamePrompt {
    case create
    case rename

    var title: LocalizedStringResource {
        switch self {
        case .create: "Create Profile"
        case .rename: "Rename Profile"
        }
    }

    var actionTitle: LocalizedStringResource {
        switch self {
        case .create: "Create"
        case .rename: "Rename"
        }
    }
}
