# Paddr current-state repository audit

Date: 2026-08-11
Scope: `codex/ui-refinement` at `edff4fb0cb790d14537d3717c437b34ff438b832`, plus the four uncommitted UI files present at audit start
Audit type: report-only runtime, concurrency, SwiftUI/accessibility/localization, test, release-packaging, documentation, and repository-readiness audit
Readiness assessment: no critical or high-severity finding was found. Do not publish the next release until PCA-001 and PCA-002 are fixed and the outstanding physical removal/reconnect acceptance has passed. PCA-003 should also be closed before presenting the configuration UI as accessibility-ready.

## Findings

### PCA-001 — Medium — A newer lifecycle operation can suppress the deferred termination reply

Domain: Application lifecycle / Swift concurrency
Confidence: Confirmed by source and a deterministic isolated XCTest probe

Evidence:

- `stopForTermination` stores AppKit's completion, advances `lifecycleEpoch`, and starts an asynchronous session stop: `Sources/PaddrAppSupport/PaddrMenuModel.swift:118-129`.
- After that suspension, it calls `finishTerminationIfNeeded()` only if its epoch is still current: `Sources/PaddrAppSupport/PaddrMenuModel.swift:130-131`.
- Enable, disable, Save & Apply, and related transitions advance the same epoch and cancel or replace `lifecycleTask`: `Sources/PaddrAppSupport/PaddrMenuModel.swift:136-157`.
- An isolated gated-session test began termination, advanced the lifecycle through a toggle while `session.stop()` was suspended, and then released both stops. The termination completion was never called. The probe was removed before final validation.
- Finished lifecycle task handles are not cleared. Because `stopForTermination` includes `lifecycleTask != nil` in its asynchronous-termination guard, an app that is otherwise idle can continue taking the `.terminateLater` path after an earlier operation has completed: `Sources/PaddrAppSupport/PaddrMenuModel.swift:119`.

Impact:

AppKit can be left waiting indefinitely for `reply(toApplicationShouldTerminate:)`. The app may appear unable to quit, and a force quit risks bypassing orderly output release. This is specifically a conflict between operation supersession and an obligation that must complete exactly once.

Fix direction:

- Give termination a one-shot, non-supersedable completion path. Once termination begins, either reject subsequent lifecycle transitions or let them cancel ordinary work without invalidating the termination reply.
- Use a `defer` or equivalent completion guard so every teardown outcome replies exactly once, including cancellation and errors.
- Clear completed lifecycle task records so idle termination can return synchronously when no teardown is required.
- Add deterministic tests for termination during enable, disable, reconnect, Save & Apply, cancellation, and an already-idle state.

Acceptance criteria:

- Every accepted deferred termination request replies exactly once.
- No newer operation can suppress or duplicate the reply.
- Output teardown completes before the reply, and an idle app does not perform unnecessary asynchronous work.

### PCA-002 — Medium — An explicitly requested missing configuration file silently enables defaults

Domain: CLI correctness / configuration safety
Confidence: Confirmed by source and executable probe

Evidence:

- `ConfigurationStore.load(from:)` chooses either the supplied URL or the default candidate, then returns `.default` whenever that file does not exist: `Sources/TrackIsBackCore/ConfigurationStore.swift:9-15`.
- The CLI passes the value of `--config` directly to that API and cannot distinguish an absent explicit file from an absent implicit default file: `Sources/TrackIsBackCLI/main.swift:89-91`.
- Running `PaddrCLI --config <nonexistent-path> --show-config` exited successfully and printed the default configuration.

Impact:

An operator can mistype or move a configuration path and still receive a successful launch using unintended mappings. For a tool that emits keyboard and mouse input, silent fallback is less safe than a clear configuration error.

Fix direction:

- Return defaults only when no explicit URL was supplied and the conventional default file is absent.
- Throw a typed configuration error when an explicitly supplied path is missing, unreadable, or not a regular file.
- Keep the app's first-run default behavior unchanged.
- Add configuration-store and CLI tests for implicit absence, explicit absence, unreadable input, malformed input, and a valid explicit file.

