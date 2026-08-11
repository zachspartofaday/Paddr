# Paddr follow-up repository audit

Date: 2026-08-11
Scope: current local `codex/ui-refinement` checkout at `be53561c53089ed2119c2ef157d09a194c7e7c9e` plus its complete uncommitted Paddr working state
Audit type: report-only engineering, UI/accessibility, test, packaging, and documentation follow-up
Readiness assessment: materially safer than the first audit, but not ready to publish as the first Paddr release until the lifecycle overlap and configuration/editor correctness findings are fixed

## Findings

### PFA-001 — High — Actor reentrancy can still launch overlapping output workers

Domain: Swift concurrency / controller lifecycle
Status: Confirmed by deterministic isolated audit probe
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed

Evidence:

- `TrackpadSession.start` begins by awaiting `stop()`, then creates and stores a replacement worker after that suspension: `Sources/TrackIsBackCore/TrackpadRuntime.swift:152-169`.
- `stop()` clears `worker` and `stopToken` before awaiting the captured worker's completion: `Sources/TrackIsBackCore/TrackpadRuntime.swift:212-220`.
- While that await is suspended, the actor is reentrant. A second `start()` can observe `worker == nil`, finish its own `stop()`, and launch a worker. When the first caller resumes, it launches another worker and overwrites the second worker/token in actor state.
- The app can create overlapping lifecycle calls by canceling one unstructured lifecycle task and immediately creating another; cancellation does not stop an actor method that is already executing and `TrackpadSession.start` does not check caller cancellation: `Sources/PaddrAppSupport/PaddrMenuModel.swift:120-140,165-175`.
- An isolated gated test issued two replacement starts while the original worker was blocked in teardown. It deterministically observed `maximumConcurrent > 1`. The probe passed only because its assertion expected the overlap; it was removed from the audit snapshot after recording the result.
- Existing session coverage calls replacement starts sequentially, after each awaited `start()` returns, so it cannot expose actor reentrancy between concurrent callers: `Tests/TrackIsBackTests/SessionTests.swift:7-24`.

Impact:

Two workers can post CGEvents concurrently. The generation gate suppresses stale stream events, but it does not gate output inside the old runtime. A worker whose token was overwritten can also become unreachable through `TrackpadSession.stop()`. This reopens the core risk previously tracked under PPA-004: stale key-up or mouse-up output can cancel a binding held by the replacement session.

Fix direction:

- Make replacement one non-reentrant lifecycle transaction. A start request should retain and await the same teardown task, then verify that its request/generation is still current before launching.
- Keep every live worker and stop token reachable until teardown completes; never clear the only handles before an await that permits reentrancy.
- Propagate caller cancellation before launch and after teardown.
- Add deterministic concurrent `start/start`, `start/stop/start`, canceled-start, stale-output, and orphan-worker tests. Assert both `maximumConcurrent == 1` and that global stop leaves zero workers.

### PFA-002 — Medium — Some saved zone layouts open with an invalid selected area

Domain: Configuration UI correctness
Status: Confirmed from state/layout invariants
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed

Evidence:

- Every new `ButtonZoneConfigurationView` initializes `selectedZone` to `.up`: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:4-7`.
- Horizontal layouts contain only `.left` and `.right`; four-corner layouts contain only corner cases: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:55-63`.
- Selection is normalized only when `zoneLayout` changes after the view exists: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:23-29`.
- The map highlights only zones present in the active layout, while the adjacent inspector continues to display and edit the invalid `.up` selection: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:33-50`, `Sources/TrackIsBackMenu/ZonePadMap.swift:16-29`.

Impact:

Opening a saved horizontal layout initially shows no selected region and an inspector labeled **Top**. Editing that inspector changes `dpadKeys.up`, which horizontal runtime hit testing never uses. A four-corner layout similarly labels the initial inspector **Top** instead of **Top left**, even though both currently alias the same stored binding. The visible editor can therefore write a mapping that does not control the area it appears to describe.

Fix direction:

- Initialize selection from `configuration.zoneLayout.zones.first` and enforce `layout.zones.contains(selectedZone)` whenever configuration is loaded, mode changes, or layout changes.
- Prefer a small selection model or binding invariant over relying only on `onChange`.
- Add a layout-matrix test proving every initial selection is visible, named correctly, and writes a binding used by that layout.

### PFA-003 — Medium — Turning output on applies unsaved edits without persisting them

Domain: App state / persistence semantics
Status: Confirmed by isolated model probe
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed behavior; intended policy inferred from the UI and README

Evidence:

- The model separately tracks editable `configuration` and `savedConfiguration`, and exposes an unsaved state when they differ: `Sources/PaddrAppSupport/PaddrMenuModel.swift:8-9,33`.
- Persistence happens only inside `saveAndApply()`: `Sources/PaddrAppSupport/PaddrMenuModel.swift:61-72`.
- Enabling output validates and passes the editable `configuration` directly to the session without saving it: `Sources/PaddrAppSupport/PaddrMenuModel.swift:135-170`.
- The pinned bar simultaneously labels the state **Unsaved changes** and presents **Save & Apply** as the operation that applies edits: `Sources/TrackIsBackMenu/ApplyBarView.swift:8-26`.
- README setup order says to configure, choose **Save & Apply**, and then turn output on: `README.md:23-27`.
- An isolated model probe changed sensitivity to `7`, toggled output on, and confirmed the session received `7` while the save dependency was never called and `hasUnsavedChanges` remained true. The probe was removed after recording the result.

Impact:

The active output can differ from both the persisted configuration and the UI's saved-state contract. Closing or relaunching Paddr silently returns to the older settings. A menu-bar toggle and a window toggle also have different practical context: the menu cannot show that it is starting an unsaved draft.

Fix direction:

- Choose and encode one explicit policy:
  - recommended: enabling uses `savedConfiguration` and requires **Save & Apply** for draft edits; or
  - atomically validate, save, and start when enabling with a draft.
- If live preview is intentional, name it explicitly and distinguish **running draft** from **saved** in status.
- Add model tests for enabling with unsaved valid edits, unsaved invalid edits, save failure, menu-bar enable, and relaunch persistence.

### PFA-004 — Medium — The interactive pad map is not keyboard-operable and lacks a useful AX role/label

Domain: Accessibility / SwiftUI interaction
Status: Confirmed by code inspection and screenshot-free accessibility-tree probe
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed

Evidence:

