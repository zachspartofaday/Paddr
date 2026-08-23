import SwiftUI

/// Changes layout without creating parallel copies of its stateful children.
/// `AnyLayout` keeps one mounted subtree while moving the same children between
/// horizontal and vertical arrangements.
struct PaddrAdaptiveSplitView<Leading: View, Trailing: View>: View {
    let breakpoint: CGFloat
    let leadingWidth: CGFloat
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @State private var availableWidth = PaddrStyle.Metrics.contentMaxWidth

    var body: some View {
        let usesColumns = availableWidth >= breakpoint
        let layout = usesColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: PaddrStyle.Spacing.s3))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: PaddrStyle.Spacing.s4))

        layout {
            leading()
                .frame(width: usesColumns ? leadingWidth : nil, alignment: .topLeading)
                .frame(
                    maxWidth: usesColumns ? nil : .infinity,
                    alignment: .topLeading
                )
            Divider()
            trailing()
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
            guard width > 0 else { return }
            availableWidth = width
        }
    }
}
