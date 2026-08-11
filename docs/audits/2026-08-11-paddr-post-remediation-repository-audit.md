# Paddr post-remediation repository audit

Date: 2026-08-11
Scope: current local `codex/ui-refinement` checkout at `be53561c53089ed2119c2ef157d09a194c7e7c9e` plus its complete uncommitted Paddr working state after the arm64-only packaging correction
Audit type: report-only runtime, concurrency, SwiftUI/accessibility/localization, test, release-packaging, and documentation audit
Readiness assessment: no critical or high-severity finding remains, but Paddr should not publish its next artifact until the release-verifier gap is closed and the outstanding physical output-release acceptance is completed

## Findings

### PRA-001 — Medium — Mapped mouse-button holds cannot produce drag events

Domain: Runtime output correctness
Confidence: Confirmed from source and Xcode 27 SDK behavior

Evidence:

- Zones can hold either mouse button until the pad leaves the zone or lifts: `Sources/TrackIsBackCore/PadMapper.swift:261-272`.
- Pointer output is always represented as `.mouseMove`: `Sources/TrackIsBackCore/PadMapper.swift:72-82`.
- `CGEventOutput` always converts that action to `.mouseMoved`, regardless of whether the output arbiter currently owns a left or right mouse-button hold: `Sources/TrackIsBackCore/CGEventOutput.swift:68-78`.
- The macOS 27 Core Graphics SDK defines `mouseMoved`, `leftMouseDragged`, and `rightMouseDragged` as distinct event types. A non-posting local probe created them as raw event types `5`, `6`, and `7`, respectively.
- Existing tests cover holding a mouse button and pointer movement independently, but no test combines a held zone mouse button on one pad with pointer movement on the other: `Tests/TrackIsBackTests/TrackIsBackTests.swift:95-130`.

Impact:

A configuration that uses one pad as a pointer and a zone on the other pad as a held left or right mouse button can click, but movement continues to be posted as ordinary mouse movement rather than a drag. Selection, camera drag, sliders, and other click-and-drag interactions can therefore fail even though both constituent mappings appear to work.

Fix direction:

- Make pointer dispatch aware of Paddr-owned held mouse-button state.
- Emit `.leftMouseDragged` or `.rightMouseDragged` while the corresponding button is held, with a defined policy if both are held.
- Add cross-pad tests for left drag, right drag, release, and movement after release.

### PRA-002 — Medium — Permission completion leaves stale or misleading action status

Domain: App state / permissions UX
Confidence: Confirmed by isolated model probe

Evidence:

- `requestInputMonitoring()` and `requestAccessibility()` map an immediately granted permission to `.configurationSaved`, even though no configuration save occurred: `Sources/PaddrAppSupport/PaddrMenuModel.swift:89-100`.
- Asynchronous permission completion is handled by `schedulePermissionRefresh()`, but its eventual `refreshStatus()` updates only permission/controller properties and never reconciles `MenuStatus`: `Sources/PaddrAppSupport/PaddrMenuModel.swift:55-60,255-263`.
- `.requestingInputMonitoring` and `.requestingAccessibility` remain action-message states: `Sources/PaddrAppSupport/MenuStatus.swift:78-86`.
- An isolated audit test requested Input Monitoring, changed the injected status to granted, and called `refreshStatus()`. `inputMonitoringStatus` became `.granted` while `status` remained `.requestingInputMonitoring`. A second probe confirmed that requesting an already-granted permission reports `.configurationSaved`. The temporary probe was removed before final validation.

Impact:

After permission approval, the compact access UI can correctly disappear while the header continues telling the user to complete a prompt. If access was already granted, the app can instead claim that configuration was saved. Both states undermine confidence in a permission flow that has already been sensitive to app identity and updates.

Fix direction:

- Add an explicit permission-ready or neutral operational status instead of reusing `.configurationSaved`.
- When refresh observes that the permission associated with a requesting/settings status is now granted, derive the appropriate current output status (`off`, waiting, connecting, or active).
- Add model tests for delayed grant, already-granted request, denied request, app reactivation, and one-permission-at-a-time completion.