Acceptance criteria:

- A missing explicit `--config` path exits nonzero with a clear diagnostic and emits no controller output.
- An absent implicit default path still loads first-run defaults.

### PCA-003 — Medium — The content-height cap can place window chrome and the command bar outside the usable display

Domain: SwiftUI/AppKit layout / accessibility
Confidence: Confirmed by source and AppKit geometry probe

Evidence:

- `WindowContentFitter` caps the requested **content** height to `NSScreen.visibleFrame.height`: `Sources/TrackIsBackMenu/WindowContentFitter.swift:23-29`.
- It then converts that content rectangle to a larger window frame and applies the resulting frame without constraining it back to `visibleFrame`: `Sources/TrackIsBackMenu/WindowContentFitter.swift:31-48`.
- On the audit system, a 1,570-point visible frame permitted 1,570 points of content, which produced a 1,602-point frame: 32 points beyond the usable display.
- The pinned command bar sits at the bottom of the configuration UI, so this overflow can hide the primary Save & Apply action when content grows under large accessibility text, a reduced-height display, or tall mode combinations.

Impact:

The application can violate the intended content-fitting behavior precisely in the constrained and accessibility configurations where the fitting logic matters most. Users may need to move or resize the window before reaching the primary action.

Fix direction:

- Derive the maximum content height by converting the screen's visible frame through the actual window's frame/content geometry, or subtract the measured titlebar and toolbar chrome.
- Constrain both final frame size and origin to the current screen's `visibleFrame`.
- Extract the geometry calculation into a deterministic helper and cover representative titlebar, toolbar, small-screen, screen-change, and accessibility-height cases.

Acceptance criteria:

- The complete window frame remains inside the current display's visible frame.
- The bottom command bar remains reachable without manual resizing at supported text sizes and display heights.
- The existing first-open no-jump behavior remains intact.

### PCA-004 — Low — README screenshots show a superseded configuration interface

Domain: Documentation / release presentation
Confidence: Confirmed by comparison with the rebuilt live app

Evidence:

- The README embeds `docs/images/paddr-overview.png` and `docs/images/paddr-zones.png`: `README.md:8,17`.
- Those checked-in images show the earlier pill-status presentation, separate Area layout row, L/R header icons, older access treatment, and earlier trackpad-card hierarchy.
- A screenshot-free accessibility-tree inspection of the rebuilt current app confirmed the newer three-cell status layout, Permissions section, aligned two-column cards, Zone settings header picker, and native Selected area picker.

Impact:

The repository's primary product page no longer represents the interface users receive. This weakens setup guidance and visual confidence but does not affect runtime behavior.

Fix direction:

- After explicit visual approval, capture replacement overview and zone-editor images from the signed current app.
- Verify visible privacy state, controller identifiers, and local paths are safe before committing images.
- Keep the current README image paths if possible to avoid unnecessary documentation churn.

Acceptance criteria:

- README images match the approved current UI and do not expose private machine or controller data.

### PCA-005 — Low — Two unreferenced legacy PuckPads icon sources remain tracked

Domain: Repository hygiene / branding
Confidence: Confirmed

Evidence:

- `Assets/PuckPadsIcon.png` and `Assets/Assets.xcassets/AppIcon.appiconset/PuckPadsIcon.png` are tracked, have different SHA-256 digests, and retain the superseded PuckPads name.
- Neither file appears in `AppIcon.appiconset/Contents.json`; the catalog references only the ten generated `icon_*` renditions.
- The build script compiles the asset catalog as `AppIcon`, and the packaged bundle whitelist contains only the compiled icon resources. No source or script reference to either legacy PNG was found.

Impact:

There is no shipped-bundle impact, but two competing, unused icon sources make future icon regeneration and brand maintenance ambiguous.

Fix direction:

- Identify or create one canonical Paddr source artwork file, name it accordingly, and document how the app-icon renditions are generated.
- Remove the two obsolete unreferenced files after confirming the canonical source is preserved.

Acceptance criteria:

- One clearly named source of truth produces the catalog renditions, and no tracked icon retains obsolete product naming without historical purpose.

