import AppKit
import SwiftUI
import XCTest

import PaddrAppSupport
@testable import PaddrMenu
import PaddrCore

@MainActor
final class MenuViewPresentationTests: XCTestCase {
    func testPendingProfileActionsCaptureKindIDAndDisplayedName() {
        let id = ConfigurationProfileID(
            rawValue: "00000000-0000-0000-0000-000000000501"
        )

        XCTAssertEqual(
            PendingProfileAction.rename(id: id, name: "Original"),
            PendingProfileAction(kind: .rename, profileID: id, profileName: "Original")
        )
        XCTAssertEqual(
            PendingProfileAction.delete(id: id, name: "Original"),
            PendingProfileAction(kind: .delete, profileID: id, profileName: "Original")
        )
        XCTAssertEqual(
            PendingProfileAction.create(suggestedName: "New Profile"),
            PendingProfileAction(
                kind: .create,
                profileID: nil,
                profileName: "New Profile"
            )
        )
    }

    func testFamilyWindowChromeUsesFullSizeTransparentSeparatorlessTitlebar() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PaddrStyle.Metrics.defaultWindowSize),
            styleMask: PaddrFamilyWindowChrome.styleMask,
            backing: .buffered,
            defer: false
        )

        PaddrFamilyWindowChrome.apply(to: window)

        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertTrue(window.styleMask.contains(.closable))
        XCTAssertTrue(window.styleMask.contains(.miniaturizable))
        XCTAssertTrue(window.styleMask.contains(.resizable))
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertEqual(window.titlebarSeparatorStyle, .none)
    }

    func testConfigurationWindowMetricsDescribeUsableLayoutWithUnifiedCompactToolbar() {
        let window = makeWindow(hasToolbar: true, usesFullSizeContent: true)
        let delegate = WindowDelegateProbe()
        window.delegate = delegate

        PaddrFamilyWindowChrome.apply(to: window)
        PaddrFamilyWindowChrome.setUsableLayoutSize(
            PaddrStyle.Metrics.defaultWindowSize,
            for: window
        )
        PaddrFamilyWindowChrome.setMinimumUsableLayoutSize(
            PaddrStyle.Metrics.minimumWindowSize,
            for: window
        )
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertNotNil(window.toolbar)
        XCTAssertEqual(window.titleVisibility, .visible)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.defaultWindowSize)

        window.setContentSize(window.contentMinSize)
        window.contentView?.layoutSubtreeIfNeeded()

        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.minimumWindowSize)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.delegate === delegate)
    }

    func testGuideWindowMetricsDescribeUsableLayoutWithoutToolbar() {
        let window = makeWindow(hasToolbar: false, usesFullSizeContent: true)

        PaddrFamilyWindowChrome.apply(to: window)
        PaddrFamilyWindowChrome.setUsableLayoutSize(
            PaddrStyle.Metrics.guideWindowSize,
            for: window
        )
        PaddrFamilyWindowChrome.setMinimumUsableLayoutSize(
            PaddrStyle.Metrics.minimumGuideWindowSize,
            for: window
        )
        window.contentView?.layoutSubtreeIfNeeded()

        XCTAssertNil(window.toolbar)
        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.guideWindowSize)

        window.setContentSize(window.contentMinSize)
        window.contentView?.layoutSubtreeIfNeeded()

        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.minimumGuideWindowSize)
    }

    func testLegacyAutosavedPhysicalFrameRetainsUsableSizeAndPositionWithFamilyChrome() {
        let autosaveName = "PaddrConfigurationWindow.v4.Tests.\(UUID().uuidString)"
        let legacyUsableSize = NSSize(width: 868, height: 680)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let legacyWindow = makeWindow(hasToolbar: true, usesFullSizeContent: false)
        legacyWindow.setContentSize(legacyUsableSize)
        legacyWindow.center()
        legacyWindow.contentView?.layoutSubtreeIfNeeded()
        let legacyLayoutSize = legacyWindow.contentLayoutRect.size
        let legacyFrame = legacyWindow.frame
        legacyWindow.saveFrame(usingName: autosaveName)

        let familyWindow = makeWindow(hasToolbar: true, usesFullSizeContent: true)
        PaddrFamilyWindowChrome.apply(to: familyWindow)

        XCTAssertTrue(familyWindow.setFrameUsingName(autosaveName))
        let restoredLegacyUsableSize = familyWindow.contentRect(
            forFrameRect: familyWindow.frame
        ).size
        PaddrFamilyWindowChrome.setUsableLayoutSize(
            restoredLegacyUsableSize,
            for: familyWindow
        )
        PaddrFamilyWindowChrome.setMinimumUsableLayoutSize(
            PaddrStyle.Metrics.minimumWindowSize,
            for: familyWindow
        )
        familyWindow.contentView?.layoutSubtreeIfNeeded()

        XCTAssertTrue(familyWindow.frame.isApproximatelyEqual(to: legacyFrame))
        assertSize(familyWindow.contentLayoutRect.size, equals: legacyLayoutSize)
        assertSize(familyWindow.contentLayoutRect.size, equals: legacyUsableSize)
    }

    func testAccessibilityOnboardingPageFitsCompactWindowWithoutScrolling() throws {
        var pager = OnboardingPager()
        pager.advance()
        pager.advance()
        let model = PaddrMenuModel(dependencies: dependencies(store: BlockingProfileStore()))
        let view = OnboardingGuideView(
            model: model,
            onSkip: {},
            onComplete: {},
            initialPager: pager
        )
        XCTAssertEqual(PaddrStyle.Metrics.guideWindowSize, NSSize(width: 720, height: 480))
        XCTAssertEqual(PaddrStyle.Metrics.minimumGuideWindowSize, NSSize(width: 640, height: 460))

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.Metrics.guideWindowSize)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.guideWindowSize.height,
            accuracy: 0.5
        )
        let scrollView = try XCTUnwrap(firstDescendant(of: NSScrollView.self, in: hostingView))
        let documentView = try XCTUnwrap(scrollView.documentView)
        documentView.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(documentView.fittingSize.height, scrollView.contentSize.height + 0.5)
    }

    func testDualPadWorkflowMountsTwoPadModeControls() {
        let view = DualPadConfigurationView(
            configuration: .constant(.default),
            appearsEnabled: true,
            isEditable: true
        )
        .frame(width: PaddrStyle.Metrics.defaultContentWidth)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: PaddrStyle.Metrics.defaultContentWidth, height: 620)
        )
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            descendants(of: NSSegmentedControl.self, in: hostingView).count,
            2,
            "Both pad-mode editors must remain mounted together"
        )
    }

    func testFamilyConsoleRendersAtDefaultWindowSize() async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)

        let hostingView = NSHostingView(rootView: ConfigurationView(model: model))
        hostingView.frame = NSRect(origin: .zero, size: PaddrStyle.Metrics.defaultWindowSize)
        await settle(hostingView)

        XCTAssertEqual(hostingView.bounds.size, PaddrStyle.Metrics.defaultWindowSize)
        XCTAssertGreaterThan(descendants(of: NSControl.self, in: hostingView).count, 2)
        for control in descendants(of: NSControl.self, in: hostingView) {
            let frame = control.convert(control.bounds, to: hostingView)
            XCTAssertGreaterThanOrEqual(frame.minX, hostingView.bounds.minX - 0.5)
            XCTAssertLessThanOrEqual(frame.maxX, hostingView.bounds.maxX + 0.5)
        }

        if let snapshotPath = ProcessInfo.processInfo.environment["PADDR_UI_SNAPSHOT_PATH"] {
            let representation = try XCTUnwrap(
                hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
            )
            hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
            let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: snapshotPath), options: .atomic)
        }
    }

    func testFamilyConsoleLeavesWindowHeightUnderUserAndAutosaveControl() async {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)

        let window = makeWindow(hasToolbar: false, usesFullSizeContent: true)
        window.contentViewController = NSHostingController(
            rootView: ConfigurationView(model: model)
        )
        PaddrFamilyWindowChrome.apply(to: window)
        PaddrFamilyWindowChrome.setUsableLayoutSize(
            PaddrStyle.Metrics.defaultWindowSize,
            for: window
        )
        let expectedFrame = window.frame

        if let contentView = window.contentView {
            for _ in 0..<12 {
                contentView.layoutSubtreeIfNeeded()
                await Task.yield()
            }
        }

        XCTAssertTrue(window.frame.isApproximatelyEqual(to: expectedFrame))
        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.defaultWindowSize)
    }

    func testPaddrAppearanceResolvesEveryAdaptiveCombination() {
        for reduceTransparency in [false, true] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for differentiateWithoutColor in [false, true] {
                    for reduceMotion in [false, true] {
                        let appearance = PaddrAppearance(
                            reduceTransparency: reduceTransparency,
                            colorSchemeContrast: contrast,
                            differentiateWithoutColor: differentiateWithoutColor,
                            reduceMotion: reduceMotion
                        )
                        let increased = contrast == .increased
                        XCTAssertEqual(appearance.usesOpaqueFallback, reduceTransparency)
                        XCTAssertEqual(appearance.hasIncreasedContrast, increased)
                        XCTAssertEqual(appearance.usesShapeDifferentiation, differentiateWithoutColor)
                        XCTAssertEqual(appearance.reducesMotion, reduceMotion)
                        XCTAssertEqual(appearance.strokeWidth, increased ? 1.5 : 1)
                        XCTAssertEqual(appearance.strokeOpacity(0.46), increased ? 1 : 0.46)
                        XCTAssertEqual(appearance.strokeOpacity(0.18), increased ? 1 : 0.18)
                        XCTAssertEqual(appearance.animation(.default) == nil, reduceMotion)
                        XCTAssertNil(appearance.animation(nil))
                    }
                }
            }
        }
    }

    func testSettingsRowControlsStayWithinTheSharedRowHeightInEveryPadMode() async {
        for width in [PaddrStyle.minimumPadColumnWidth, PaddrStyle.padColumnWidth] {
            for mode in PadMode.allCases {
                for layout in PadZoneLayout.allCases {
                    var configuration = PadConfiguration(mode: mode)
                    configuration.zoneLayout = layout
                    let hostingView = NSHostingView(
                        rootView: PadConfigurationView(
                            side: .left,
                            configuration: .constant(configuration)
                        )
                        .frame(width: width)
                    )
                    hostingView.frame = NSRect(
                        origin: .zero,
                        size: NSSize(
                            width: width,
                            height: PaddrStyle.Metrics.defaultWindowSize.height
                        )
                    )
                    await settle(hostingView)

                    for control in descendants(of: NSControl.self, in: hostingView) {
                        XCTAssertLessThanOrEqual(
                            control.bounds.height,
                            PaddrStyle.Metrics.row + 0.5,
                            "\(type(of: control)) in \(mode)/\(layout) at \(width)pt "
                                + "is taller than the row family"
                        )
                        assertControlFits(control, in: hostingView)
                    }
                }
            }
        }
    }

    /// A SwiftUI `Slider` renders no `NSControl` descendant on this SDK, so the switch is
    /// the probe that is actually reachable through the `descendants(of:)` seam.
    func testSettingsRowCentersItsControlInTheSharedRowHeight() throws {
        let row = PaddrSettingsRow(title: "Track pointer", systemImage: "scope") {
            Toggle("Track pointer", isOn: .constant(true))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .frame(width: PaddrStyle.padColumnWidth)
        let hostingView = NSHostingView(rootView: row)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.padColumnWidth,
                height: hostingView.fittingSize.height
            )
        )
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.bounds.height,
            PaddrStyle.Metrics.row,
            accuracy: 0.5
        )
        let toggle = try XCTUnwrap(firstDescendant(of: NSControl.self, in: hostingView))
        let frame = toggle.convert(toggle.bounds, to: hostingView)
        XCTAssertLessThanOrEqual(frame.height, PaddrStyle.Metrics.row + 0.5)
        XCTAssertEqual(frame.midY, hostingView.bounds.midY, accuracy: 0.5)
    }

    func testFlexibleSettingsRowAlignsItsSwitchWithThePickerControlEdge() throws {
        let rows = VStack(spacing: PaddrStyle.Spacing.s3) {
            PaddrSettingsRow(
                title: "Track pointer inside tap radius",
                systemImage: "cursorarrow.motionlines",
                labelWidth: nil
            ) {
                Toggle("Track pointer inside tap radius", isOn: .constant(true))
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            PaddrSettingsRow(title: "Touch tap", systemImage: "hand.tap") {
                SettingsControlEdgeProbe(identifier: "picker-edge")
                    .frame(width: PaddrStyle.Width.control)
            }
        }
        .frame(width: PaddrStyle.minimumPadSectionWidth)
        let hostingView = NSHostingView(rootView: rows)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.minimumPadSectionWidth,
                height: hostingView.fittingSize.height
            )
        )
        hostingView.layoutSubtreeIfNeeded()

        let toggle = try XCTUnwrap(firstDescendant(of: NSSwitch.self, in: hostingView))
        let pickerEdge = try XCTUnwrap(
            descendants(of: NSView.self, in: hostingView).first {
                $0.identifier?.rawValue == "picker-edge"
            }
        )
        XCTAssertEqual(
            toggle.convert(toggle.bounds, to: hostingView).maxX,
            pickerEdge.convert(pickerEdge.bounds, to: hostingView).maxX,
            accuracy: 1
        )
    }

    func testSettingsGroupAddsItsSeparatingDividerOnlyWhenDeclared() {
        func groupHeight(showsLeadingDivider: Bool) -> CGFloat {
            let group = PaddrSettingsGroup(showsLeadingDivider: showsLeadingDivider) {
                PaddrSettingsRow(title: "Sensitivity", systemImage: "speedometer") {
                    Slider(value: .constant(0.5), in: 0...1)
                        .frame(width: PaddrStyle.Width.control)
                }
            }
            .frame(width: PaddrStyle.padColumnWidth)
            let hostingView = NSHostingView(rootView: group)
            hostingView.layoutSubtreeIfNeeded()
            return hostingView.fittingSize.height
        }

        XCTAssertGreaterThan(
            groupHeight(showsLeadingDivider: true),
            groupHeight(showsLeadingDivider: false)
        )
    }

    /// The inset section inside one dual-pad column is the binding constraint on the width
    /// scale. A starved label can wrap mid-word and a slider can push every peer row beyond
    /// the section border, so the complete row budgets are asserted directly.
    func testPickerRowFitsItsInlineBranchInsideTheInspectorColumn() {
        XCTAssertLessThanOrEqual(
            PaddrStyle.Width.labelColumn + PaddrStyle.Spacing.s3 + PaddrStyle.Width.control,
            PaddrStyle.minimumPadSectionWidth,
            "A picker row's inline branch must fit the inspector column"
        )
        let modeRow = PaddrSettingsRow(title: "Mode", systemImage: "square.grid.2x2") {
            Picker("Area layout", selection: .constant(PadZoneLayout.fourCorners)) {
                Text("Four corners").tag(PadZoneLayout.fourCorners)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: PaddrStyle.Width.controlMedium)
        }
        .frame(width: PaddrStyle.minimumPadSectionWidth)
        let modeHostingView = NSHostingView(rootView: modeRow)
        modeHostingView.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            PaddrStyle.Width.labelColumn
                + PaddrStyle.Spacing.s3
                + PaddrStyle.Width.controlMedium,
            PaddrStyle.minimumPadSectionWidth,
            "The icon-bearing area-layout row must fit the inspector column"
        )
        XCTAssertEqual(modeHostingView.fittingSize.height, PaddrStyle.Metrics.row, accuracy: 0.5)

        let row = PaddrSettingsRow(title: "Action", systemImage: "keyboard") {
            OutputBindingPicker(
                selection: .constant("Up arrow"),
                width: PaddrStyle.Width.control
            )
        }
        .frame(width: PaddrStyle.minimumPadSectionWidth)
        let hostingView = NSHostingView(rootView: row)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertEqual(
            hostingView.fittingSize.height,
            PaddrStyle.Metrics.row,
            accuracy: 0.5,
            "The inline row no longer fits the inspector column"
        )
    }

    func testSliderRowFitsInsideTheInsetPadSection() {
        let sliderRowWidth = PaddrStyle.Width.labelColumnWide
            + PaddrStyle.Spacing.s3
            + PaddrStyle.sliderMinimumWidth
            + PaddrStyle.Spacing.s2
            + PaddrStyle.Width.readout

        XCTAssertGreaterThanOrEqual(
            PaddrStyle.sliderMinimumWidth,
            120,
            "The compact breakpoint must preserve a usable native slider"
        )
        let longestLabel = NSHostingView(
            rootView: Label(
                LocalizedStringResource("Pointer acceleration"),
                systemImage: "arrow.up.right.and.arrow.down.left"
            )
            .paddrTypography(.rowLabel)
        )
        longestLabel.layoutSubtreeIfNeeded()
        XCTAssertLessThanOrEqual(
            longestLabel.fittingSize.width,
            PaddrStyle.Width.labelColumnWide,
            "The compact slider label column must not truncate its longest label"
        )
        XCTAssertLessThanOrEqual(
            sliderRowWidth,
            PaddrStyle.minimumPadSectionWidth,
            "A slider row must not push itself or neighboring rows beyond the inset section"
        )
        XCTAssertEqual(
            PaddrStyle.minimumPadSectionWidth,
            PaddrStyle.minimumPadColumnWidth - (4 * PaddrStyle.Spacing.s3),
            "The width budget must include both card and section horizontal padding"
        )
        XCTAssertEqual(
            PaddrStyle.previewInspectorColumnsBreakpoint,
            PaddrStyle.Metrics.zoneMapWidth
                + PaddrStyle.minimumPadSectionWidth
                + PaddrStyle.previewInspectorSpacing,
            "The nested split must derive its breakpoint from the complete rendered row"
        )
    }

    /// The public `colorSchemeContrast`, `accessibilityReduceTransparency`, and
    /// `accessibilityDifferentiateWithoutColor` values are read-only, so the hosted matrix
    /// drives them through their underscore-prefixed writable key paths. `PaddrAppearance`'s
    /// own resolution of the same inputs is proved separately by
    /// `testPaddrAppearanceResolvesEveryAdaptiveCombination`.
    func testAdaptiveMatrixKeepsSurfacesFiniteAndControlsInsideTheHost() {
        for colorScheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                for reduceTransparency in [false, true] {
                    for differentiateWithoutColor in [false, true] {
                        let view = adaptiveMatrixSubject
                            .environment(\.colorScheme, colorScheme)
                            .environment(\._colorSchemeContrast, contrast)
                            .environment(\._accessibilityReduceTransparency, reduceTransparency)
                            .environment(
                                \._accessibilityDifferentiateWithoutColor,
                                differentiateWithoutColor
                            )

                        let label = """
                            \(colorScheme)/\(contrast)/\
                            reduceTransparency:\(reduceTransparency)/\
                            differentiateWithoutColor:\(differentiateWithoutColor)
                            """
                        let hostingView = NSHostingView(rootView: view)
                        let fitted = hostingView.fittingSize
                        XCTAssertTrue(fitted.width.isFinite, label)
                        XCTAssertTrue(fitted.height.isFinite, label)
                        XCTAssertGreaterThan(fitted.height, 0, label)

                        hostingView.frame = NSRect(
                            origin: .zero,
                            size: NSSize(width: PaddrStyle.padColumnWidth, height: fitted.height)
                        )
                        hostingView.layoutSubtreeIfNeeded()
                        for control in descendants(of: NSControl.self, in: hostingView) {
                            assertControlFits(control, in: hostingView)
                        }
                    }
                }
            }
        }
    }

    /// The three surfaces this slice moved onto `PaddrAppearance`: the card chrome, the
    /// status chip, and the permission row.
    private var adaptiveMatrixSubject: some View {
        VStack(spacing: PaddrStyle.Spacing.s3) {
            StatusCell(
                title: LocalizedStringResource("Output"),
                value: LocalizedStringResource("Active"),
                systemImage: "wave.3.right.circle.fill",
                state: .active
            )
            PermissionTile(
                title: LocalizedStringResource("Accessibility"),
                detail: LocalizedStringResource("Sends mapped mouse, scroll, and keyboard input."),
                isGranted: false,
                requestAction: {},
                settingsAction: {}
            )
            PadConfigurationView(
                side: .left,
                configuration: .constant(PaddrConfiguration.default.left)
            )
        }
        .frame(width: PaddrStyle.padColumnWidth)
        .background { PanelBackgroundView() }
    }

    func testPointerTrackingToggleReflectsDefaultsAndLegacyBindingAtRadiusZero() async throws {
        let defaultView = PadConfigurationView(
            side: .right,
            configuration: .constant(PadConfiguration(mode: .mouse))
        )
        .frame(width: PaddrStyle.Metrics.minimumWindowSize.width - (2 * PaddrStyle.Spacing.s4))
        let defaultHostingView = NSHostingView(rootView: defaultView)
        defaultHostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.Metrics.minimumWindowSize.width - (2 * PaddrStyle.Spacing.s4),
                height: 640
            )
        )
        await settle(defaultHostingView)

        let defaultToggle = try XCTUnwrap(
            firstDescendant(of: NSSwitch.self, in: defaultHostingView)
        )
        XCTAssertEqual(defaultToggle.state, .on)
        XCTAssertEqual(defaultToggle.accessibilityRoleDescription(), "switch")
        XCTAssertEqual(accessibilityIntegerValue(of: defaultToggle), 1)
        XCTAssertTrue(defaultToggle.isEnabled)
        let defaultControls = descendants(of: NSControl.self, in: defaultHostingView)
        XCTAssertGreaterThanOrEqual(defaultControls.count, 2)
        for control in defaultControls {
            assertControlFits(control, in: defaultHostingView)
        }

        var legacy = try JSONDecoder().decode(
            PadConfiguration.self,
            from: Data("{\"mode\":\"mouse\",\"mouseDeadzone\":0}".utf8)
        )
        let legacyBinding = Binding(
            get: { legacy },
            set: { legacy = $0 }
        )
        let legacyView = PadConfigurationView(
            side: .right,
            configuration: legacyBinding
        )
        .frame(width: PaddrStyle.padColumnWidth)
        let legacyHostingView = NSHostingView(rootView: legacyView)
        legacyHostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.padColumnWidth,
                height: PaddrStyle.Metrics.defaultWindowSize.height
            )
        )
        await settle(legacyHostingView)

        let legacyToggle = try XCTUnwrap(
            firstDescendant(of: NSSwitch.self, in: legacyHostingView)
        )
        XCTAssertEqual(legacy.centerTapTrackingMode, .coupled)
        XCTAssertEqual(legacyToggle.state, .off)
        XCTAssertEqual(legacyToggle.accessibilityRoleDescription(), "switch")
        XCTAssertEqual(accessibilityIntegerValue(of: legacyToggle), 0)
        XCTAssertTrue(legacyToggle.isEnabled)
        legacyToggle.performClick(nil)
        await settle(legacyHostingView)
        XCTAssertEqual(legacy.centerTapTrackingMode, .decoupled)
        XCTAssertEqual(legacyToggle.state, .on)
        XCTAssertEqual(accessibilityIntegerValue(of: legacyToggle), 1)
        assertControlFits(legacyToggle, in: legacyHostingView)
    }

    func testProfilePickerPresentsPendingCreatedProfile() async throws {
        try await assertPendingProfilePicker(
            expectedName: "Third",
            operation: { $0.createProfile(named: "Third") }
        )
    }

    func testProfilePickerPresentsPendingDuplicatedProfile() async throws {
        try await assertPendingProfilePicker(
            expectedName: "Default Copy",
            operation: { $0.duplicateActiveProfile() }
        )
    }

    func testFiveStatusPillsFitMinimumWindowWidthWithUnavailableBattery() async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        XCTAssertNil(model.receiverDescription)
        XCTAssertFalse(model.controllerConnected)
        XCTAssertNil(model.batteryStatus)

        assertApplyBarFitsMinimumWindow(model: model)
    }

    func testFiveStatusPillsFitMinimumWindowWidthWithLongestBatteryValue() async throws {
        let store = BlockingProfileStore()
        let session = PresentationSession()
        let model = PaddrMenuModel(
            dependencies: dependencies(
                store: store,
                session: session,
                receiver: "Fake receiver"
            )
        )
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        let didStart = await waitUntil { await session.startCount == 1 }
        XCTAssertTrue(didStart)
        await session.send(.controllerConnected)
        await session.send(.batteryUpdated(.init(chargeState: .chargingDone, percentage: 100)))
        let didPublishBattery = await waitUntil { model.batteryStatus?.percentage == 100 }
        XCTAssertTrue(didPublishBattery)

        assertApplyBarFitsMinimumWindow(model: model)
        _ = await session.stop()
    }

    func testWidestStatusPayloadsWrapInsideMinimumBarContentWidth() {
        let contentWidth = PaddrStyle.Metrics.minimumWindowSize.width
            - (2 * PaddrStyle.Metrics.outerSpacing)
        let row = PaddrWrappingHStack(
            horizontalSpacing: PaddrStyle.Spacing.s2,
            verticalSpacing: PaddrStyle.Spacing.s2
        ) {
            StatusCell(
                title: "Puck",
                value: LocalizedStringResource("Not found"),
                systemImage: "cable.connector.slash",
                state: .problem
            )
            StatusCell(
                title: "Controller",
                value: LocalizedStringResource("Not found"),
                systemImage: "gamecontroller",
                state: .problem
            )
            StatusCell(
                title: "Battery",
                value: String("100%"),
                systemImage: "battery.100percent",
                state: .neutral
            )
            StatusCell(
                title: "Output",
                value: LocalizedStringResource("Releasing"),
                systemImage: "pause.circle",
                state: .neutral
            )
            StatusCell(
                title: "Access",
                value: LocalizedStringResource("Needed"),
                systemImage: "exclamationmark.shield",
                state: .problem
            )
        }
        .frame(width: contentWidth, alignment: .leading)
        let hostingView = NSHostingView(rootView: row)
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertLessThanOrEqual(
            hostingView.fittingSize.width,
            contentWidth
        )
        XCTAssertGreaterThanOrEqual(
            hostingView.fittingSize.height,
            (2 * PaddrStyle.Metrics.row) + PaddrStyle.Spacing.s2,
            "Larger status pills should wrap as whole controls at the minimum width"
        )
    }

    private func assertApplyBarFitsMinimumWindow(
        model: PaddrMenuModel,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let controller = NSHostingController(rootView: ApplyBarView(model: model))
        let fitted = controller.sizeThatFits(
            in: NSSize(width: PaddrStyle.Metrics.minimumWindowSize.width, height: 400)
        )
        XCTAssertLessThanOrEqual(
            fitted.width,
            PaddrStyle.Metrics.minimumWindowSize.width + 0.5,
            file: file,
            line: line
        )
        XCTAssertGreaterThan(fitted.height, 0, file: file, line: line)
    }

    private func assertPendingProfilePicker(
        expectedName: String,
        operation: @MainActor (PaddrMenuModel) -> Bool
    ) async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }

        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)
        XCTAssertTrue(operation(model))
        let didStartSave = await waitUntil { store.didStartSave }
        XCTAssertTrue(didStartSave)

        guard case let .switching(to: pendingID, named: pendingName) = model.profileSelectionPresentation else {
            return XCTFail("Expected a pending profile selection")
        }
        XCTAssertEqual(pendingName, expectedName)
        XCTAssertFalse(model.profiles.contains(where: { $0.id == pendingID }))

        let presentation = ProfileControlsView(model: model).profilePickerPresentation
        let pendingOption = try XCTUnwrap(presentation.options.first { $0.id == pendingID })
        XCTAssertEqual(pendingOption.label, "Switching to \(expectedName)…")
        XCTAssertEqual(presentation.accessibilityValue, "Switching to \(expectedName)")
    }

    private func accessibilityIntegerValue(of object: NSObject) -> Int? {
        let selector = NSSelectorFromString("accessibilityValue")
        guard object.responds(to: selector),
              let value = object.perform(selector)?.takeUnretainedValue() as? NSNumber else {
            return nil
        }
        return value.intValue
    }

    private func assertControlFits(
        _ control: NSControl,
        in hostingView: NSView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = control.convert(control.bounds, to: hostingView)
        XCTAssertGreaterThanOrEqual(frame.minX, hostingView.bounds.minX - 0.5, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, hostingView.bounds.minY - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, hostingView.bounds.maxX + 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, hostingView.bounds.maxY + 0.5, file: file, line: line)
    }

    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> [ViewType] {
        let current = (view as? ViewType).map { [$0] } ?? []
        return current + view.subviews.flatMap { descendants(of: type, in: $0) }
    }

    private func firstDescendant<ViewType: NSView>(
        of type: ViewType.Type,
        in view: NSView
    ) -> ViewType? {
        descendants(of: type, in: view).first
    }

    private func dependencies(
        store: BlockingProfileStore,
        session: any TrackpadSessionControlling = InertSession(),
        receiver: String? = nil
    ) -> MenuDependencies {
        MenuDependencies(
            session: session,
            loadProfiles: { ConfigurationProfileLoadResult(document: .default) },
            saveProfiles: store.save,
            probeReceiver: { receiver },
            accessibilityTrusted: { _ in true },
            openPrivacySettings: { _ in },
            sleep: { duration in try await Task.sleep(for: duration) },
            reconnectDelay: { _ in throw CancellationError() }
        )
    }

    private func settle(_ hostingView: NSView) async {
        for _ in 0..<6 {
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
        }
    }

    private func makeWindow(
        hasToolbar: Bool,
        usesFullSizeContent: Bool
    ) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if usesFullSizeContent { styleMask.insert(.fullSizeContentView) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: PaddrStyle.Metrics.defaultWindowSize),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = "Paddr"
        window.titleVisibility = .visible
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior.insert(.fullScreenNone)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        if hasToolbar {
            window.contentViewController = NSHostingController(rootView: WindowToolbarProbe())
        } else {
            window.contentViewController = NSHostingController(rootView: Color.clear)
        }
        return window
    }

    private func assertSize(
        _ actual: NSSize,
        equals expected: NSSize,
        accuracy: CGFloat = 0.5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: accuracy, file: file, line: line)
    }
}