### PRA-003 — Medium — The release verifier accepts an unrelated or tampered ZIP

Domain: Release integrity
Confidence: Confirmed by isolated artifact probe

Evidence:

- `verify-release.sh` validates metadata, architecture, resources, and signature only on the separately supplied `APP_PATH`: `scripts/verify-release.sh:16-51`.
- It checks the ZIP only for forbidden metadata and the presence of the path `Paddr.app/Contents/MacOS/Paddr`; it does not extract or verify the archived bundle: `scripts/verify-release.sh:53-58`.
- The digest proves only that the supplied checksum matches the supplied ZIP: `scripts/verify-release.sh:60-70`.
- An isolated probe created a ZIP containing only `Paddr.app/Contents/MacOS/Paddr`, using `/bin/echo` as the executable, generated a matching basename-only digest, and supplied a separate valid Paddr app as `APP_PATH`. The verifier printed `Verified Paddr 0.6.1 (10).` and exited successfully.

Impact:

The packaging pipeline currently creates its ZIP immediately from the verified staged app, so the normal in-process path produced a valid artifact in this audit. However, the shared verifier cannot establish that a ZIP received, copied, cached, or selected later contains that app. It can positively attest to an invalid release archive.

Fix direction:

- Extract the ZIP into a fresh validated temporary directory and run all plist, architecture, resource, content-whitelist, and strict-signature checks against the extracted `Paddr.app`.
- Either remove the separate app argument or compare a stable digest of the extracted bundle contents with the staged app.
- Add regression fixtures for a missing plist, substituted executable, extra bundle content, invalid signature, and valid ZIP paired with the wrong app.

This finding narrows the earlier PFA-005 closure: checksum portability and version assertions are fixed, but archive authenticity is not yet verified.

### PRA-004 — Low — `CGEventOutput` makes an unchecked cross-task safety promise without synchronization

Domain: Swift concurrency / output boundary
Confidence: Confirmed structure; current production impact is mitigated by single-worker ownership

Evidence:

- `TrackpadOutputDispatching` requires `Sendable`, and `CGEventOutput` satisfies it using `@unchecked Sendable`: `Sources/TrackIsBackCore/CGEventOutput.swift:19-25`.
- The class stores a non-`Sendable` `CGEventSource` and has no mutex, actor isolation, queue confinement type, or other synchronization around `dispatch`: `Sources/TrackIsBackCore/CGEventOutput.swift:23-43`.
- Removing `@unchecked Sendable` in an isolated compile probe produced the expected Swift 6 diagnostic that stored property `source` contains non-`Sendable` type `CGEventSource`. The change was reverted after the probe.
- The current runtime creates and consumes one output object inside one blocking worker, so no production call site was found dispatching through the same instance concurrently: `Sources/TrackIsBackCore/TrackpadRuntime.swift:89-95,107-124`.

Impact:

There is no confirmed race in the current single-worker path, but the public protocol promises that callers may transfer/share implementations across concurrency domains. A future profile, diagnostics, or multi-device path can rely on that promise and race the shared Core Graphics source.

Fix direction:

- Prefer removing `Sendable` from the synchronous dispatcher existential if it never crosses isolation, or wrap creation/use in an explicitly confined output executor.
- If cross-task use is required, protect the complete event-source dispatch operation with a synchronization primitive and document the invariant before retaining `@unchecked Sendable`.

### PRA-005 — Low — Radial and corner neutral previews do not match runtime hit testing

Domain: Zone editor visual correctness
Confidence: Confirmed geometry mismatch

Evidence:

- The map is rendered at a non-square `230 × 190` frame: `Sources/TrackIsBackMenu/ButtonZoneConfigurationView.swift:41-49`.
- Pointer hit testing normalizes x by width and y by height before delegating to runtime hit testing: `Sources/TrackIsBackMenu/ZonePadMap.swift:75-81`.
- Runtime radial/corner deadzones are circles in normalized controller coordinates: `Sources/TrackIsBackCore/PadMapper.swift:170-186`.
- The preview instead draws a screen-space circle using `min(width, height)` for both axes: `Sources/TrackIsBackMenu/ZonePadMap.swift:119-130`.
- At deadzone `0.5`, runtime hit testing displayed in a `230 × 190` map has x/y radii `57.5/47.5` points; the preview draws `47.5/47.5`. A horizontal strip can therefore appear active where clicking it selects no zone.

