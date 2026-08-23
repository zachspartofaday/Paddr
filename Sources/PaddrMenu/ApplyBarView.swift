import PaddrAppSupport
import SwiftUI

enum PaddrStatusKind: String, CaseIterable, Identifiable {
    case access
    case puck
    case controller
    case output
    case battery

    var id: Self { self }
}

struct ApplyBarView: View {
    @Bindable var model: PaddrMenuModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    private var outputValue: LocalizedStringResource {
        switch model.readiness.output {
        case .active: "Active"
        case .releasing: "Releasing"
        case .waiting: "Waiting"
        case .idle: "Idle"
        }
    }

    private var outputSystemImage: String {
        switch model.readiness.output {
        case .active: "wave.3.right.circle.fill"
        case .releasing: "arrow.down.circle"
        case .waiting: "hourglass.circle"
        case .idle: "pause.circle"
        }
    }

    private var batteryPresentation: BatteryStatusPresentation {
        BatteryStatusPresentation(status: model.batteryStatus)
    }

    private var batteryState: StatusBadgeState {
        switch batteryPresentation.levelBand {
        case .unavailable: .neutral
        case .critical: .critical
        case .low: .problem
        case .healthy: .ready
        }
    }

    var outputToggleAccessibilityLabel: LocalizedStringResource { "Trackpad output" }

    var outputToggleAccessibilityValue: LocalizedStringResource {
        model.isEnabled ? "On" : "Off"
    }

    var outputToggleHelp: LocalizedStringResource {
        model.readiness.outputDisabledReason?.message
            ?? LocalizedStringResource("Enable or disable mapped trackpad output")
    }

    var outputToggleAccessibilityIdentifier: String {
        PaddrAccessibility.identifier("toolbar", "output")
    }

    var body: some View {
        let usesInlineLayout = availableWidth >= PaddrStyle.Metrics.statusBarInlineBreakpoint
            && !dynamicTypeSize.isAccessibilitySize
        let minimumContentWidth = PaddrStyle.Metrics.minimumWindowSize.width
            - (2 * PaddrStyle.Metrics.outerSpacing)
        let contentLayout = usesInlineLayout
            ? AnyLayout(HStackLayout(alignment: .center, spacing: PaddrStyle.Spacing.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s2))
        let cellsLayout = usesInlineLayout
            ? AnyLayout(HStackLayout(alignment: .center, spacing: PaddrStyle.Spacing.s2))
            : AnyLayout(
                PaddrWrappingHStack(
                    horizontalSpacing: PaddrStyle.Spacing.s2,
                    verticalSpacing: PaddrStyle.Spacing.s2
                )
            )

        contentLayout {
            cellsLayout {
                statusCells
            }
            .fixedSize(horizontal: usesInlineLayout, vertical: false)
            .frame(
                minWidth: usesInlineLayout ? nil : 0,
                idealWidth: usesInlineLayout ? nil : minimumContentWidth,
                maxWidth: usesInlineLayout ? nil : .infinity,
                alignment: .leading
            )

            statusGuidanceAndOutputControl
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PaddrStyle.Metrics.outerSpacing)
        .padding(.vertical, PaddrStyle.Spacing.s2)
        .frame(minHeight: PaddrStyle.Metrics.commandBar)
        .background(PaddrStyle.night0.opacity(0.96))
        .overlay(alignment: .top) {
            PaddrAppearanceReader { appearance in
                Rectangle()
                    .fill(appearance.surfaceStroke)
                    .frame(height: appearance.strokeWidth)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0 else { return }
            availableWidth = width
        }
        .onChange(of: model.status) { _, status in
            guard status.messageState != nil else { return }
            AccessibilityNotification.Announcement(String(localized: status.message)).post()
        }
    }

    private var statusGuidanceAndOutputControl: some View {
        HStack(alignment: .center, spacing: PaddrStyle.Spacing.s3) {
            statusMessage
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: .infinity,
                    minHeight: PaddrStyle.Metrics.row,
                    alignment: .leading
                )

            Toggle("Trackpad output", isOn: $model.isEnabled)
                .labelsHidden()
                .disabled(!model.canToggleOutput)
                .toggleStyle(.switch)
                .accessibilityLabel(Text(outputToggleAccessibilityLabel))
                .accessibilityValue(Text(outputToggleAccessibilityValue))
                .help(Text(outputToggleHelp))
                .accessibilityIdentifier(outputToggleAccessibilityIdentifier)
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var statusMessage: some View {
        if let messageState = model.status.messageState {
            Label {
                Text(model.status.message)
                    .lineLimit(1)
                    .truncationMode(.tail)
            } icon: {
                Image(
                    systemName: messageState == .failure
                        ? "exclamationmark.triangle.fill"
                        : "info.circle.fill"
                )
                .accessibilityHidden(true)
            }
            .paddrTypography(.rowLabel)
            .foregroundStyle(
                messageState == .failure ? PaddrStyle.errorText : PaddrStyle.warningText
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.status.message)
            .help(Text(model.status.message))
        } else {
            Label(
                model.readiness.nextAction.title,
                systemImage: model.readiness.nextAction.systemImage
            )
            .paddrTypography(.rowLabel)
            .foregroundStyle(
                model.readiness.nextAction == .none
                    ? PaddrStyle.activeText
                    : PaddrStyle.textSecondary
            )
            .help(Text(model.readiness.nextAction.title))
            .paddrAccessibilityID("status", "next-action")
        }
    }

    @ViewBuilder private var statusCells: some View {
        ForEach(PaddrStatusKind.allCases) { statusCell(for: $0) }
    }

    @ViewBuilder private func statusCell(for kind: PaddrStatusKind) -> some View {
        switch kind {
        case .access:
            let isReady = model.readiness.access == .ready
            StatusCell(
                title: LocalizedStringResource("Access"),
                value: isReady
                    ? LocalizedStringResource("Ready")
                    : LocalizedStringResource("Needed"),
                systemImage: isReady
                    ? "checkmark.shield.fill"
                    : "exclamationmark.shield",
                state: isReady ? .ready : .problem,
                isCompact: isReady,
                identifier: "access"
            )
        case .puck:
            let isReady = model.readiness.puck == .connected
            StatusCell(
                title: LocalizedStringResource("Puck"),
                value: isReady
                    ? LocalizedStringResource("Connected")
                    : LocalizedStringResource("Not found"),
                systemImage: isReady
                    ? "cable.connector"
                    : "cable.connector.slash",
                state: isReady ? .ready : .problem,
                isCompact: isReady,
                identifier: "puck"
            )
        case .controller:
            let isReady = model.readiness.controller == .connected
            StatusCell(
                title: LocalizedStringResource("Controller"),
                value: isReady
                    ? LocalizedStringResource("Connected")
                    : LocalizedStringResource("Not found"),
                systemImage: isReady ? "gamecontroller.fill" : "gamecontroller",
                state: isReady ? .ready : .problem,
                isCompact: isReady,
                identifier: "controller"
            )
        case .output:
            let isReady = model.readiness.output == .active
            StatusCell(
                title: LocalizedStringResource("Output"),
                value: outputValue,
                systemImage: outputSystemImage,
                state: isReady ? .active : .neutral,
                isCompact: isReady,
                identifier: "output"
            )
        case .battery:
            StatusCell(
                title: LocalizedStringResource("Battery"),
                value: batteryPresentation.compactValue,
                systemImage: batteryPresentation.systemImage,
                state: batteryState,
                accessibilityValue: batteryPresentation.accessibilityValue,
                identifier: "battery"
            )
        }
    }

}
