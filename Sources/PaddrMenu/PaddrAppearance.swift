import SwiftUI

/// The single resolution of the adaptive environment `PaddrMenu` reacts to.
///
/// Views read it through ``PaddrAppearanceReader`` instead of each declaring its own
/// `@Environment` pairs, so one place decides what Reduce Transparency, increased
/// contrast, Differentiate Without Colour, and Reduce Motion mean for the interface.
struct PaddrAppearance: Equatable {
    /// Materials are replaced by an opaque, still-tinted fill.
    let usesOpaqueFallback: Bool
    /// Separators and borders are drawn at full strength.
    let hasIncreasedContrast: Bool
    /// State must be distinguished by shape, not by colour alone.
    let usesShapeDifferentiation: Bool
    /// Animation is suppressed.
    let reducesMotion: Bool

    init(
        reduceTransparency: Bool = false,
        colorSchemeContrast: ColorSchemeContrast = .standard,
        differentiateWithoutColor: Bool = false,
        reduceMotion: Bool = false
    ) {
        usesOpaqueFallback = reduceTransparency
        hasIncreasedContrast = colorSchemeContrast == .increased
        usesShapeDifferentiation = differentiateWithoutColor
        reducesMotion = reduceMotion
    }

    init(environment: EnvironmentValues) {
        self.init(
            reduceTransparency: environment.accessibilityReduceTransparency,
            colorSchemeContrast: environment.colorSchemeContrast,
            differentiateWithoutColor: environment.accessibilityDifferentiateWithoutColor,
            reduceMotion: environment.accessibilityReduceMotion
        )
    }

    /// Border and separator thickness.
    var strokeWidth: CGFloat { hasIncreasedContrast ? 1.5 : 1 }

    /// Family-console surfaces become visibly more opaque in Increased Contrast.
    /// These values match the pinned reference instead of multiplying an already
    /// translucent color by an opacity of one.
    func surface(elevated: Bool) -> Color {
        if hasIncreasedContrast {
            return Color.white.opacity(elevated ? 0.14 : 0.09)
        }
        return elevated ? PaddrStyle.elevatedSurface : PaddrStyle.surface
    }

    /// Family-console strokes strengthen from 10% to 28% white in Increased Contrast.
    var surfaceStroke: Color {
        hasIncreasedContrast ? Color.white.opacity(0.28) : PaddrStyle.surfaceStroke
    }

    /// A surface's separator opacity: its own standard value, or full strength when the
    /// viewer asked for increased contrast.
    func strokeOpacity(_ standard: Double) -> Double {
        hasIncreasedContrast ? 1 : standard
    }

    /// The animation to use, or `nil` when the viewer asked for reduced motion.
    func animation(_ animation: Animation?) -> Animation? {
        reducesMotion ? nil : animation
    }
}

/// Reads the adaptive environment once and hands the resolved ``PaddrAppearance`` to
/// its content.
struct PaddrAppearanceReader<Content: View>: View {
    @ViewBuilder let content: (PaddrAppearance) -> Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content(
            PaddrAppearance(
                reduceTransparency: reduceTransparency,
                colorSchemeContrast: colorSchemeContrast,
                differentiateWithoutColor: differentiateWithoutColor,
                reduceMotion: reduceMotion
            )
        )
    }
}