Impact:

The interactive map is not fully representative of the regions that emit output. The mismatch is most visible at larger inherited deadzones and can make edge selection appear broken.

Fix direction:

- Draw the normalized circle as an ellipse with independent width and height radii, or make the interactive pad viewport square.
- Share one testable normalized-geometry model between rendering and hit testing and add representative boundary tests.

### PRA-006 — Low — Runtime-generated key and mouse labels bypass localization and presentation naming

Domain: Localization / UI consistency
Confidence: Confirmed

Evidence:

- Picker labels render `KeyCatalog.commonNames` through `Text(key.capitalized)`: `Sources/TrackIsBackMenu/KeyPicker.swift:21-24` and `Sources/TrackIsBackMenu/TapActionPicker.swift:24-26`.
- The map similarly renders the raw stored binding with `.capitalized`: `Sources/TrackIsBackMenu/ZonePadMap.swift:25-29`.
- A `String` variable passed to `Text` is verbatim rather than a localizable key, so these known labels are invisible to String Catalog extraction.
- The 88-entry catalog has no entries for known labels such as `Command` or `Space`; the localization coverage script still passes because runtime strings cannot be extracted.
- Mouse bindings are presented as **Left click** and **Right click** in pickers but as raw **Mouse-Left** and **Mouse-Right** on the pad map.

Impact:

English remains usable, but the previous PFA-006 closure does not cover every known visible label. Future translations will leave key names in English, and the pad map currently uses less polished names than its adjacent inspector.

Fix direction:

- Introduce a catalog-backed presentation label for every known key and mouse binding while keeping custom `code:N` values verbatim.
- Reuse that label in both pickers and the map.
- Extend localization validation with an explicit known-binding catalog matrix because source extraction cannot discover runtime arrays.

### PRA-007 — Low — Async lifecycle tests still depend on bounded scheduler polling

Domain: Test determinism / coverage
Confidence: Confirmed structure; no flake reproduced in this audit

Evidence:

- Session tests wait for actor/runtime state by yielding up to 10,000 times and failing if the scheduler has not made the expected progress: `Tests/TrackIsBackTests/SessionTests.swift:127-140`.
- Model tests use the same bounded `Task.yield()` polling pattern: `Tests/PaddrAppSupportTests/MenuModelTests.swift:267-273`.
- The suite has deterministic injected worker/sleeper components, but the final observation channel is still iteration-count polling rather than an awaitable signal.
- Model coverage does not include delayed permission grant (PRA-002), active Save & Apply restart ordering, or rapid disable/enable supersession as explicit generation tests.
- All 54 tests passed in this audit; the concern is that the test process can outrun scheduled work under a different executor/load and that some accepted generation behavior remains unproved.

Impact:

The suite can produce a false timeout without a product regression, and it may remain green while stale app-level operations mutate newer state in paths not represented by the current tests.

Fix direction:

- Replace yield-count polling with awaitable latches/streams/continuations emitted by the injected dependency at the exact transition.
- Return or expose lifecycle completion handles where appropriate so tests can await behavior rather than poll state.
- Add generation-order tests for delayed permission completion, active Save & Apply restart, rapid disable/enable, reconnect supersession, and termination during each suspension point.

## Overturned or bounded suspicions