private final class WindowDelegateProbe: NSObject, NSWindowDelegate {}

private struct WindowToolbarProbe: View {
    var body: some View {
        Color.clear
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {}
                }
            }
    }
}

private struct SettingsControlEdgeProbe: NSViewRepresentable {
    let identifier: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(identifier)
    }
}

private extension CGRect {
    func isApproximatelyEqual(to other: CGRect, accuracy: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) <= accuracy
            && abs(minY - other.minY) <= accuracy
            && abs(width - other.width) <= accuracy
            && abs(height - other.height) <= accuracy
    }
}

private struct InertSession: TrackpadSessionControlling {
    func start(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome { .clean }
}

private actor PresentationSession: TrackpadSessionControlling {
    private var continuation: AsyncStream<TrackpadSessionEvent>.Continuation?
    private(set) var startCount = 0

    func start(
        configuration: PaddrConfiguration,
        observeOnly: Bool,
        outputGate: OutputGate?
    ) async -> AsyncStream<TrackpadSessionEvent> {
        startCount += 1
        let (stream, continuation) = AsyncStream<TrackpadSessionEvent>.makeStream()
        self.continuation = continuation
        return stream
    }

    @discardableResult
    func stop() async -> TrackpadSessionStopOutcome {
        continuation?.finish()
        continuation = nil
        return .clean
    }

    func send(_ event: TrackpadSessionEvent) {
        continuation?.yield(event)
    }
}

private final class BlockingProfileStore: @unchecked Sendable {
    private let gate = BoundedTestGate()
    private let lock = NSLock()
    private var saveStarted = false
    private var saveReleased = false

    var didStartSave: Bool {
        lock.withLock { saveStarted }
    }

    func save(_ document: ConfigurationProfileDocument) {
        lock.withLock { saveStarted = true }
        gate.wait()
    }

    func releaseSave() {
        let shouldSignal = lock.withLock {
            guard !saveReleased else { return false }
            saveReleased = true
            return true
        }
        if shouldSignal {
            gate.signal()
        }
    }
}