## Prior finding closure check

- **PRA-001 remains closed.** `CGEventOutput` tracks held mouse buttons and emits the corresponding dragged event while Paddr owns a hold.
- **PRA-002 remains closed.** Permission completion reconciles the menu model's typed operational status instead of reporting a save or retaining a request message.
- **PRA-003 remains closed.** The release verifier extracts and fully validates the archived app, rejects a substituted executable, and compares archive contents with the staged bundle.
- **PRA-004 remains closed.** Output dispatch uses synchronized state and no `@unchecked Sendable` declaration remains.
- **PRA-005 remains closed.** The zone preview uses independent normalized x/y radii and matches runtime hit testing.
- **PRA-006 remains closed.** Known key and mouse bindings use catalog-backed presentation labels consistently.
- **PRA-007 remains closed.** Lifecycle tests use deterministic continuation/stream signals rather than bounded scheduler polling.
- The earlier PPA and PFA session, removal, arbiter, validation, selection, persistence, localization, and packaging findings remain closed in source and automated tests. PCA-001 is a newly isolated app-termination obligation and does not reopen the actor-owned worker-serialization fix.

## Scope, authority, and method

- `README.md`, `CONTRIBUTING.md`, `Package.swift`, release scripts, three prior audits, repository policy files, the current source, and the live draft PR were treated as authority. No repository-local `AGENTS.md` was present.
- The user worktree was preserved. A fresh local clone of `edff4fb0cb790d14537d3717c437b34ff438b832` was overlaid with the exact four tracked UI diffs and used as the audit bench.
- Audited inventory: 35 production Swift files (4,083 lines), 10 XCTest files (1,292 lines), 3 products, 6 targets, one English String Catalog, release scripts, documentation, and app assets.
- No third-party package dependency, SwiftData model, C/Objective-C source, Xcode project/workspace, configured linter, or hosted CI workflow is present.
- Specialist lenses applied: Swift concurrency, SwiftUI/accessibility/localization, XCTest/concurrency testing, release artifact verification, repository policy, and live AppKit accessibility structure.
- GitHub was inspected read-only. The public repository's draft PR #1 targets `main`; its prior executable-bit review thread is resolved at the audited commit. `main` requires one approving review, code-owner review, and resolved conversations. No open issue was present.