- **PFA-001 remains closed.** The actor retains its worker record through teardown and revalidates request epoch/cancellation after suspension. Four concurrent session tests passed, and no path to overlapping live workers was found.
- **PFA-002 and PFA-003 remain closed.** Zone selection normalizes to visible regions, and enable/reconnect starts use the saved snapshot under the selected Save-then-start policy.
- **Modifier-key output is not a finding.** A non-posting Core Graphics probe confirmed virtual key codes for Command, Shift, Option, and Control are created as `flagsChanged` events with modifier flags, matching the macOS 27 SDK contract.
- **Tap/output ownership remains sound for successful dispatch.** The arbiter prevents duplicate downs, retains cross-pad ownership, suppresses same-binding tap interruption, and releases globally and idempotently. Output-dispatch failure during cleanup remains a rare best-effort limitation rather than a separately confirmed defect.
- **Arm64-only packaging is correctly enforced.** The clean package contained exactly `arm64`; release scripts and README contain no current universal/x86_64 instruction. Historical universal references remain only inside earlier audit evidence.
- **The normal package path produced a clean artifact.** PRA-003 concerns independent verification of the ZIP, not the ZIP generated during this audit.
- **README screenshots remain explicitly deferred.** They were not captured, changed, or treated as current visual evidence, following operator direction.
- **No sensitive repository material was found.** A scoped scan found no private-key, common token, credential, or sensitive tracked-filename pattern.

## Scope, authority, and method

- No repository-local `AGENTS.md`, PRD, active issue, or open pull request exists. `README.md`, `CONTRIBUTING.md`, `Package.swift`, `.github/CODEOWNERS`, both earlier audits, and the live checkout were treated as authority.
- Read-only GitHub inspection confirmed `zachspartofaday/PuckPads` is public on `main`, with no open issues or pull requests at audit time.
- The user worktree was not used as the execution bench. A fresh local clone was created at `/tmp/paddr-audit-20260811.PGxvbX` from `be53561c`, then overlaid with the exact tracked and untracked working state while excluding ignored build products and Finder metadata.
- Exact audited inventory: 58 visible worktree entries over the base commit; 31 production Swift files (3,507 lines); 8 XCTest files (1,124 lines); `Package.swift`; 3 products; 6 targets; and an 88-entry English String Catalog.
- There are no third-party dependencies, SwiftData models, C/Objective-C sources, Xcode projects/workspaces, configured linters, or hosted workflows.
- Specialist lenses applied after inventory: `swift-concurrency-pro`, `swiftui-pro`, `swift-testing-pro`, and `xcodebuildmcp-cli`. XCTest was reviewed in place; migration was not requested. SwiftData, UIKit modernization, C bounds safety, and a separate Xcode security-settings audit were not applicable.
- Evidence means file/line inspection, Xcode 27 SDK declarations, reproducible commands, isolated probes, or artifact inspection. Temporary audit probes were removed before final source-state comparison.

