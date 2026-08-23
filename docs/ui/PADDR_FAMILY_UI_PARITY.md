# Paddr Family UI Parity Manifest

Updated: 2026-08-23  
Status: Implemented for the Paddr 0.11 development line  
Paddr issues: #76, #77, #78  
Authority: BottleRocket `docs/marketing/PADDR_FAMILY_UI_AUTHORITY.md`, issue #267,
PR #268, merged as `38839ca6dbf86a1ffb29108129378f46cbd1e119`  
Pinned reference: `6c65d74fac9add281918438629228333535752a4`

## Boundary

Paddr resolves each reference declaration with
`git show 6c65d74fac9add281918438629228333535752a4:<path>`. It owns every adaptation
locally and has no source, package, runtime, build, or release dependency on
BottleRocket.

The grant covers presentation code only. Paddr's profile schema, configuration schema,
controller I/O, parser, output, session, and persistence contracts are unchanged.

## Licensed declaration disposition

Every declaration named by the authority is enumerated below. **Adapted** records a
Paddr-local presentation derivation. **Not adapted** means the declaration is permitted by
the grant but is not used and Paddr makes no provenance claim for it. **Authority-excluded**
means the authority expressly withholds it from the MIT grant.

### `SCMapprConsoleTheme.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `ConsoleLayout` | **Adapted:** `PaddrStyle.Metrics.defaultContentWidth` and `outerSpacing`; restored and user-resized windows remain fluid beyond that default. |
| `ConsolePalette` | **Adapted:** canonical values in `PaddrStyle`, with product-specific token names replaced by neutral names and separate accessible semantic derivatives. |
| `consoleBackground` and `ConsoleBackgroundModifier` | **Adapted:** `PanelBackgroundView`. |
| `consoleSurface` and `ConsoleSurfaceModifier` | **Adapted:** `paddrCard()`, `PaddrCardModifier`, and `PaddrAppearance`. |
| `ConsolePrimaryButton` | **Adapted:** `paddrActionButton(.primary)`. Paddr retains native bordered-prominent semantics with an accessible derived tint. |
| `ConsoleSecondaryButton` | **Adapted:** `paddrActionButton(.secondary)`. |
| `ConsoleTone` | **Adapted:** `StatusBadgeState` semantic mappings. |
| `WineBootstrapStepStatus` extension | **Authority-excluded:** no Paddr adaptation. |

### `SCMapprStyle.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `SCTextRole` | **Adapted:** `PaddrTextRole` and `paddrTypography(_:)`. |
| `SCInterfaceTextScale` and its environment support | **Not adapted:** Paddr uses native macOS text styles without a custom scale environment. |
| Typography modifier/support directly associated with `SCTextRole` | **Adapted:** `PaddrTypographyModifier`. |
| `SCLayout` | **Adapted:** `PaddrStyle.Spacing`, `Metrics`, `Radius`, and `Width`. |
| Panel modifiers | **Adapted:** `paddrCard()`, `PaddrCardModifier`, `PaddrSectionContainer`, and `PaddrInsetDivider`. |
| `SCPageHeaderStyle` | **Not adapted.** |
| `DetailScaffold` | **Not adapted:** `ConfigurationView` remains Paddr-owned window composition. |
| `SCStatusTileCard` | **Adapted:** `StatusCell` and the status-tile surface grammar in `PermissionTile`. |
| `SCEmptyStateCallout` | **Not adapted.** |
| `ParameterSlider` | **Adapted:** the presentation grammar in `ValueSliderRow`; Paddr retains its own ranges and bindings. |
| `PlainDeferredSlider` | **Not adapted:** Paddr uses a native `Slider`. |
| `SCControlRow` | **Adapted:** `PaddrSettingsRow`. |
| `BindingPresetPicker` | **Adapted:** `OutputBindingPicker`; Paddr's binding vocabulary and data remain unchanged. |
| `AccentOptionItem` | **Not adapted:** Paddr uses its existing pad/profile presentation values. |
| `AccentOptionSelector` | **Not adapted:** Paddr keeps both trackpad editors visible and has no side selector. |
| `SCActionButtonSize` | **Adapted as local geometry/role policy:** `PaddrButtonRole` and `PaddrStyle.Metrics.controlHeight`; no size enum was copied. |
| `SCActionButton` | **Adapted:** `PaddrActionButtonModifier` and `paddrActionButton(_:)`; native button behavior remains authoritative. |
| `SCButtonGroup` | **Not adapted.** |
| `SCActionGrid` | **Not adapted.** |
| `MetricRow` | **Not adapted.** |
| `AxisCircleView` | **Not adapted:** Paddr retains its own trackpad preview and hit-test geometry. |
| `TriggerBarView` | **Not adapted.** |
| `GyroPreviewView` | **Not adapted.** |
| `LiveButtonBadge` | **Not adapted.** |
| `DPadDirectionBadges` | **Not adapted.** |
| Panel-control chrome helpers | **Adapted:** `PaddrSettingsPrimitives` and the `paddrMenuSelector()` chrome only; controls retain native keyboard and focus behavior. |
| `SCMenuOption` | **Not adapted:** Paddr retains its own profile and binding option models. |
| `SCMenuSelector` | **Adapted only as menu chrome:** native Paddr `Picker` and `Menu` controls use `paddrMenuSelector()`. |
| `SCPanelSection` | **Adapted:** `PaddrSectionContainer` and `PaddrSettingsGroup`; Paddr does not adopt the reference persistence behavior. |
| `SCContextHelpCard` | **Adapted as tone/surface presentation:** `PermissionTile`; permission state and actions remain Paddr-owned. |
| `SCWindowConfigurator` | **Adapted only as the window geometry contract:** `PaddrStyle.Metrics`. Paddr's `AppDelegate` adds product-local full-size, transparent, separatorless family chrome while retaining visible titles, its regular unified configuration toolbar, usable-layout sizing, activation, and window lifecycle behavior. Legacy v4 and compact-titlebar v5 autosaved geometry migrates to the full-size v6 contract without losing usable size or top-edge position; content scrolls within the user-managed window instead of resizing it to the document. |

