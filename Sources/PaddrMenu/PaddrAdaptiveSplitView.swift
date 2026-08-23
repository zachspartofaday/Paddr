import SwiftUI

extension EnvironmentValues {
    /// Coarsened at the adaptive breakpoint so a card can fill the finite
    /// tallest-column proposal without reacting to every resize point.
    @Entry var paddrFillsEqualHeightColumn = false
}

/// Changes layout without creating parallel copies of its stateful children.
/// `AnyLayout` keeps one mounted subtree while moving the same children between
/// horizontal and vertical arrangements.
struct PaddrAdaptiveSplitView<Leading: View, Trailing: View>: View {
    let breakpoint: CGFloat
    let leadingWidth: CGFloat?
    let showsDivider: Bool
    let equalizesColumnHeights: Bool
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var availableWidth = PaddrStyle.Metrics.contentMaxWidth

    init(
        breakpoint: CGFloat,
        leadingWidth: CGFloat,
        showsDivider: Bool = true,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.breakpoint = breakpoint
        self.leadingWidth = leadingWidth
        self.showsDivider = showsDivider
        equalizesColumnHeights = false
        self.leading = leading
        self.trailing = trailing
    }

    /// Creates a dividerless, equal-width split whose columns share the
    /// tallest intrinsic height. Keeping this as a separate initializer makes
    /// unsupported fixed-leading or divider combinations unrepresentable.
    init(
        equalHeightColumnsBreakpoint breakpoint: CGFloat,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.breakpoint = breakpoint
        leadingWidth = nil
        showsDivider = false
        equalizesColumnHeights = true
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        let usesColumns = availableWidth >= breakpoint
        let usesEqualHeightColumns = usesColumns && equalizesColumnHeights
        let layout = usesEqualHeightColumns
            ? AnyLayout(PaddrEqualHeightColumnsLayout(spacing: PaddrStyle.Spacing.s3))
            : usesColumns
                ? AnyLayout(HStackLayout(alignment: .top, spacing: PaddrStyle.Spacing.s3))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s4))

        layout {
            leading()
                .frame(width: usesColumns ? leadingWidth : nil, alignment: .topLeading)
                .frame(
                    minWidth: usesColumns && leadingWidth != nil ? nil : 0,
                    maxWidth: usesColumns && leadingWidth != nil ? nil : .infinity,
                    alignment: .topLeading
                )
                .frame(
                    maxHeight: usesEqualHeightColumns ? .infinity : nil,
                    alignment: .topLeading
                )
                .environment(\.paddrFillsEqualHeightColumn, usesEqualHeightColumns)
            if showsDivider {
                Divider()
            }
            trailing()
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
                .frame(
                    maxHeight: usesEqualHeightColumns ? .infinity : nil,
                    alignment: .topLeading
                )
                .environment(\.paddrFillsEqualHeightColumn, usesEqualHeightColumns)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0 else { return }
            availableWidth = width
        }
    }
}