## Validation performed

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -Xswiftc -warnings-as-errors`
  - Passed: 36 core tests and 18 app-support tests, 0 failures.
- `scripts/check-localization.sh` with the Xcode-beta toolchain
  - Passed extraction coverage and catalog compilation.
- XcodeBuildMCP 2.6.2, `TrackIsBackMenu`, release, arm64
  - Passed in the isolated snapshot.
- `scripts/package-release.sh` with `EXPECTED_VERSION=0.6.1`, `EXPECTED_BUILD=10`, ad-hoc signing, and temporary output/scratch directories
  - Passed build, exact arm64 architecture, plist/resources, strict signature, bundle whitelist, smoke launch, metadata-clean ZIP, portable digest, wrong-version/build rejection, and clean-recipient checksum.
- Tampered-archive probe
  - Confirmed PRA-003: a ZIP containing `/bin/echo` at the expected executable path was accepted when paired with a separate valid app and matching digest.
- Permission-state probe
  - Confirmed PRA-002: delayed grant retained `.requestingInputMonitoring`; already-granted request produced `.configurationSaved`.
- Non-posting Core Graphics probes
  - Confirmed distinct moved/dragged event types and overturned the modifier-key suspicion without emitting input.
- Zone-geometry calculation
  - Confirmed the runtime/preview deadzone radius mismatch at the shipped map dimensions.
- `sh -n scripts/*.sh`, `plutil -lint Packaging/Info.plist`, `jq empty Resources/Localizable.xcstrings`, CLI help smoke, scoped secret-pattern scan, and `git diff --check`
  - Passed.

## Skipped checks and residual risk

- No product fix, commit, push, issue, pull request, release, upload, notarization, stapling, or GitHub mutation was performed.
- No screenshot was captured and no README image was changed.
- No physical puck unplug/replug was performed. Release-on-removal while holding a keyboard key, left mouse button, and right mouse button remains the outstanding PPA-002 hardware acceptance.
- No human VoiceOver listening or system-wide Full Keyboard Access, large accessibility text, Increase Contrast, Reduce Transparency, or light/dark visual pass was performed. Prior screenshot-free AX evidence remains historical, not a substitute for human acceptance.
- Developer ID signing was not repeated in this audit. The immediately preceding arm64-only validation remains historical evidence; this isolated audit used ad-hoc signing.
- No live game was used to test pointer-plus-zone dragging, so PRA-001 is confirmed from the emitted event type and SDK contract rather than an individual game's response.
- No baseline-to-current regression delta is claimed; validation applies only to the exact overlaid snapshot.

## Open questions and assumptions

- Assumption: holding a mapped left/right mouse button while moving the other pad is intended to support ordinary macOS drag interaction. If not, document drag as unsupported and reconsider whether held mouse buttons should be offered in Zones.
- Question: when a permission becomes ready, should the action message disappear entirely or briefly show a dedicated **Access ready** confirmation before returning to operational status?
- Assumption: the standalone verifier is intended to attest to the distributable ZIP, not merely to a separate staging app and a checksum file.
- Assumption: Paddr remains arm64-only, macOS 26.0 remains the deployment target for a possible Apple-silicon backport, and Xcode 27 remains the release toolchain.
- Assumption: per-game/app profiles remain roadmap-only and do not alter this remediation scope.

## Target shape

- Pointer output emits the correct moved or dragged event according to centrally owned mouse-button state.
- Permission state transitions are typed, truthful, and converge after prompts/settings changes without stale action copy.
- One release verifier proves the identity, metadata, contents, architecture, resources, and signature of the app actually contained in `Paddr.zip`.
- Output-dispatch concurrency guarantees are enforced by the type boundary rather than asserted unchecked.
- The visual pad map and runtime hit testing share normalized geometry and presentation labels.
- Known binding labels are catalog-backed, while truly custom values remain explicit diagnostics/verbatim data.
- Async tests await deterministic dependency signals and cover every app-level generation transition.

## Phased remediation roadmap

### Phase 0 — Current behavior and release assurance

One focused runtime/model/packaging change set:

1. Add held-button-aware drag event output and cross-pad drag tests.
2. Reconcile permission request/refresh status and add delayed-grant model tests.
3. Extract and validate the archived app in `verify-release.sh`; add tampered ZIP regression cases.

Acceptance: held left/right mappings drag correctly; permission status converges truthfully; the isolated fake ZIP probe is rejected while a clean arm64 package still passes.

### Phase 1 — Concurrency and deterministic-test closure

One core/test change set:

1. Remove or internally enforce the output dispatcher's unchecked `Sendable` contract.
2. Replace yield-count polling with awaitable test signals.
3. Add active Save & Apply, rapid disable/enable, reconnect supersession, permission completion, and termination generation tests.

Acceptance: no production output type makes an unenforced cross-task promise, and lifecycle tests have no scheduler-count timeout loops.

### Phase 2 — UI geometry and localization polish

One UI/resources change set:

1. Share normalized geometry between zone hit testing and rendering.
2. Add catalog-backed key/mouse presentation labels and use them everywhere.
3. Run the deferred human accessibility/appearance matrix and physical unplug/replug acceptance without capturing README screenshots until separately approved.

Acceptance: preview boundaries match runtime at representative deadzones and sizes; known labels are consistently localized; manual release gates are recorded honestly.

## Summary

The second remediation held: lifecycle serialization, Save-then-start persistence, zone selection, typed failures, accessibility representation, localization extraction, numeric safety, removal cleanup, output arbitration, arm64 packaging, and portable checksums remain materially improved. This audit found no new high-severity regression. The most important remaining work is to make held mouse buttons produce real drag events, make permission completion converge to truthful status, and verify the app inside the release ZIP rather than a separate bundle. Four lower-risk findings cover sendability, preview geometry, known binding labels, and deterministic test signaling.

## Remediation closure — 2026-08-11

The findings above are retained as historical evidence. The release-preparation working tree now contains the following remediation.

- **PRA-001 — Resolved in implementation and automated acceptance.** `CGEventOutput` tracks Paddr-owned held mouse buttons and emits `leftMouseDragged` or `rightMouseDragged` for pointer movement while the matching button is down. Left-button drag has defined precedence if both buttons are held. Tests cover unheld movement, left drag, right drag, and dual-button precedence. A live game-specific drag pass remains recommended.
- **PRA-002 — Resolved.** Immediate and delayed permission completion now returns to the truthful operational state instead of reporting a configuration save or retaining stale prompt copy. Model tests cover both already-granted permissions and one-at-a-time delayed completion.
- **PRA-003 — Resolved.** The verifier validates the checksum first, rejects unsafe archive paths and unexpected top-level contents, extracts into a fresh validated temporary directory, rejects symlinks, verifies metadata/architecture/resources/content/signature on the archived app itself, and requires an exact recursive match with the staged app. The audit's `/bin/echo` archive pattern is now a permanent negative regression test.
- **PRA-004 — Resolved.** `CGEventOutput` no longer uses `@unchecked Sendable`. Its complete output batch and held-button state are serialized by `Synchronization.Mutex`, while each non-Sendable Core Graphics event source remains confined to the locked dispatch operation.
- **PRA-005 — Resolved.** Shared `ZoneMapGeometry` renders radial and corner neutral regions with independent x/y radii, matching normalized runtime coordinates in a non-square map. Geometry tests cover radial, horizontal, vertical, and grid layouts.
- **PRA-006 — Resolved.** Known keyboard and mouse bindings have explicit `LocalizedStringResource` presentation names shared by both pickers and the Canvas. Literal letters/digits and custom `code:N` values remain deliberately verbatim. The English catalog and explicit known-binding matrix now cover every known label.
- **PRA-007 — Resolved.** Bounded `Task.yield()` polling was removed. Session tests await actor epoch and injected runtime-start signals; model tests await status change streams. Added coverage exercises delayed permission completion, active Save & Apply restart, and reconnect supersession, alongside the existing concurrent start, cancellation, stale-event, reconnect, and termination cases.

### Closure validation

- Xcode 27 warnings-as-errors tests passed: 39 core tests and 24 app-support tests, 0 failures.
- The arm64 release package build passed with warnings as errors; XcodeBuildMCP 2.6.2 independently built the `TrackIsBackMenu` release target.
- String Catalog extraction coverage and compilation, shell syntax, plist/JSON validation, and `git diff --check` passed.
- Fresh ad-hoc and Developer ID packages for `0.6.1 (10)` passed arm64 architecture, hardened-runtime/strict signature, exact bundle contents, smoke launch, clean ZIP, basename-only digest, clean-recipient verification, wrong-version/build rejection, and tampered-archive rejection. Developer ID identity: `Developer ID Application: Zachary Skjaveland (9T97GZT4MV)`.
- A live configuration-window pass confirmed native segmented controls, permission controls, compact side-by-side pad cards across every behavior, right-side zone inspection, configurable center deadzone, 3 × 3 zone selection without a neutral region, catalog-backed labels, semantic selected-area pop-up, and the pinned command bar. Fresh README screenshots were captured after explicit approval.

### Residual manual release gates

- Physical unplug/replug while holding a keyboard key, left mouse button, and right mouse button remains unperformed; PPA-002 is still not claimed as physically hardware-verified.
- Human VoiceOver listening, Full Keyboard Access, large accessibility text, Increase Contrast, and Reduce Transparency remain release-checklist work rather than open code findings.
- Developer ID signing is locally valid, but the artifact has not been submitted to Apple for notarization or stapled. No release was uploaded by this remediation.