### `SCMapprAccessibility.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `SCAccessibility` namespace and slug/identifier algorithm | **Adapted:** `PaddrAccessibility`; the prefix is `paddr`, and identifiers exclude paths, controller IDs, profile names, and private runtime values. |
| Optional-identifier modifier | **Adapted:** `PaddrOptionalAccessibilityIdentifierModifier`. |
| Associated `View` helpers | **Adapted:** `paddrAccessibilityID` and `paddrOptionalAccessibilityID`. |

### `SCMapprShell.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `SCVisualRole` cases | **Adapted:** the Paddr-relevant subset is expressed by `StatusBadgeState`. |
| `SCVisualRole.color` | **Adapted:** `StatusBadgeState.color` and `textColor`; `.ready` maps to success green. |
| `SCVisualRole.displayName` | **Adapted as Paddr-specific localized status values in `StatusCell`, `PaddrReadiness`, and `MenuBarPresentation`; reference product wording is not copied.** |
| `SCVisualRole.accessibilityTitle` | **Adapted as explicit Paddr accessibility labels and values in `StatusCell` and `MenuBarPresentation`.** |
| `SCVisualRole.indicatorSymbol` | **Adapted as explicit SF Symbols at Paddr status call sites.** |
| Wine-specific initializer and every other shell/session declaration | **Authority-excluded:** no Paddr adaptation. |

### `SCMapprInputPanes.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `PadPreviewView` | **Adapted only as family presentation:** `PadModePreview`; Paddr's existing zone geometry and runtime hit testing remain authoritative. |
| `InputLayerContextBanner` | **Not adapted.** |
| `PadsPane` | **Not adapted:** the pinned authority uses a focused `selectedPadSide` workflow; Paddr deliberately keeps simultaneous Left/Right editors instead. |
| `PadConfigurationCards` | **Adapted:** `DualPadConfigurationView`, `PadConfigurationView`, and `PaddrAdaptiveSplitView`; Paddr supports only its existing Off, Pointer, Scroll, and Zones modes. |

Paddr's simultaneous dual-editor behavior is a deliberate product-specific divergence. Both
editors are visible in equal-height columns at the default window size and stack at their natural,
independent heights only below the narrow-width breakpoint. `AnyLayout` moves the same mounted
editor subtrees during reflow.

### `SCMapprPanes.swift`

| Pinned declaration | Disposition and Paddr-local expression |
| --- | --- |
| `ConsolePageHeader` | **Not adapted.** |
| `ConsoleProfilesPage` and its directly nested profile helpers | **Adapted only as compact profile interaction presentation:** `TopControlsView` and `ProfileControlsView`, including item-bound deletion confirmation. Paddr retains its existing profile operations, confirmation rules, and Save & Apply contract; no reference profile or game-target state is copied. |

## Token parity

