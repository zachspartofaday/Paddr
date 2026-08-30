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

    func testConfigurationWindowMetricsDescribeUsableLayoutWithCompactToolbar() {
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
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(window.toolbarStyle, .unifiedCompact)
        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.defaultWindowSize)

        window.setContentSize(window.contentMinSize)
        window.contentView?.layoutSubtreeIfNeeded()

        assertSize(window.contentLayoutRect.size, equals: PaddrStyle.Metrics.minimumWindowSize)
        XCTAssertFalse(window.isReleasedWhenClosed)
        XCTAssertTrue(window.delegate === delegate)
    }

    func testConfigurationTitleIsPlainLeadingAndLargerThanTheNativeCompactTitle() throws {
        let window = makeWindow(hasToolbar: true, usesFullSizeContent: true)
        let accessory = try XCTUnwrap(window.titlebarAccessoryViewControllers.first)
        let label = try XCTUnwrap(
            descendants(of: NSTextField.self, in: accessory.view).first
        )

        XCTAssertEqual(window.title, "Paddr")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertEqual(accessory.layoutAttribute, .leading)
        XCTAssertEqual(label.stringValue, "Paddr")
        XCTAssertEqual(label.font?.pointSize, PaddrFamilyWindowChrome.configurationTitlePointSize)
        XCTAssertFalse(label.isBezeled)
        XCTAssertFalse(label.drawsBackground)
        XCTAssertFalse(label.isEditable)
        XCTAssertFalse(label.isSelectable)
    }

    func testConfigurationToolbarRetainsFlexibleSpaceBesideTheCustomTitle() async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }

        let window = makeWindow(hasToolbar: false, usesFullSizeContent: true)
        window.contentViewController = NSHostingController(
            rootView: ConfigurationView(model: model)
        )
        PaddrFamilyWindowChrome.installConfigurationTitle(window.title, in: window)
        for _ in 0..<6 {
            window.contentView?.layoutSubtreeIfNeeded()
            await Task.yield()
        }

        let toolbar = try XCTUnwrap(window.toolbar)
        XCTAssertTrue(
            toolbar.items.contains { $0.itemIdentifier == .flexibleSpace },
            "The flexible spacer keeps Refresh at the trailing edge"
        )
        XCTAssertEqual(
            toolbar.items.filter { $0.itemIdentifier != .flexibleSpace }.count,
            1,
            "Trackpad Output belongs to the bottom status bar, leaving Refresh as the only action"
        )
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

    func testExpandedAutosavedFrameMigratesToCompactWithoutChangingUsableSizeOrTopEdge() {
        let autosaveName = "PaddrConfigurationWindow.v6.Tests.\(UUID().uuidString)"
        let expectedUsableSize = NSSize(width: 868, height: 680)
        defer { NSWindow.removeFrame(usingName: autosaveName) }

        let expandedWindow = makeWindow(hasToolbar: true, usesFullSizeContent: true)
        expandedWindow.toolbarStyle = .unified
        PaddrFamilyWindowChrome.apply(to: expandedWindow)
        PaddrFamilyWindowChrome.setUsableLayoutSize(expectedUsableSize, for: expandedWindow)
        expandedWindow.center()
        expandedWindow.contentView?.layoutSubtreeIfNeeded()
        let expectedTopLeft = NSPoint(
            x: expandedWindow.frame.minX,
            y: expandedWindow.frame.maxY
        )
        expandedWindow.saveFrame(usingName: autosaveName)

        let compactWindow = makeWindow(hasToolbar: true, usesFullSizeContent: true)
        PaddrFamilyWindowChrome.apply(to: compactWindow)

        XCTAssertTrue(
            PaddrFamilyWindowChrome.migrateAutosavedFrame(
                usingName: autosaveName,
                from: .unified,
                to: .unifiedCompact,
                for: compactWindow
            )
        )
        compactWindow.contentView?.layoutSubtreeIfNeeded()

        XCTAssertEqual(compactWindow.toolbarStyle, .unifiedCompact)
        assertSize(compactWindow.contentLayoutRect.size, equals: expectedUsableSize)
        XCTAssertEqual(compactWindow.frame.minX, expectedTopLeft.x, accuracy: 0.5)
        XCTAssertEqual(compactWindow.frame.maxY, expectedTopLeft.y, accuracy: 0.5)
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

    func testCardsAndInsetSectionsOwnTheSharedSurfaceMargin() throws {
        let width: CGFloat = 300
        let contentHeight: CGFloat = 44

        let cardView = SettingsControlEdgeProbe(identifier: "card-content")
            .frame(maxWidth: .infinity)
            .frame(height: contentHeight)
            .paddrCard()
            .frame(width: width)
        let cardHost = NSHostingView(rootView: cardView)
        cardHost.frame = NSRect(origin: .zero, size: cardHost.fittingSize)
        cardHost.layoutSubtreeIfNeeded()
        let cardContent = try XCTUnwrap(
            descendants(of: NSView.self, in: cardHost).first {
                $0.identifier?.rawValue == "card-content"
            }
        )
        let cardFrame = cardContent.convert(cardContent.bounds, to: cardHost)
        XCTAssertEqual(cardHost.bounds.width, width, accuracy: 0.5)
        XCTAssertEqual(
            cardHost.bounds.height,
            contentHeight + (2 * PaddrStyle.Inset.card),
            accuracy: 0.5
        )
        XCTAssertEqual(cardFrame.minX, PaddrStyle.Inset.card, accuracy: 0.5)
        XCTAssertEqual(
            cardHost.bounds.maxX - cardFrame.maxX,
            PaddrStyle.Inset.card,
            accuracy: 0.5
        )
        XCTAssertEqual(cardFrame.minY, PaddrStyle.Inset.card, accuracy: 0.5)
        XCTAssertEqual(
            cardHost.bounds.maxY - cardFrame.maxY,
            PaddrStyle.Inset.card,
            accuracy: 0.5
        )

        let sectionView = PaddrSectionContainer {
            SettingsControlEdgeProbe(identifier: "section-content")
                .frame(maxWidth: .infinity)
                .frame(height: contentHeight)
        }
        .frame(width: width)
        let sectionHost = NSHostingView(rootView: sectionView)
        sectionHost.frame = NSRect(origin: .zero, size: sectionHost.fittingSize)
        sectionHost.layoutSubtreeIfNeeded()
        let sectionContent = try XCTUnwrap(
            descendants(of: NSView.self, in: sectionHost).first {
                $0.identifier?.rawValue == "section-content"
            }
        )
        let sectionFrame = sectionContent.convert(sectionContent.bounds, to: sectionHost)
        XCTAssertEqual(sectionHost.bounds.width, width, accuracy: 0.5)
        XCTAssertEqual(
            sectionHost.bounds.height,
            contentHeight + (2 * PaddrStyle.Inset.section),
            accuracy: 0.5
        )
        XCTAssertEqual(sectionFrame.minX, PaddrStyle.Inset.section, accuracy: 0.5)
        XCTAssertEqual(
            sectionHost.bounds.maxX - sectionFrame.maxX,
            PaddrStyle.Inset.section,
            accuracy: 0.5
        )
        XCTAssertEqual(sectionFrame.minY, PaddrStyle.Inset.section, accuracy: 0.5)
        XCTAssertEqual(
            sectionHost.bounds.maxY - sectionFrame.maxY,
            PaddrStyle.Inset.section,
            accuracy: 0.5
        )
    }

    func testSectionHeadingKeepsNaturalHeightOutsideTheControlRowFamily() {
        let hostingView = NSHostingView(rootView: PaddrSectionHeader("Pointer settings"))
        hostingView.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(hostingView.fittingSize.height, 0)
        XCTAssertLessThan(hostingView.fittingSize.height, PaddrStyle.Metrics.row)
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
            PaddrStyle.minimumPadColumnWidth
                - (2 * PaddrStyle.Inset.card)
                - (2 * PaddrStyle.Inset.section),
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

    func testPadCardHeaderOmitsVisibleBehaviorHeadingAndSelectedSummary() async throws {
        let hostingView = NSHostingView(
            rootView: PadConfigurationView(
                side: .right,
                configuration: .constant(PadConfiguration(mode: .mouse))
            )
            .frame(width: PaddrStyle.padColumnWidth)
        )
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: PaddrStyle.padColumnWidth, height: 640)
        )
        await settle(hostingView)

        let renderedText = descendants(of: NSTextField.self, in: hostingView).map(\.stringValue)
        let selector = try XCTUnwrap(
            descendants(of: NSSegmentedControl.self, in: hostingView).first {
                $0.identifier?.rawValue == PaddrAccessibility.identifier("pad-mode", "right")
            }
        )

        XCTAssertFalse(
            renderedText.contains("Behavior"),
            "Behavior remains the control's accessibility label, not a redundant visible heading"
        )
        XCTAssertFalse(
            renderedText.contains("Pointer"),
            "The Behavior selector already communicates the selected mode"
        )
        XCTAssertEqual(selector.accessibilityLabel(), "Behavior")
    }

    func testAdaptivePadHeaderMovesTheSameSelectorBelowTitleOnlyWhenNeeded() throws {
        let layout = PaddrAdaptiveHeaderLayout(
            spacing: PaddrStyle.Spacing.s2,
            layoutDirection: .leftToRight
        ) {
            SettingsControlEdgeProbe(identifier: "header-title")
                .frame(width: 120, height: 28)
            SettingsControlEdgeProbe(identifier: "header-selector")
                .frame(width: PaddrStyle.behaviorPickerWidth, height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let hostingView = NSHostingView(rootView: layout)
        let defaultCardContentWidth = PaddrStyle.padColumnWidth
            - (2 * PaddrStyle.Inset.card)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: defaultCardContentWidth, height: 120)
        )
        hostingView.layoutSubtreeIfNeeded()

        let inlineTitle = try XCTUnwrap(
            descendants(of: NSView.self, in: hostingView).first {
                $0.identifier?.rawValue == "header-title"
            }
        )
        let inlineSelector = try XCTUnwrap(
            descendants(of: NSView.self, in: hostingView).first {
                $0.identifier?.rawValue == "header-selector"
            }
        )
        let inlineTitleFrame = inlineTitle.convert(inlineTitle.bounds, to: hostingView)
        let inlineSelectorFrame = inlineSelector.convert(inlineSelector.bounds, to: hostingView)

        XCTAssertEqual(inlineTitleFrame.midY, inlineSelectorFrame.midY, accuracy: 0.5)
        XCTAssertEqual(inlineTitleFrame.minX, hostingView.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(inlineSelectorFrame.maxX, hostingView.bounds.maxX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            inlineSelectorFrame.minX - inlineTitleFrame.maxX,
            PaddrStyle.Spacing.s2,
            "The inline header should protect the declared title-to-control gap"
        )

        let constrainedWidth = PaddrStyle.minimumPadColumnWidth
            - (2 * PaddrStyle.Inset.card)
        hostingView.frame.size.width = constrainedWidth
        hostingView.layoutSubtreeIfNeeded()

        let stackedTitle = try XCTUnwrap(
            descendants(of: NSView.self, in: hostingView).first {
                $0.identifier?.rawValue == "header-title"
            }
        )
        let stackedSelector = try XCTUnwrap(
            descendants(of: NSView.self, in: hostingView).first {
                $0.identifier?.rawValue == "header-selector"
            }
        )
        let stackedTitleFrame = stackedTitle.convert(stackedTitle.bounds, to: hostingView)
        let stackedSelectorFrame = stackedSelector.convert(stackedSelector.bounds, to: hostingView)

        XCTAssertTrue(inlineTitle === stackedTitle)
        XCTAssertTrue(inlineSelector === stackedSelector)
        XCTAssertGreaterThanOrEqual(
            abs(stackedSelectorFrame.midY - stackedTitleFrame.midY),
            ((stackedSelectorFrame.height + stackedTitleFrame.height) / 2)
                + PaddrStyle.Spacing.s2 - 0.5,
            "The constrained header should stack without overlapping title and selector"
        )
        XCTAssertEqual(stackedSelectorFrame.minX, stackedTitleFrame.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(stackedSelectorFrame.minX, hostingView.bounds.minX - 0.5)
        XCTAssertLessThanOrEqual(stackedSelectorFrame.maxX, hostingView.bounds.maxX + 0.5)

        let rightToLeftLayout = PaddrAdaptiveHeaderLayout(
            spacing: PaddrStyle.Spacing.s2,
            layoutDirection: .rightToLeft
        ) {
            SettingsControlEdgeProbe(identifier: "rtl-header-title")
                .frame(width: 120, height: 28)
            SettingsControlEdgeProbe(identifier: "rtl-header-selector")
                .frame(width: PaddrStyle.behaviorPickerWidth, height: 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        let rightToLeftHost = NSHostingView(rootView: rightToLeftLayout)
        rightToLeftHost.frame = NSRect(
            origin: .zero,
            size: NSSize(width: defaultCardContentWidth, height: 120)
        )
        rightToLeftHost.layoutSubtreeIfNeeded()

        let rightToLeftTitle = try XCTUnwrap(
            descendants(of: NSView.self, in: rightToLeftHost).first {
                $0.identifier?.rawValue == "rtl-header-title"
            }
        )
        let rightToLeftSelector = try XCTUnwrap(
            descendants(of: NSView.self, in: rightToLeftHost).first {
                $0.identifier?.rawValue == "rtl-header-selector"
            }
        )
        let rightToLeftTitleFrame = rightToLeftTitle.convert(
            rightToLeftTitle.bounds,
            to: rightToLeftHost
        )
        let rightToLeftSelectorFrame = rightToLeftSelector.convert(
            rightToLeftSelector.bounds,
            to: rightToLeftHost
        )

        XCTAssertEqual(rightToLeftTitleFrame.midY, rightToLeftSelectorFrame.midY, accuracy: 0.5)
        XCTAssertEqual(rightToLeftTitleFrame.maxX, rightToLeftHost.bounds.maxX, accuracy: 0.5)
        XCTAssertEqual(rightToLeftSelectorFrame.minX, rightToLeftHost.bounds.minX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(
            rightToLeftTitleFrame.minX - rightToLeftSelectorFrame.maxX,
            PaddrStyle.Spacing.s2,
            "The RTL inline header should protect the declared title-to-control gap"
        )
        XCTAssertGreaterThanOrEqual(
            rightToLeftSelectorFrame.minX,
            rightToLeftHost.bounds.minX - 0.5
        )
        XCTAssertLessThanOrEqual(
            rightToLeftTitleFrame.maxX,
            rightToLeftHost.bounds.maxX + 0.5
        )
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

        let defaultSwitches = descendants(of: NSSwitch.self, in: defaultHostingView)
        XCTAssertEqual(defaultSwitches.count, 3)
        let defaultToggle = try XCTUnwrap(defaultSwitches.dropFirst().first)
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

        let legacySwitches = descendants(of: NSSwitch.self, in: legacyHostingView)
        XCTAssertEqual(legacySwitches.count, 3)
        let legacyToggle = try XCTUnwrap(legacySwitches.dropFirst().first)
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

    func testPointerStabilityControlsExposePerPadDefaultsAndBindings() async throws {
        var configuration = PadConfiguration(mode: .mouse)
        let view = PadConfigurationView(
            side: .right,
            configuration: Binding(
                get: { configuration },
                set: { configuration = $0 }
            )
        )
        .frame(width: PaddrStyle.padColumnWidth)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.padColumnWidth,
                height: PaddrStyle.Metrics.defaultWindowSize.height
            )
        )
        await settle(hostingView)

        let switches = descendants(of: NSSwitch.self, in: hostingView)
        XCTAssertEqual(switches.count, 3)
        let smoothing = try XCTUnwrap(switches.first)
        let stabilization = try XCTUnwrap(switches.last)

        XCTAssertEqual(smoothing.state, .off)
        XCTAssertEqual(stabilization.state, .on)

        smoothing.performClick(nil)
        stabilization.performClick(nil)
        await settle(hostingView)

        XCTAssertTrue(configuration.pointerSmoothingEnabled)
        XCTAssertFalse(configuration.tapStabilizationEnabled)
    }

    func testTapStabilizationUsesCompleteLocalizedToleranceForSliderAccessibilityValue() {
        let valueText = TapStabilizationPresentation.toleranceValue(
            points: 6,
            locale: Locale(identifier: "en")
        )
        XCTAssertEqual(valueText, "6 pt")
        XCTAssertEqual(
            ToggleValueSliderRow(
                title: "Tap stabilization",
                systemImage: "hand.tap",
                isEnabled: .constant(true),
                value: .constant(6),
                range: ConfigurationLimits.tapStabilizationThresholdPoints,
                step: 1,
                valueText: valueText,
                accessibilityIdentifier: "tap-stabilization-test"
            ).sliderAccessibilityValue,
            valueText
        )
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

    func testBottomStatusBarOwnsTrailingOutputToggleWithPreservedSemantics() async throws {
        let store = BlockingProfileStore()
        let model = PaddrMenuModel(dependencies: dependencies(store: store))
        defer { store.releaseSave() }
        let didInitialize = await waitUntil { model.isInitialized }
        XCTAssertTrue(didInitialize)

        let applyBar = ApplyBarView(model: model)
        let hostingView = NSHostingView(rootView: applyBar)
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(
                width: PaddrStyle.Metrics.defaultWindowSize.width,
                height: PaddrStyle.Metrics.commandBar
            )
        )
        await settle(hostingView)

        let switches = descendants(of: NSSwitch.self, in: hostingView)
        let outputToggle = try XCTUnwrap(switches.first)
        XCTAssertEqual(switches.count, 1)
        XCTAssertEqual(
            applyBar.outputToggleAccessibilityIdentifier,
            PaddrAccessibility.identifier("toolbar", "output")
        )
        XCTAssertEqual(
            String(localized: applyBar.outputToggleAccessibilityLabel),
            "Trackpad output"
        )
        XCTAssertEqual(String(localized: applyBar.outputToggleAccessibilityValue), "Off")
        XCTAssertEqual(
            String(localized: applyBar.outputToggleHelp),
            "Enable or disable mapped trackpad output"
        )
        XCTAssertEqual(outputToggle.accessibilityRoleDescription(), "switch")
        XCTAssertEqual(accessibilityIntegerValue(of: outputToggle), 0)
        XCTAssertEqual(outputToggle.isEnabled, model.canToggleOutput)
        XCTAssertEqual(
            outputToggle.convert(outputToggle.bounds, to: hostingView).maxX,
            hostingView.bounds.maxX - PaddrStyle.Metrics.outerSpacing,
            accuracy: 1
        )

        outputToggle.performClick(nil)
        await settle(hostingView)

        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(accessibilityIntegerValue(of: outputToggle), 1)
        XCTAssertEqual(
            String(localized: ApplyBarView(model: model).outputToggleAccessibilityValue),
            "On"
        )
        XCTAssertEqual(hostingView.fittingSize.height, PaddrStyle.Metrics.commandBar, accuracy: 0.5)
    }

    func testResolvedStatusCompactsButRetainsAccessibleIdentityAndValue() {
        let compactCell = StatusCell(
            title: "Access",
            value: LocalizedStringResource("Ready"),
            systemImage: "checkmark.shield.fill",
            state: .ready,
            isCompact: true,
            identifier: "access"
        )
        let compact = NSHostingView(rootView: compactCell)
        compact.frame = NSRect(origin: .zero, size: compact.fittingSize)
        compact.layoutSubtreeIfNeeded()

        let detailed = NSHostingView(
            rootView: StatusCell(
                title: "Access",
                value: LocalizedStringResource("Needed"),
                systemImage: "exclamationmark.shield",
                state: .problem,
                identifier: "access-detailed"
            )
        )
        detailed.frame = NSRect(origin: .zero, size: detailed.fittingSize)
        detailed.layoutSubtreeIfNeeded()

        XCTAssertEqual(compact.fittingSize.height, PaddrStyle.Metrics.statusPill, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(compact.fittingSize.width, PaddrStyle.Metrics.statusPill)
        XCTAssertLessThan(compact.fittingSize.width, detailed.fittingSize.width)

        XCTAssertEqual(compactCell.accessibilityLabelText, "Access")
        XCTAssertEqual(compactCell.accessibilityValueText, "Ready")
    }

    func testBatteryStatusNeverCompactsItsPercentage() {
        let compactSuccess = NSHostingView(
            rootView: StatusCell(
                title: "Controller",
                value: LocalizedStringResource("Connected"),
                systemImage: "gamecontroller.fill",
                state: .ready,
                isCompact: true
            )
        )
        let battery = NSHostingView(
            rootView: StatusCell(
                title: "Battery",
                value: String("60%"),
                systemImage: "battery.50percent",
                state: .ready,
                accessibilityValue: "Level 60%, Discharging"
            )
        )

        XCTAssertGreaterThan(battery.fittingSize.width, compactSuccess.fittingSize.width)
        XCTAssertEqual(battery.fittingSize.height, PaddrStyle.Metrics.statusPill, accuracy: 0.5)
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
            (2 * PaddrStyle.Metrics.statusPill) + PaddrStyle.Spacing.s2,
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
        window.toolbarStyle = .unifiedCompact
        window.collectionBehavior.insert(.fullScreenNone)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        if hasToolbar {
            window.contentViewController = NSHostingController(rootView: WindowToolbarProbe())
            PaddrFamilyWindowChrome.installConfigurationTitle(window.title, in: window)
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
