import PaddrAppSupport
import SwiftUI
import TrackIsBackCore

struct ProfileBarView: View {
    @Bindable var model: PaddrMenuModel
    @State private var pendingSelectionID: ConfigurationProfileID?
    @State private var showsDiscardConfirmation = false
    @State private var namePrompt: NamePrompt?
    @State private var nameDraft = ""
    @State private var pendingDeleteID: ConfigurationProfileID?

    var body: some View {
        HStack(spacing: 8) {
            Picker("Profile", selection: profileSelection) {
                ForEach(model.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: 260)
            .accessibilityValue(model.activeProfile.name)

            Button("New Profile", systemImage: "plus", action: promptForCreate)
                .labelStyle(.iconOnly)
                .help("Create profile")
                .disabled(model.hasUnsavedChanges)

            Button("Duplicate Profile", systemImage: "plus.square.on.square") {
                _ = model.duplicateActiveProfile()
            }
            .labelStyle(.iconOnly)
            .help("Duplicate profile")
            .disabled(model.hasUnsavedChanges)

            Button("Rename Profile", systemImage: "pencil", action: promptForRename)
                .labelStyle(.iconOnly)
                .help("Rename profile")
                .disabled(!model.canEditActiveProfile)

            Button("Delete Profile", systemImage: "trash", role: .destructive) {
                pendingDeleteID = model.activeProfileID
            }
            .labelStyle(.iconOnly)
            .help("Delete profile")
            .disabled(!model.canEditActiveProfile || model.hasUnsavedChanges)

            if !model.canEditActiveProfile {
                Text("Duplicate Default to customize it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .alert("Discard unsaved changes?", isPresented: $showsDiscardConfirmation) {
            Button("Cancel", role: .cancel) {
                if let id = pendingSelectionID {
                    _ = model.resolveProfileSelection(id: id, discardChanges: false)
                }
                pendingSelectionID = nil
            }
            Button("Discard Changes", role: .destructive) {
                if let id = pendingSelectionID {
                    _ = model.resolveProfileSelection(id: id, discardChanges: true)
                }
                pendingSelectionID = nil
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

    private var profileSelection: Binding<ConfigurationProfileID> {
        Binding(
            get: { model.activeProfileID },
            set: { id in
                switch model.requestProfileSelection(id: id, source: .configurationWindow) {
                case .confirmationRequired:
                    pendingSelectionID = id
                    showsDiscardConfirmation = true
                case .accepted, .blockedByUnsavedChanges, .cancelled, .operationInProgress,
                     .profileNotFound, .storageUnavailable, .unchanged:
                    break
                }
            }
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

    private func promptForCreate() {
        nameDraft = "New Profile"
        namePrompt = .create
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
