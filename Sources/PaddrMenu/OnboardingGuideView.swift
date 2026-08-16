import PaddrAppSupport
import SwiftUI

struct OnboardingGuideView: View {
    @Bindable var model: PaddrMenuModel
    let onSkip: @MainActor () -> Void
    let onComplete: @MainActor () -> Void

    @State private var pager: OnboardingPager

    init(
        model: PaddrMenuModel,
        onSkip: @escaping @MainActor () -> Void,
        onComplete: @escaping @MainActor () -> Void,
        initialPager: OnboardingPager = OnboardingPager()
    ) {
        self.model = model
        self.onSkip = onSkip
        self.onComplete = onComplete
        _pager = State(initialValue: initialPager)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { page.frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            footer
        }
        .frame(
            minWidth: PaddrStyle.Metrics.minimumGuideWindowSize.width,
            idealWidth: PaddrStyle.Metrics.guideWindowSize.width,
            minHeight: PaddrStyle.Metrics.minimumGuideWindowSize.height,
            idealHeight: PaddrStyle.Metrics.guideWindowSize.height
        )
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Paddr Guide")
                .paddrTypography(.pageTitle)
            Spacer()
            Text("Step \(pager.pageNumber) of \(OnboardingPager.pageCount)")
                .paddrTypography(.rowLabel)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PaddrStyle.Spacing.s5)
        .padding(.vertical, PaddrStyle.Spacing.s4)
        .accessibilityElement(children: .combine)
    }

    private var page: some View {
        VStack(spacing: PaddrStyle.Spacing.s5) {
            switch pager.pageIndex {
            case 0:
                guidePage(
                    symbol: "hand.point.up.left.fill",
                    title: LocalizedStringResource("Welcome to Paddr"),
                    detail: LocalizedStringResource(
                        "Use Steam Controller trackpads without Steam Input. Paddr maps trackpad gestures to normal macOS mouse, scrolling, and keyboard input; it does not inject into games."
                    )
                )
            case 1:
                guidePage(
                    symbol: "person.crop.rectangle.stack",
                    title: LocalizedStringResource("Profiles and Duplicate Default"),
                    detail: LocalizedStringResource(
                        "Default is a safe, read-only reference. Duplicate Default to create an editable profile, then set each pad to Pointer, Scroll, Off, or Zones."
                    )
                )
            case 2:
                guidePage(
                    symbol: "accessibility",
                    title: LocalizedStringResource("Allow Access"),
                    detail: LocalizedStringResource(
                        "Input Monitoring lets Paddr receive controller reports from the puck, and Accessibility lets it send your mapped mouse and keyboard input. Paddr asks for Input Monitoring at first launch; otherwise it only requests permission or opens Settings when you choose an action below."
                    )
                ) {
                    permissionControls
                }
            default:
                guidePage(
                    symbol: "play.circle.fill",
                    title: LocalizedStringResource("Start Output Safely"),
                    detail: LocalizedStringResource(
                        "The Paddr menu shows receiver and controller status with the Trackpad Output toggle. When output starts, release both trackpads to return to neutral before mapped input activates."
                    )
                )
            }

            pageIndicator
        }
        .padding(PaddrStyle.Spacing.s5)
    }

    private func guidePage(
        symbol: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource
    ) -> some View {
        guidePage(symbol: symbol, title: title, detail: detail) { EmptyView() }
    }

    private func guidePage<Actions: View>(
        symbol: String,
        title: LocalizedStringResource,
        detail: LocalizedStringResource,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack(alignment: .top, spacing: PaddrStyle.Spacing.s5) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(PaddrStyle.accentText)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
                Text(title)
                    .paddrTypography(.cardTitle)
                Text(detail)
                    .paddrTypography(.rowLabel)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PaddrStyle.Spacing.s3)
        .paddrCard()
        .accessibilityElement(children: .contain)
    }

    private var permissionControls: some View {
        VStack(alignment: .leading, spacing: PaddrStyle.Spacing.s3) {
            HStack(spacing: PaddrStyle.Spacing.s2) {
                Label(
                    model.inputMonitoringGranted ? "Input Monitoring ready" : "Input Monitoring needed",
                    systemImage: model.inputMonitoringGranted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(model.inputMonitoringGranted ? PaddrStyle.activeText : PaddrStyle.warningText)
                .accessibilityLabel(
                    model.inputMonitoringGranted
                        ? Text("Input Monitoring access is ready")
                        : Text("Input Monitoring access is needed")
                )

                Button("Request", action: model.requestInputMonitoring)
                    .paddrActionButton(.primary)
                Button("Open Settings", action: model.openInputMonitoringSettings)
                    .paddrActionButton(.secondary)
            }

            HStack(spacing: PaddrStyle.Spacing.s2) {
                Label(
                    model.accessibilityTrusted ? "Accessibility ready" : "Accessibility needed",
                    systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(model.accessibilityTrusted ? PaddrStyle.activeText : PaddrStyle.warningText)
                .accessibilityLabel(
                    model.accessibilityTrusted
                        ? Text("Accessibility access is ready")
                        : Text("Accessibility access is needed")
                )

                Button("Request", action: model.requestAccessibility)
                    .paddrActionButton(.primary)
                Button("Open Settings", action: model.openAccessibilitySettings)
                    .paddrActionButton(.secondary)
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: PaddrStyle.Spacing.s2) {
            ForEach(0..<OnboardingPager.pageCount, id: \.self) { index in
                Circle()
                    .fill(index == pager.pageIndex ? PaddrStyle.accentText : Color.secondary.opacity(0.28))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Guide progress")
        .accessibilityValue("Step \(pager.pageNumber) of \(OnboardingPager.pageCount)")
    }

    private var currentPageTitle: String {
        switch pager.pageIndex {
        case 0: String(localized: "Welcome to Paddr")
        case 1: String(localized: "Profiles and Duplicate Default")
        case 2: String(localized: "Allow Access")
        default: String(localized: "Start Output Safely")
        }
    }

    private func goBack() {
        pager.goBack()
        announcePageChange()
    }

    private func goNext() {
        pager.advance()
        announcePageChange()
    }

    private func announcePageChange() {
        AccessibilityNotification.Announcement(
            String(
                localized: "Step \(pager.pageNumber) of \(OnboardingPager.pageCount): \(currentPageTitle)"
            )
        ).post()
    }

    private var footer: some View {
        HStack(spacing: PaddrStyle.Spacing.s2) {
            Button("Skip", action: onSkip)
                .keyboardShortcut(.cancelAction)
                .paddrActionButton(.secondary)

            Spacer()

            if pager.canGoBack {
                Button("Back", action: goBack)
                    .paddrActionButton(.secondary)
            }

            if pager.isLastPage {
                Button("Get Started", action: onComplete)
                    .keyboardShortcut(.defaultAction)
                    .paddrActionButton(.primary)
            } else {
                Button("Next", action: goNext)
                    .keyboardShortcut(.defaultAction)
                    .paddrActionButton(.primary)
            }
        }
        .padding(.horizontal, PaddrStyle.Spacing.s5)
        .padding(.vertical, PaddrStyle.Spacing.s4)
    }
}
