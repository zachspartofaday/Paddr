import AppKit
import SwiftUI
import PaddrCore

struct PadConfigurationView: View {
    @Environment(\.paddrFillsEqualHeightColumn) private var fillsEqualHeightColumn

    let side: PadSide
    @Binding var configuration: PadConfiguration

    init(
        side: PadSide,
        configuration: Binding<PadConfiguration>
    ) {
        self.side = side
        _configuration = configuration
    }

    private var title: LocalizedStringResource { side == .left ? "Left trackpad" : "Right trackpad" }
    private var tracksPointerInsideTapRadius: Binding<Bool> {
        Binding(
            get: { configuration.centerTapTrackingMode == .decoupled },
            set: {
                configuration.centerTapTrackingMode = $0 ? .decoupled : .coupled
            }
        )
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
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            Text(title)
                .paddrTypography(.cardTitle)
                .foregroundStyle(PaddrStyle.textPrimary)

            HStack(spacing: PaddrStyle.Spacing.s2) {
                Text("Behavior")
                    .paddrTypography(.sectionLabel)
                    .foregroundStyle(PaddrStyle.textSecondary)
                Spacer()
                PadModePicker(
                    selection: $configuration.mode,
                    accessibilityIdentifier: PaddrAccessibility.identifier(
                        "pad-mode",
                        side.rawValue
                    )
                )
                    .frame(width: PaddrStyle.behaviorPickerWidth)
            }
            .frame(maxWidth: .infinity, minHeight: PaddrStyle.Metrics.row)

            PaddrSectionContainer {
                modeSettings
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(
            maxHeight: fillsEqualHeightColumn ? .infinity : nil,
            alignment: .topLeading
        )
        .paddrCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var modeSettings: some View {
        switch configuration.mode {
        case .disabled:
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                Text("This trackpad will not emit pointer, scroll, or button input.")
                    .paddrTypography(.rowLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .mouse:
            previewSplit(previewTitle: LocalizedStringResource("Tap area")) {
                PaddrSettingsGroup {
                    sensitivityRow
                    ValueSliderRow(
                        title: "Pointer acceleration",
                        systemImage: "arrow.up.right.and.arrow.down.left",
                        value: $configuration.mouseAcceleration,
                        range: ConfigurationLimits.mouseAcceleration,
                        step: 0.01,
                        valueText: configuration.mouseAcceleration.formatted(
                            .percent.precision(.fractionLength(0))
                        )
                    )
                    .help("Zero is linear. Higher values increase fast-motion gain.")
                    ValueSliderRow(
                        title: "Center tap radius",
                        systemImage: "scope",
                        value: $configuration.mouseDeadzone,
                        range: ConfigurationLimits.mouseDeadzone,
                        step: 0.01,
                        valueText: configuration.mouseDeadzone.formatted(.percent.precision(.fractionLength(0)))
                    )
                    .help("The radius starts at the pad center. Leaving it cancels the tap. At 0%, taps use the maximum-movement limit.")
                    PaddrSettingsRow(
                        title: "Track pointer inside tap radius",
                        systemImage: "cursorarrow.motionlines",
                        labelWidth: nil
                    ) {
                        Toggle(
                            "Track pointer inside tap radius",
                            isOn: tracksPointerInsideTapRadius
                        )
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityLabel("Track pointer inside tap radius")
                        .accessibilityValue(
                            configuration.centerTapTrackingMode == .decoupled
                                ? LocalizedStringResource("On")
                                : LocalizedStringResource("Off")
                        )
                        .help("When on, pointer movement continues inside and across the center tap radius. When off, the radius also acts as a pointer dead zone.")
                        .paddrAccessibilityID("pad", side.rawValue, "pointer-tracking")
                    }
                    TapActionPicker(selection: $configuration.tapKey)
                }
            }

        case .scroll:
            previewSplit(previewTitle: LocalizedStringResource("Preview")) {
                PaddrSettingsGroup {
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
        PaddrAdaptiveSplitView(
            breakpoint: PaddrStyle.previewInspectorColumnsBreakpoint,
            leadingWidth: PaddrStyle.Metrics.zoneMapWidth,
            showsDivider: false,
            leading: { previewSection(title: previewTitle) },
            trailing: { settingsSection(settings) }
        )
    }

    private func settingsSection<Settings: View>(
        @ViewBuilder _ settings: () -> Settings
    ) -> some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            PaddrSectionHeader(settingsTitle)
            settings()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    private func previewSection(title: LocalizedStringResource) -> some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            PaddrSectionHeader(title)
            PadModePreview(mode: configuration.mode, deadzone: configuration.mouseDeadzone)
                .frame(
                    width: PaddrStyle.Metrics.zoneMapWidth,
                    height: PaddrStyle.Metrics.zoneMapHeight
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .help("Mirrors how the trackpad will respond in this mode.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    let accessibilityIdentifier: String

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
        control.setAccessibilityIdentifier(accessibilityIdentifier)
        control.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
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
