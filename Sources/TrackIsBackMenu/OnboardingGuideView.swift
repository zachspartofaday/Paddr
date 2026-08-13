import PaddrAppSupport
import SwiftUI

struct OnboardingGuideView: View {
    @Bindable var model: PaddrMenuModel
    let onSkip: @MainActor () -> Void
    let onComplete: @MainActor () -> Void

    @State private var pager = OnboardingPager()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { page.frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            footer
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 430, idealHeight: 470)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Paddr Guide")
                .paddrTypography(.title)
            Spacer()
            Text("Step \(pager.pageNumber) of \(OnboardingPager.pageCount)")
                .paddrTypography(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }

    private var page: some View {
        VStack(spacing: 24) {
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
                    title: LocalizedStringResource("Allow Accessibility"),
                    detail: LocalizedStringResource(
                        "Accessibility permission lets Paddr send your mapped mouse and keyboard input. Paddr only requests permission or opens Settings when you choose an action below."
                    )
                ) {
                    accessibilityControls
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
        .padding(28)
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
        HStack(alignment: .top, spacing: 24) {
            Image(systemName: symbol)
                .font(.system(size: 48, weight: .medium))
                .foregroundStyle(PaddrStyle.accentText)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .paddrTypography(.padTitle)
                Text(detail)
                    .paddrTypography(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(PaddrStyle.cardPadding)
        .paddrCard()
        .accessibilityElement(children: .contain)
    }

    private var accessibilityControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                model.accessibilityTrusted ? "Access ready" : "Access needed",
                systemImage: model.accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .foregroundStyle(model.accessibilityTrusted ? PaddrStyle.activeText : PaddrStyle.warningText)
            .accessibilityLabel(
                model.accessibilityTrusted
                    ? Text("Accessibility access is ready")
                    : Text("Accessibility access is needed")
            )

            HStack(spacing: 8) {
                Button("Request", action: model.requestAccessibility)
                    .paddrActionButton(prominent: true)
                Button("Open Settings", action: model.openAccessibilitySettings)
                    .paddrActionButton()
            }
        }
    }

    private var pageIndicator: some View {
        HStack(spacing: 8) {
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
        case 2: String(localized: "Allow Accessibility")
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
        HStack(spacing: 10) {
            Button("Skip", action: onSkip)
                .keyboardShortcut(.cancelAction)
                .paddrActionButton()

            Spacer()

            if pager.canGoBack {
                Button("Back", action: goBack)
                    .paddrActionButton()
            }

            if pager.isLastPage {
                Button("Get Started", action: onComplete)
                    .keyboardShortcut(.defaultAction)
                    .paddrActionButton(prominent: true)
            } else {
                Button("Next", action: goNext)
                    .keyboardShortcut(.defaultAction)
                    .paddrActionButton(prominent: true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}
