import AppKit
import SwiftUI
import TrackIsBackCore

struct PadConfigurationView: View {
    let side: PadSide
    @Binding var configuration: PadConfiguration
    @State private var isExpanded = true

    private var title: LocalizedStringResource { side == .left ? "Left trackpad" : "Right trackpad" }
    private var summary: LocalizedStringResource {
        switch configuration.mode {
        case .disabled: "Off"
        case .mouse: "Pointer"
        case .scroll: "Scroll"
        case .dpad: configuration.zoneLayout.displayName
        }
    }

    private var settingsTitle: LocalizedStringResource {
        switch configuration.mode {
        case .disabled: "Trackpad off"
        case .mouse: "Pointer settings"
        case .scroll: "Scroll settings"
        case .dpad: "Zone settings"
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: PaddrStyle.settingsRowSpacing) {
                HStack(spacing: 12) {
                    PadModePicker(selection: $configuration.mode)
                        .frame(width: PaddrStyle.behaviorPickerWidth)

                    Spacer(minLength: 8)
                }
                .frame(maxWidth: .infinity, minHeight: PaddrStyle.behaviorRowHeight)
                .padding(.horizontal, PaddrStyle.insetHorizontalPadding)

                PaddrSectionContainer {
                    modeSettings
                }
            }
            .padding(.top, PaddrStyle.settingsRowSpacing)
        } label: {
            HStack(spacing: 10) {
                Text(title).paddrTypography(.padTitle)
                Spacer()
                Text(summary)
                    .paddrTypography(.caption)
                    .foregroundStyle(
                        configuration.mode == .disabled ? Color.secondary : PaddrStyle.accentText
                    )
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        configuration.mode == .disabled
                            ? Color.secondary.opacity(0.08)
                            : PaddrStyle.accent.opacity(0.10),
                        in: .capsule
                    )
            }
            .frame(minHeight: PaddrStyle.cardHeaderHeight)
            .contentShape(.rect)
        }
        .padding(PaddrStyle.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .paddrCard()
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var modeSettings: some View {
        switch configuration.mode {
        case .disabled:
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                Text("This trackpad will not emit pointer, scroll, or button input.")
                    .paddrTypography(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .mouse:
            previewSplit(previewTitle: LocalizedStringResource("Tap area")) {
                VStack(spacing: PaddrStyle.settingsRowSpacing) {
                    sensitivityRow
                    ValueSliderRow(
                        title: "Center tap radius",
                        systemImage: "scope",
                        value: $configuration.mouseDeadzone,
                        range: ConfigurationLimits.mouseDeadzone,
                        step: 0.01,
                        valueText: configuration.mouseDeadzone.formatted(.percent.precision(.fractionLength(0)))
                    )
                    .help("The radius starts at the pad center. Movement pauses inside it, and leaving it cancels the tap.")
                    TapActionPicker(selection: $configuration.tapKey)
                }
            }

        case .scroll:
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                VStack(spacing: PaddrStyle.settingsRowSpacing) {
                    sensitivityRow
                    TapActionPicker(selection: $configuration.tapKey)
                }
            }

        case .dpad:
            ButtonZoneConfigurationView(configuration: $configuration)
        }
    }

    /// Mirrors the Zones map-plus-inspector split so every mode keeps the pad
    /// itself as the card's anchor.
    private func previewSplit(
        previewTitle: LocalizedStringResource,
        @ViewBuilder settings: @escaping () -> some View
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                previewSection(title: previewTitle)
                    .frame(width: PaddrStyle.zoneMapWidth)
                PaddrInsetDivider(axis: .vertical)
                    .padding(.horizontal, 8)
                settingsSection(settings)
                    .frame(width: PaddrStyle.zoneInspectorWidth, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: PaddrStyle.zoneSubdivisionSpacing) {
                previewSection(title: previewTitle)
                settingsSection(settings)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSection<Settings: View>(
        @ViewBuilder _ settings: () -> Settings
    ) -> some View {
        VStack(alignment: .leading, spacing: PaddrStyle.insetHeaderContentSpacing) {
            Text(settingsTitle)
                .paddrTypography(.callout)
                .bold()
                .frame(minHeight: PaddrStyle.insetHeaderHeight)
                .accessibilityAddTraits(.isHeader)
            settings()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func previewSection(title: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaddrStyle.settingsRowSpacing) {
            Text(title)
                .paddrTypography(.callout)
                .bold()
                .frame(minHeight: PaddrStyle.insetHeaderHeight)
            PadModePreview(mode: configuration.mode, deadzone: configuration.mouseDeadzone)
                .frame(maxWidth: PaddrStyle.zoneMapWidth * 1.4)
                .frame(
                    minHeight: PaddrStyle.zoneMapHeight,
                    maxHeight: PaddrStyle.zoneMapHeight
                )
                .help("Mirrors how the trackpad will respond in this mode.")
        }
    }

    private var sensitivityRow: some View {
        let isScrollMode = configuration.mode == .scroll
        let value = isScrollMode ? configuration.scrollSensitivity : configuration.sensitivity
        return ValueSliderRow(
            title: "Sensitivity",
            systemImage: "speedometer",
            value: isScrollMode ? $configuration.scrollSensitivity : $configuration.sensitivity,
            range: isScrollMode ? ConfigurationLimits.scrollSensitivity : ConfigurationLimits.sensitivity,
            step: 0.1,
            valueText: value.formatted(.number.precision(.fractionLength(1))) + "×"
        )
    }
}

private struct PadModePicker: NSViewRepresentable {
    @Binding var selection: PadMode

    private static let modes: [PadMode] = [.disabled, .mouse, .scroll, .dpad]
    private static let labels = [
        String(localized: LocalizedStringResource("Off")),
        String(localized: LocalizedStringResource("Pointer")),
        String(localized: LocalizedStringResource("Scroll")),
        String(localized: LocalizedStringResource("Zones"))
    ]

    @MainActor
    final class Coordinator: NSObject {
        var selection: Binding<PadMode>

        init(selection: Binding<PadMode>) {
            self.selection = selection
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            guard Self.validSegment(sender.selectedSegment) else { return }
            selection.wrappedValue = PadModePicker.modes[sender.selectedSegment]
        }

        private static func validSegment(_ segment: Int) -> Bool {
            PadModePicker.modes.indices.contains(segment)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: Self.labels,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setAccessibilityLabel(String(localized: LocalizedStringResource("Behavior")))
        update(control, coordinator: context.coordinator)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        update(control, coordinator: context.coordinator)
    }

    private func update(_ control: NSSegmentedControl, coordinator: Coordinator) {
        coordinator.selection = $selection
        control.selectedSegment = Self.modes.firstIndex(where: { $0.rawValue == selection.rawValue }) ?? 0
        let segmentWidth = PaddrStyle.behaviorPickerWidth / CGFloat(Self.modes.count)
        for segment in Self.modes.indices {
            control.setWidth(segmentWidth, forSegment: segment)
        }
    }
}