## Validation performed

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -Xswiftc -warnings-as-errors`
  - Passed 64 tests: 39 core and 25 app-support, 0 failures.
- `scripts/check-localization.sh`
  - Passed Xcode 27 extraction coverage and String Catalog compilation.
- `swift build -c release -Xswiftc -warnings-as-errors --arch arm64`
  - Passed under Xcode-beta.
- Ad-hoc release packaging in a fresh temporary destination
  - Passed exact version/build, arm64 architecture, plist/resources, strict signature, bundle/archive whitelist, smoke launch, clean ZIP, tamper/non-executable rejection, and portable checksum verification.
- Installed Developer ID release packaging in a separate fresh destination
  - Passed with `Developer ID Application: Zachary Skjaveland (9T97GZT4MV)`, hardened runtime, Team ID `9T97GZT4MV`, macOS 26 runtime metadata, strict signature verification, clean archive, and checksum verification.
- `sh -n scripts/*.sh`, `plutil -lint Packaging/Info.plist`, `jq empty Resources/Localizable.xcstrings`, scoped secret/private-key scan, and `git diff --check`
  - Passed.
- Screenshot-free live inspection of the rebuilt app
  - Confirmed the current two-column structure, native Area layout and Selected area pop-ups, accessible control identifiers, and hidden duplicate Canvas semantics.
- Isolated deterministic termination test, explicit missing-config executable probe, and AppKit window-geometry probe
  - Confirmed PCA-001, PCA-002, and PCA-003. Temporary probe code was removed before final source comparison.

## Overturned or bounded suspicions

- The four current UI edits compile, pass the suite and localization gates, and expose the Area layout picker in the Zone settings header as intended.
- Touch tap uses the shared trailing-control alignment, and the new first-layout handling avoids the previously observed zero-height first-open resize.
- `Task.detached` remains confined to the blocking IOKit run-loop bridge; no second detached runtime path or unchecked sendability promise was found.
- Hiding the Canvas from accessibility remains correct because the adjacent native Selected area picker provides equivalent selection semantics and spatial keyboard navigation remains in the app-support policy.
- Arm64-only packaging matches the current macOS 27 product scope. No x86_64/universal requirement remains in active build or release instructions.
- The current packaging flow produced valid ad-hoc and Developer ID artifacts. No Apple Developer portal change was needed to sign locally with the installed certificate.
- No credential, private key, unredacted controller identifier, sensitive IOHID path, or generated build cache is tracked.

## Skipped checks and residual risk

- No source fix, commit, push, PR update, issue, release, upload, notarization, stapling, or other GitHub mutation was performed.
- No new screenshot was captured and no README image was changed.
- No physical puck unplug/replug test was performed. Releasing a held keyboard key, left mouse button, and right mouse button exactly once, retaining the enabled toggle, and reconnecting output remains the outstanding hardware acceptance.
- The live accessibility-tree pass does not replace human VoiceOver listening or complete Full Keyboard Access, large accessibility text, Increase Contrast, Reduce Transparency, and light/dark appearance acceptance.
- Developer ID signing succeeded locally, but notarization was intentionally not attempted. Distribution outside the local trust context still requires configured notarization credentials, submission, acceptance, stapling, and Gatekeeper verification.
- The app was smoke-launched, but no native game was used for end-to-end mapping acceptance.

## Target state

Paddr should have a termination path whose completion cannot be invalidated by ordinary operation generations, strict explicit configuration loading, a frame-aware content fitter that keeps the command bar on-screen, approved current documentation images, and one canonical Paddr icon source. Release evidence should then include physical disconnect/reconnect, human accessibility/appearance checks, Developer ID signing, notarization, stapling, and Gatekeeper validation.

## Phased remediation roadmap

### Phase 0 — Correctness blockers

1. Resolve PCA-001 with one-shot termination coordination and deterministic lifecycle tests.
2. Resolve PCA-002 by distinguishing explicit and implicit configuration absence and adding CLI/store tests.
3. Re-run the 64-test suite, localization checks, warnings-as-errors release build, and both packaging paths.

### Phase 1 — Window and accessibility resilience

1. Resolve PCA-003 with frame-aware sizing and pure geometry tests.
2. Perform the reduced-height, large-text, keyboard, VoiceOver, Increase Contrast, Reduce Transparency, and light/dark live pass.

### Phase 2 — Approved presentation cleanup

1. Resolve PCA-005 by establishing the canonical Paddr icon source.
2. Once the interface is explicitly approved, resolve PCA-004 with privacy-reviewed current screenshots.

### Phase 3 — Release acceptance

1. Complete the physical unplug/replug test while each keyboard and mouse output is held.
2. Build and verify the final Developer ID artifact from a clean snapshot.
3. Only with explicit operator approval, notarize, staple, run Gatekeeper verification, update the draft PR, and publish a release.

## Remediation evidence — 2026-08-11

The original audit above is preserved as the historical record. PCA-001 through PCA-005 are resolved in the current uncommitted worktree.

### PCA-001 — Resolved

- `PaddrMenuModel` now owns a dedicated one-shot termination state and task, separate from ordinary lifecycle epochs.
- Beginning termination invalidates and cancels enable, disable, reconnect, permission-refresh, and Save & Apply work; new transitions are ignored after termination begins.
- The model awaits `session.stop()` and every captured lifecycle task before delivering all queued AppKit completions exactly once. Completed task handles are cleared, and an idle model terminates synchronously.
- Deterministic gated tests cover active streaming, enable, disable, reconnect, Save & Apply, repeated termination requests, cancellation/drain ordering, exactly-once replies, and idle cleanup.

### PCA-002 — Resolved

- `ConfigurationStore.load(from:)` now distinguishes implicit and explicit paths. A missing implicit default still returns defaults; a missing explicit path, directory, unreadable file, malformed JSON, or invalid configuration throws a typed configuration error.
- CLI help and README guidance now state that `--config PATH` must be an existing, readable regular JSON file.
- Boundary tests cover implicit absence, explicit absence, non-regular input, unreadable input, malformed input, and valid explicit input. `scripts/test-cli.sh` verifies that a missing explicit path exits 2, writes no effective configuration to stdout, and reports the path.

### PCA-003 — Resolved

- `WindowFrameGeometry` subtracts real window chrome from the display's visible frame and clamps both final frame size and origin while preserving the top edge when possible.
- `WindowContentFitter` measures the pinned command bar, suppresses first-resize animation, animates only later content changes, and observes `NSWindow.didChangeScreenNotification` so a moved window is re-fitted for its new display.
- Pure geometry tests cover chrome subtraction, fitting requests, top-edge preservation, small/oversized displays, origin clamping, and screen changes.
- The signed live app opened without the earlier height jump. Off, Pointer, Scroll, mixed Zones/Pointer, dual Zones, 3 × 3, and collapsed states retained a reachable command bar as their content height changed.

### PCA-004 — Resolved

- `docs/images/paddr-overview.png` is a cursor-free 1,120 × 565 capture of expanded Scroll and Pointer configuration.
- `docs/images/paddr-zones.png` is a cursor-free 1,120 × 694 capture of expanded 3 × 3 Zones and Pointer configuration.
- Both images came from the current Developer ID-signed build, preserve the existing README paths, and expose no controller identifier, configuration path, or other private machine data.

### PCA-005 — Resolved

- `Assets/PaddrIcon.png` is the single canonical 1,024-pixel blue source artwork.
- Both obsolete `PuckPadsIcon.png` files were removed, and all ten AppIcon catalog renditions were regenerated from the canonical source.
- `scripts/generate-app-icon.sh` performs deterministic staged generation with exact dimension checks; CONTRIBUTING documents the workflow.

### Visual polish completed with remediation

- Top-level cards use native regular glass with adaptive outlines, while inset settings surfaces use a quieter tinted fill and lighter stroke.
- Status and permission surfaces use restrained semantic tinting without adding another brand accent; Steam blue `#1A9FFF` remains the sole product accent.
- Mode and inspector divider lines were removed in favor of deliberate spacing. All configuration selectors now share a consistent trailing edge.
- Pad maps use a layered squircle surface, clearer segment boundaries, selected-region depth, compact action labels, a quieter neutral indicator, shaped keyboard focus, and unchanged runtime hit-testing/accessibility semantics.
- Screenshot-free live inspection covered dark and isolated light appearances plus the behavior/layout combinations above. A separate temporary preview forced Increase Contrast and Reduce Transparency, confirming opaque backgrounds and strengthened outlines without changing system settings. The accessibility tree exposed native labeled controls and kept the visual Canvas hidden from assistive technologies.

### Final automated and packaging validation

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -Xswiftc -warnings-as-errors`: 81 tests passed (45 core, 36 app-support), 0 failures.
- Xcode 27 String Catalog extraction coverage and compilation passed.
- Arm64 release builds for `Paddr` and `PaddrCLI` passed with warnings as errors.
- Shell syntax, plist, catalog JSON, icon generation/dimensions, CLI missing-path regression, and `git diff --check` passed.
- Fresh ad-hoc and Developer ID packages passed exact `0.6.1` / build `10` metadata, arm64 architecture, bundle/archive whitelists, smoke launch, strict signing, clean ZIP, portable SHA-256 verification, tamper rejection, and non-executable rejection.
- Developer ID validation confirmed hardened runtime, Team ID `9T97GZT4MV`, and runtime version 26.0. Gatekeeper correctly continued to reject the artifact as unnotarized because notarization was outside this work's authority.

### Remaining release acceptance outside these findings

- The physical puck unplug/replug test while holding a keyboard key, left mouse button, and right mouse button was not performed. Hardware release/reconnect behavior remains explicitly unclaimed.
- Notarization, stapling, publication, PR updates, commits, pushes, and release uploads were not performed.
