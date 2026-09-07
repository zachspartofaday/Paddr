import PaddrAppSupport
import SwiftUI
import PaddrCore

struct ProfileControlsView: View {
    @Bindable var model: PaddrMenuModel
    @State private var confirmationSelectionID: ConfigurationProfileID?
    @State private var showsDiscardConfirmation = false
    @State private var pendingProfileAction: PendingProfileAction?
    @State private var showsRestoreConfirmation = false
    @State private var nameDraft = ""

    var body: some View {
        let pickerPresentation = profilePickerPresentation

        HStack(spacing: PaddrStyle.Spacing.s2) {
            Text("Profile")
                .paddrTypography(.sectionLabel)
                .fixedSize(horizontal: true, vertical: false)

            Picker("Profile", selection: profileSelection) {
                ForEach(pickerPresentation.options) { option in
                    Text(verbatim: option.label).tag(option.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .paddrMenuSelector()
            .frame(width: PaddrStyle.Width.controlWide)
            .accessibilityLabel("Profile")
            .accessibilityValue(Text(verbatim: pickerPresentation.accessibilityValue))
            .help("Select the active profile")
            .paddrAccessibilityID("profile", "selector")

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

                Button(
                    "Restore Defaults",
                    systemImage: "arrow.counterclockwise",
                    action: requestRestoreDefaults
                )
                .disabled(!model.canEditActiveProfile)

                Button("Delete Profile", systemImage: "trash", role: .destructive) {
                    pendingProfileAction = .delete(
                        id: model.activeProfileID,
                        name: model.activeProfile.name
                    )
                }
                .disabled(!model.canEditActiveProfile || model.hasUnsavedChanges)
            } label: {
                if isDefaultProfile {
                    Label("Duplicate to Edit", systemImage: "plus.square.on.square")
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: true, vertical: false)
                } else {
                    Label("Profile Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.titleAndIcon)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .paddrMenuSelector()
            .accessibilityLabel(profileActionsAccessibilityLabel)
            .accessibilityValue(profileActionsAccessibilityValue)
            .help(profileActionsHelp)
            .paddrAccessibilityID("profile", "actions")
        }
        .disabled(!model.canManageProfiles)
        .alert("Restore defaults?", isPresented: $showsRestoreConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Defaults", role: .destructive) {
                model.restoreDefaults(discardChanges: true)
            }
        } message: {
            Text("This replaces your unsaved draft with defaults. Save & Apply is still required to update the profile.")
        }
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
        .alert(
            "Create Profile",
            isPresented: profileActionIsPresented(.create)
        ) {
            TextField("Profile name", text: $nameDraft)
            Button("Cancel", role: .cancel) { pendingProfileAction = nil }
            Button("Create") {
                guard pendingProfileAction?.kind == .create else { return }
                _ = model.createProfile(named: nameDraft)
                pendingProfileAction = nil
            }
        } message: {
            Text("Profile names must be nonempty and unique, ignoring case.")
        }
        .alert(
            "Rename Profile",
            isPresented: profileActionIsPresented(.rename)
        ) {
            TextField("Profile name", text: $nameDraft)
            Button("Cancel", role: .cancel) { pendingProfileAction = nil }
            Button("Rename") {
                guard pendingProfileAction?.kind == .rename,
                      let id = pendingProfileAction?.profileID else { return }
                _ = model.renameProfile(id: id, to: nameDraft)
                pendingProfileAction = nil
            }
        } message: {
            Text("Profile names must be nonempty and unique, ignoring case.")
        }
        .confirmationDialog(
            "Delete \(pendingProfileAction?.profileName ?? "")?",
            isPresented: profileActionIsPresented(.delete),
            titleVisibility: .visible
        ) {
            Button("Delete Profile", role: .destructive) {
                guard pendingProfileAction?.kind == .delete,
                      let id = pendingProfileAction?.profileID else { return }
                _ = model.deleteProfile(id: id, confirmed: true)
                pendingProfileAction = nil
            }
            Button("Cancel", role: .cancel) { pendingProfileAction = nil }
        } message: {
            Text("Deleting the active profile activates Default first. This cannot be undone.")
        }
    }

    private var isDefaultProfile: Bool { model.activeProfileID == .default }

    var profilePickerPresentation: ProfilePickerPresentation {
        ProfilePickerPresentation(
            profiles: model.profiles,
            activeProfileName: model.activeProfile.name,
            selection: model.profileSelectionPresentation
        )
    }

    private var profileActionsAccessibilityLabel: LocalizedStringResource {
        isDefaultProfile ? "Duplicate Default to Edit" : "Profile Actions"
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
            set: { id in requestProfileSelection(id: id) }
        )
    }

    private func profileActionIsPresented(_ kind: PendingProfileAction.Kind) -> Binding<Bool> {
        Binding(
            get: { pendingProfileAction?.kind == kind },
            set: { isPresented in
                if !isPresented, pendingProfileAction?.kind == kind {
                    pendingProfileAction = nil
                }
            }
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

    private func requestRestoreDefaults() {
        if model.hasUnsavedChanges {
            showsRestoreConfirmation = true
        } else {
            model.restoreDefaults()
        }
    }

    private func promptForCreate() {
        nameDraft = "New Profile"
        pendingProfileAction = .create(suggestedName: nameDraft)
    }

    private func duplicateActiveProfile() {
        _ = model.duplicateActiveProfile()
    }

    private func promptForRename() {
        nameDraft = model.activeProfile.name
        pendingProfileAction = .rename(
            id: model.activeProfileID,
            name: model.activeProfile.name
        )
    }
}

struct PendingProfileAction: Equatable {
    enum Kind: Equatable {
        case create
        case rename
        case delete
    }

    let kind: Kind
    let profileID: ConfigurationProfileID?
    let profileName: String

    static func create(suggestedName: String) -> Self {
        Self(kind: .create, profileID: nil, profileName: suggestedName)
    }

    static func rename(id: ConfigurationProfileID, name: String) -> Self {
        Self(kind: .rename, profileID: id, profileName: name)
    }

    static func delete(id: ConfigurationProfileID, name: String) -> Self {
        Self(kind: .delete, profileID: id, profileName: name)
    }
}

struct ProfilePickerPresentation: Equatable {
    struct Option: Identifiable, Equatable {
        let id: ConfigurationProfileID
        let label: String
    }

    let options: [Option]
    let accessibilityValue: String

    init(
        profiles: [ConfigurationProfile],
        activeProfileName: String,
        selection: ProfileSelectionPresentation
    ) {
        switch selection {
        case .active:
            options = profiles.map { Option(id: $0.id, label: $0.name) }
            accessibilityValue = activeProfileName

        case let .switching(to: pendingID, named: pendingName):
            let pendingLabel = String(
                localized: "Switching to \(pendingName)…",
                comment: "Profile selector value while the selected profile is being saved"
            )
            var presentedOptions = profiles.map { profile in
                Option(
                    id: profile.id,
                    label: profile.id == pendingID ? pendingLabel : profile.name
                )
            }
            if !presentedOptions.contains(where: { $0.id == pendingID }) {
                presentedOptions.append(Option(id: pendingID, label: pendingLabel))
            }
            options = presentedOptions
            accessibilityValue = String(
                localized: "Switching to \(pendingName)",
                comment: "Profile selector accessibility value while the selected profile is being saved"
            )
        }
    }
}