- Region selection is implemented only with a location-sensitive `SpatialTapGesture`: `Sources/TrackIsBackMenu/ZonePadMap.swift:43-50`.
- The map is focusable and supplies an accessibility adjustable action, but it has no keyboard handler or semantic control representation: `Sources/TrackIsBackMenu/ZonePadMap.swift:52-64`.
- In a live AX probe after switching the left pad to Zones, the map appeared as `AXUnknown`. It exposed `AXIncrement` and `AXDecrement` plus value description **Top**, but did not expose the source accessibility label **Button area map** as an AX title/description.
- After programmatically focusing that exact AX element, Left, Right, Up, and Down arrow key events left its value at **Top**.
- The adjacent action picker edits only the currently selected region, so a keyboard-only user cannot reach the other regions: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:42-50`.

Impact:

Mouse users can select every area, and VoiceOver may be able to invoke the increment/decrement actions, but ordinary keyboard navigation cannot choose a region. The unknown unlabeled role also gives assistive technology less context than the source intends. This does not satisfy the planned keyboard-only and VoiceOver acceptance for the zone editor.

Fix direction:

- Represent regions as real `Button` controls, or provide an `accessibilityRepresentation` using a labeled Picker/List whose selection is shared with the visual map.
- Add explicit keyboard commands for previous/next and spatial arrow navigation, with a visible focus treatment.
- Verify the map exposes a stable role, name, selected value, help, and actions in the AX tree.
- Add focused-state/selection model tests and complete a human VoiceOver and Full Keyboard Access pass.

### PFA-005 — Medium — The emitted SHA-256 file is tied to the builder's absolute path

Domain: Release packaging
Status: Confirmed by recipient-directory probe
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed

Evidence:

- The packaging script writes `shasum -a 256 "$zip_path"` directly to the digest file: `scripts/package-release.sh:65`.
- This records an absolute builder path, for example `…  /tmp/paddr-audit-package…/Paddr.zip`, rather than the archive basename.
- The script's verification reads only the first hash field and recalculates against the same original absolute path, so it does not test portability: `scripts/package-release.sh:66-68`.
- Copying `Paddr.zip` and `Paddr.zip.sha256` together into a clean recipient directory, hiding the original ZIP, and running `shasum -a 256 -c Paddr.zip.sha256` failed with status 1 because it looked for the builder's path.
- Version/build “verification” currently checks only that the plist values are nonempty; it cannot reject an unintended release version: `scripts/package-release.sh:16-19`.

Impact:

The checksum displayed in release notes can still be compared manually, but the shipped `.sha256` file is not self-contained and standard verification fails for recipients. A release operator can also accidentally package the wrong nonempty version/build without the script detecting it.

Fix direction:

- Generate the digest from inside `output_dir` so the file contains `Paddr.zip`, and verify it from a separate staged recipient directory.
- Accept required `EXPECTED_VERSION` and `EXPECTED_BUILD` values for release packaging and compare them exactly.
- Add a shell acceptance test that moves only the ZIP and digest to a clean directory before running `shasum -c`.

### PFA-006 — Low — The English String Catalog does not cover all known UI and accessibility text

Domain: Localization / accessibility copy
Status: Confirmed by catalog/source comparison
Remediation status: Resolved locally on 2026-08-11.
Confidence: Confirmed

Evidence:

- `Resources/Localizable.xcstrings` contains 65 source entries and compiles successfully, but known source keys are absent.
- Missing visible, help, or accessibility keys include **Request**, **Open Settings**, **Reads controller trackpad reports.**, **Sends mapped mouse and keyboard input.**, **Button area map**, **Neutral**, **Zone action**, **Action**, **Touch tap action**, **Trackpad output**, **On**, and **Refresh controller and permission status**.
- Representative source locations: `Sources/TrackIsBackMenu/PermissionTile.swift:25-36`, `Sources/TrackIsBackMenu/SystemAccessView.swift:22-35`, `Sources/TrackIsBackMenu/ZonePadMap.swift:31-64`, `Sources/TrackIsBackMenu/KeyPicker.swift:15-31`, `Sources/TrackIsBackMenu/TapActionPicker.swift:15-32`, `Sources/TrackIsBackMenu/AppHeaderView.swift:22-30`.
- Failure status carries a runtime `String` and constructs a localization resource from that dynamic message: `Sources/PaddrAppSupport/MenuStatus.swift:16,32`. Core configuration, permission, device, and output errors are consequently English runtime strings rather than typed localizable cases.

Impact:

English fallback still displays, so this is not a current English-language functional failure. However, the catalog cannot serve as a complete extraction authority, accessibility labels/help will be missed by future translations, and dynamic failures cannot reorder interpolated values such as side names or paths.

Fix direction:

- Add every known UI, help, and accessibility key to the catalog and add translator comments for ambiguous actions.
- Replace free-form known failures with typed localized cases and interpolate runtime values into localized resources; preserve truly unknown errors as a clearly nonlocalized diagnostic fallback.
- Add a catalog-coverage check for explicitly catalog-managed targets.

## Overturned or bounded suspicions

- **Touch-tap policy remains fixed.** `PadMode.allowsTouchTap` gates tracking and emission, and tests cover Off plus every Zones layout.
- **Shared output ownership remains fixed for one runtime.** `OutputArbiter` source-owns key and mouse bindings, protects held bindings from matching taps, and has focused overlap/release tests. PFA-001 is a lifecycle problem because each overlapping runtime owns a separate arbiter.
- **Simulated removal cleanup remains sound.** The HID callback state rejects reports after removal, clears its queue, emits typed `.deviceRemoved`, and runtime teardown releases held output. Physical unplug/replug remains unverified rather than overturned.
- **Numeric conversion safety remains fixed.** Shared limits reject adjacent invalid values and Core Graphics scroll conversion clamps finite values at `Int32` boundaries.
- **Bundle staging is clean.** Fresh staging, stale-file removal, exact content whitelist, universal architecture, resource compilation, strict signature verification, clean ZIP metadata, and smoke launch all passed. PFA-005 is limited to digest portability and release-version assertions.
- **Standalone-window lifecycle works.** The app launches a real configuration window and closing it leaves the menu-bar process alive. No screenshot was captured.
- **No sensitive repository material was found.** A scoped scan found no private keys, credentials, tokens, raw device serials, private IOHID paths, or private config paths.

## Scope, authority, and method

- No repository-local `AGENTS.md`, PRD, active issue, or open pull request exists. `README.md`, `CONTRIBUTING.md`, `Package.swift`, `.github/CODEOWNERS`, the prior audit, and the live checkout were treated as authority.
- Read-only GitHub checks found no open issues or pull requests. The public repository still has only the PuckPads 0.6.0 prerelease; Paddr publication remains a future sequencing action.
- The user worktree was not used as the audit execution bench. A fresh local clone of `be53561` was created under `/tmp` and overlaid with the exact current working state while excluding `.git`, `.build`, and `dist`.
- The current state has 55 visible worktree entries over the base commit: 24 modified/rename-like entries, 14 deleted entries, and 17 untracked entries.
- Inventory: 38 Swift files, 3,242 source lines, 775 test lines, three products, four production targets, and two XCTest targets. There are no third-party dependencies, SwiftData models, C/Objective-C sources, Xcode projects/workspaces, configured linters, or hosted workflows.
- Specialist lenses applied after inventory: SwiftUI/accessibility/localization, Swift concurrency/HID bridging, and XCTest quality. XCTest was reviewed in place; migration to Swift Testing was not requested. SwiftData, UIKit modernization, C bounds safety, and Xcode-project security settings were not applicable.
- Evidence means file/line inspection, reproducible command output, deterministic probes in the isolated clone, or screenshot-free AX state. Audit-only probes were deleted before canonical validation.

## Validation performed

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -Xswiftc -warnings-as-errors`
  - Passed: 34 core tests and 7 app-support tests, 0 failures.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release -Xswiftc -warnings-as-errors`
  - Passed for the complete package.
- `scripts/package-release.sh` in a fresh temporary output directory
  - Passed app build, universal `x86_64 arm64`, compiled catalog, strict ad-hoc signature, exact bundle whitelist, smoke launch, clean ZIP metadata, and local hash comparison.
- Concurrent-start audit probe
  - Confirmed actor-reentrant replacement can exceed one active worker.
- Unsaved-enable audit probe
  - Confirmed an unsaved sensitivity reaches the live session without invoking persistence.
- Recipient checksum probe
  - Failed as expected with status 1 after moving the ZIP and digest away from the builder path, confirming PFA-005.
- Screenshot-free AX probe
  - Confirmed the zone map is `AXUnknown`, exposes increment/decrement but not its intended label, and does not change selection under arrow-key input.
- `plutil -lint Packaging/Info.plist`, `jq empty Resources/Localizable.xcstrings`, `sh -n scripts/*.sh`, and `git diff --check`
  - Passed.
- Scoped sensitive-material scan
  - No matches.

## Skipped checks and residual risk

- No source fix, commit, push, issue, pull request, release, notarization, stapling, or GitHub mutation was performed.
- No README or audit screenshot was captured. Existing README images were not changed or judged as current visual evidence.
- No physical puck unplug/replug was performed. Held-key, left-click, and right-click release/reconnect remain mandatory hardware acceptance before publication.
- VoiceOver, Full Keyboard Access, large accessibility text, Increase Contrast, Reduce Transparency, light/dark appearance, and reduced-height behavior were not changed system-wide. The AX probe is evidence for PFA-004, not a substitute for the final human pass.
- Developer ID signing was not repeated in the isolated audit; the prior local validation remains historical evidence. This audit used ad-hoc signing only.
- No baseline-to-current regression delta is claimed; this audit validated only the exact current overlaid snapshot.
- The live user's invalid legacy configuration was not modified. Configuration migration and recovery remain covered only by unit tests and existing app behavior.

## Open questions and assumptions

- Assumption: **Save & Apply** is the only operation intended to make edited settings active. If unsaved live preview is intentional, PFA-003 should be dispositioned as a product-language/state-model redesign rather than rejected without replacement behavior.
- Question: should Paddr remain an accessory-only app with no Dock icon or standard main menu now that configuration is a standalone window? The current menu-bar-first lifecycle is preserved in this audit.
- Question: will the GitHub repository and image filenames remain PuckPads while the product is Paddr? This is release sequencing and repository identity work, not part of the current runtime remediation.
- Assumption: per-game/app profiles remain roadmap-only and should not complicate the fixes below.
- Assumption: macOS 26.0 stays the deployment target and Xcode 27 remains the release toolchain.

## Target shape

- One lifecycle owner guarantees at most one HID/output worker across concurrent, canceled, reconnecting, saving, and terminating requests.
- Draft, saved, and active configurations have an explicit product policy and cannot silently diverge.
- Every zone editor opens with a valid selected region, and every region is operable by pointer, keyboard, VoiceOver, and Voice Control.
- Permission controls and status surfaces adapt at large text and translated lengths without overflow.
- Every known UI/status/help/accessibility string is cataloged or intentionally marked diagnostic-only.
- Release ZIPs are universal, strictly signed, metadata-clean, version-asserted, and accompanied by a portable checksum file.

## Phased remediation roadmap

### Phase 0 — Lifecycle correctness blocker

One focused core/test PR:

1. Replace the reentrant start/stop sequence with a teardown/start transaction that revalidates request generation after every await.
2. Preserve handles for all workers until each one exits; make global stop prove zero active workers.
3. Add concurrent start/start, start/stop/start, cancellation, stale-output, reconnect, and termination tests without fixed-delay polling.

Acceptance: deterministic tests cannot produce `maximumConcurrent > 1`; canceled or superseded requests cannot post output; stop and termination leave no worker or held binding.

### Phase 1 — Configuration and zone-editor correctness

One app-support/UI PR after Phase 0:

1. Decide and implement the draft/saved/active configuration policy.
2. Initialize and continuously normalize zone selection against the active layout.
3. Add model and layout-matrix tests, including saved horizontal and four-corner configurations.

Acceptance: active settings always match the declared policy, and no inspector can edit an invisible or unused area.

### Phase 2 — Accessibility and localization closure

One UI/resources PR:

1. Give the zone editor a semantic control representation and full keyboard navigation.
2. Make permission actions adapt within each tile, then run the planned large-text and assistive-technology matrix.
3. Complete the String Catalog and type known user-facing failures.

Acceptance: the AX tree exposes a named role/value, every region is reachable without a pointer, all known keys are cataloged, and the human accessibility pass succeeds.

### Phase 3 — Release tooling and publication readiness

One packaging/docs PR:

1. Emit a basename-only SHA file and verify it from a clean recipient directory.
2. Require exact expected version/build values and retain existing universal/signature/content checks.
3. Update public-download and signing copy immediately before the first Paddr release, without replacing screenshots until visual approval.

Acceptance: ZIP plus digest verifies after being copied anywhere; the wrong version/build is rejected; documentation matches the actual published artifact.

## Summary

The first remediation substantially improved Paddr: tap policy, shared ownership, HID removal, numeric safety, dependency injection, adaptive presentation, and clean universal packaging all remain in place. This follow-up found one release-blocking concurrency flaw and four concrete medium-severity behavior/accessibility/packaging gaps that the ordinary green test suite does not catch. The recommended order is lifecycle serialization first, then configuration/editor correctness, then accessibility/localization, and finally checksum/release closure.

## Remediation closure — 2026-08-11

The findings and probes above remain as historical evidence. The current uncommitted working tree contains the remediation below; no commit, push, notarization, release publication, or screenshot capture was performed.

- **PFA-001 — Resolved.** `TrackpadSession` now owns an epoch-tagged worker record, retains each worker and stop token through teardown, and revalidates request identity and cancellation after suspension. Superseded starts return finished streams. Four deterministic gated tests cover concurrent start/start, start/stop/start, cancelled replacement, stale-event/output ordering, maximum concurrency of one, and final zero-worker teardown.
- **PFA-002 — Resolved.** Valid zones are centralized on `PadZoneLayout`; the editor initializes from the active layout and continuously normalizes selection. The layout matrix covers every initial selection, transition/navigation behavior, and binding write. A live screenshot-free AX pass confirmed Left/right opens on **Left** and Four corners opens on **Top left**.
- **PFA-003 — Resolved with the selected Save-then-start policy.** Enabling validates and persists a changed draft before checking controller availability or starting output. Every start and reconnect uses `savedConfiguration`; validation/save failures preserve the draft, start no session, and turn output off with typed status. Model tests cover valid enable, invalid draft, save failure, disconnected save, reconnect snapshot consistency, relaunch persistence, Save & Apply failure, and termination.
- **PFA-004 — Resolved.** The Canvas remains a pointer and spatial-arrow surface with visible focus, while its duplicate accessibility semantics are hidden. A native **Selected area** pop-up is the semantic equivalent. Live AX inspection reported `AXPopUpButton`, description **Selected area**, stable identifier `selected-area-picker`, contextual help, and current value; keyboard type-selection changed Left to Right. A human VoiceOver listening pass remains a release checklist item, not an open code finding.
- **PFA-005 — Resolved.** Release packaging now requires exact `EXPECTED_VERSION` and `EXPECTED_BUILD`, emits `Paddr.zip` in the digest rather than a builder path, and uses one read-only verifier for the app, ZIP, and checksum. The shell regression test rejects wrong metadata and verifies copied ZIP/digest files from a clean recipient directory.
- **PFA-006 — Resolved.** Known failures are typed `MenuFailure` values with localized user-facing resources and retained diagnostic data. The English catalog now contains 88 entries, including UI, help, menu, status, and accessibility copy. `scripts/check-localization.sh` extracts strings from all managed targets, rejects missing catalog keys, and compiles the catalog.

### Final validation evidence

- Xcode 27 warnings-as-errors tests passed: 36 core tests and 18 app-support tests, 0 failures.
- The complete release build passed with warnings as errors.
- XcodeBuildMCP 2.6.2 independently built the `TrackIsBackMenu` release target successfully.
- Localization extraction coverage, catalog compilation, shell syntax, plist validation, JSON validation, and `git diff --check` passed.
- Fresh arm64-only ad-hoc and Developer ID packages passed exact metadata and architecture, strict signature, hardened runtime, bundle whitelist, smoke launch, clean ZIP, portable checksum, and wrong-version/build rejection. Developer ID identity: `Developer ID Application: Zachary Skjaveland (9T97GZT4MV)`.
- Screenshot-free live checks passed at the minimum 640-point width/reduced height, under ordinary launch, and under dark/Increase Contrast/Reduce Transparency launch arguments. The selected-area native control remained present and keyboard-operable.
- The local puck `0x28DE:0x1304` remains detectable. Physical unplug/replug while holding mapped keyboard and mouse outputs still requires a person to manipulate the hardware and is not claimed here.

### Architecture scope correction — 2026-08-11

- Paddr distribution is arm64-only. Intel Macs cannot run macOS 27, so an `x86_64` slice does not serve the currently supported controller path.
- macOS 26.0 remains the deployment target solely to preserve a possible Apple-silicon backport path.
- Build defaults, release packaging, artifact verification, and current documentation now enforce the exact arm64 architecture set. Earlier universal-package statements above are retained only as historical audit evidence.