| Paddr token | Value |
| --- | --- |
| `night0` | `#05060D` |
| `night1` | `#0D1126` |
| `interfaceBlue` | `#339EFF` |
| `interfacePurple` | `#7359FF` |
| `successGreen` | `#46B487` |
| `cautionAmber` | `#FFB340` |
| primary / secondary / tertiary text | `#FFFFFF` / `#D7E9FF` / `#9DC4F8` |
| control height / radius | `38` / `7` points |
| reference content width / outer spacing | `820` / `24` points; Paddr retains the outer spacing |
| Paddr default usable window / content width | `1280 × 700` / `1232` points; product-local width keeps both nested pad editors in columns |
| configuration titlebar | native regular unified style; 15-point AppKit title, transparent background, no separator; compact v5 frames migrate to v6 without losing usable height or their top edge |
| card / inset-panel content margin | `16` / `16` points; the card modifier and section container own these insets |
| sibling-card / row / inline-control gap | `16` / `12` / `8` points |
| preview–inspector gutter | `24` points |
| status-pill minimum height / horizontal inset | `32` / `12` points; resolved icon-only pills use an 8-point inset |

Paddr keeps the canonical palette, control sizing, and outer spacing intact. Its Paddr-local
native type ladder is 22-point page title, 17-point card title, 15-point section title,
13-point band label, 12-point row/value, and 10-point metadata. Each role carries its weight:
page and card titles are bold, section and band titles are semibold, and values retain
monospaced digits.
Its wider default window is the product-local layout decision described below. The following
Paddr-local semantic derivatives pair the shared tokens accessibly and are not additional
claims of BottleRocket token parity:

| Semantic use | Paddr resolution |
| --- | --- |
| Native selected/prominent control tint with white foreground | `#006EC3` / `#FFFFFF` |
| Success text over layered dark surfaces | `#52C99A`; canonical `#46B487` remains the fill/border tone |
| Selected pad/zone boundary | `#FFFFFF` over the canonical purple or blue-to-purple wash |
| Selected zone caption | `#FFFFFF` on `#006EC3` |
| Permission boundary | Canonical green or amber at 75% opacity; 100% in Increased Contrast |
| Standard / Increased Contrast surfaces | 5% / 9% white, elevated 8% / 14%, stroke 10% / 28% |

## Required Paddr behavior

- Left and Right configurations remain independent and keep their existing encoded form.
- Both Left and Right editors stay mounted and independently bound to their existing
  configuration values. There is no selected-side state or persistence seam.
- Fresh default geometry uses a 1280×700-point usable window and two equal 608-point pad
  columns, keeping each pad preview and its settings visible side-by-side. Wider user or
  restored windows expand those columns fluidly; existing autosaved sizes remain respected,
  document height remains user-controlled, and the configuration surface scrolls within it.
- The 24-point canvas margin, 16-point primary-card and inset-panel margins, 16-point sibling-card
  gap, 12-point row rhythm, 8-point inline-control gap, and 4-point icon gap form one declared
  spacing hierarchy. Fixed 190×182 pad maps center inside compact sections, and settings-row
  width budgets include both 16-point card and section insets before selecting a horizontal
  nested split. Preview and settings columns use a protected 24-point whitespace gutter rather
  than a vertical divider.
- Responsive pad and zone layouts use `AnyLayout` to move one mounted child tree;
  no stateful editor or control closure is duplicated under `ViewThatFits`. Accessibility
  text sizes stack both editor and preview/inspector splits even at wide regular-text widths,
  so fixed native controls never compete with scaled labels.
- Statuses are ordered Access, Puck, Controller, Output, and Battery. Resolved non-battery
  statuses compact to a green symbol-only pill while preserving their full accessibility label,
  value, and help text; unresolved statuses retain visible text. Battery always retains its
  percentage and uses healthy green at 60% or higher, caution amber from 20–59%, critical red
  below 20%, and neutral styling when unavailable. Detailed labels and values share the native
  callout size, with distinct title-to-value spacing and 12-point side padding. The 32-point pills
  wrap as whole controls rather than shrinking at narrow widths or Accessibility text sizes. Increased Contrast,
  Differentiate Without Color, Reduce Transparency, and Reduce Motion are resolved by
  `PaddrAppearance`.
- Status and menu semantics are ordered and deterministic. The pure readiness resolver
  identifies the next action and gives the output control a specific disabled reason.
- All newly introduced user-facing text is reachable through
  `Resources/Localizable.xcstrings`.

## Explicit exclusions

The BottleRocket name appears only where required to identify the MIT-licensed source in
repository provenance documentation and the bundled mandatory MIT attribution notice. It is
not used as Paddr product branding. No BottleRocket mark, icon, wordmark,
launch/bottle/plume metaphor, screenshot, Wine or CrossOver wording, game-target flow,
bridge/session logic, release process, controller runtime, persistence implementation, or
private repository path ships in Paddr application code or user-facing product resources.

## Attribution

`THIRD_PARTY_NOTICES.md` retains the MIT notice required by the grant.
`scripts/build-app.sh` installs it as
`Paddr.app/Contents/Resources/ThirdPartyNotices.txt`, and the Help and status menus expose
an **Open Source Notices…** command.
