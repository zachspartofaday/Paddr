# PuckPads repository audit

Date: 2026-08-11
Scope: current local `codex/ui-refinement` checkout at `be53561c53089ed2119c2ef157d09a194c7e7c9e` plus its 20 tracked, uncommitted files
Audit type: report-only repository audit
Readiness assessment: suitable for an explicitly experimental prerelease; not yet ready for a stable public release

## Executive summary

The repository is compact, understandable, and builds cleanly with the intended Xcode 27 beta toolchain. Both the public baseline and the current local delta pass all 18 tests with warnings promoted to errors. The current app also builds in release mode, produces a strictly verifiable ad-hoc-signed bundle, and passes its smoke test.

The main release blockers are input correctness and HID lifecycle behavior. A stored tap binding can fire while a pad is Off or in Zones mode even though the UI hides it in Zones mode. The HID stream does not observe device removal, so unplugging the puck can leave the app reporting active output and delay release of held keys or mouse buttons indefinitely. Output is also emitted independently by each pad, so two sources mapped to the same binding can release each other incorrectly.

Finding count: 2 High, 5 Medium, 1 Low.

## Authority and repository map

- No repository-local `AGENTS.md`, active issue, open pull request, PRD, or implementation plan was present. `README.md`, `CONTRIBUTING.md`, `Package.swift`, and the live checkout were treated as current authority.
- The GitHub repository had no open issues or pull requests at audit time. `.github/CODEOWNERS` assigns all paths to `@zachspartofaday`.
- The package contains one core library, one CLI executable, one SwiftUI menu-bar executable, and one XCTest target: `Package.swift:5-18`.
- Inventory: 35 Swift files and approximately 3,042 Swift source/test lines. There are no third-party package dependencies, C/Objective-C targets, SwiftData models, Xcode project/workspace files, configured linters, or hosted CI workflows.
- Deployment target is macOS 26.0, while validation used Xcode 27.0 beta, macOS 27.0 SDK, and Swift 6.4. Verbose compiler and linker invocations explicitly selected `MacOSX27.0.sdk` and `arm64-apple-macos26.0`.
- Specialist lenses applied: SwiftUI/accessibility, Swift concurrency and HID bridging, and XCTest quality. SwiftData, UIKit modernization, C bounds safety, and Xcode-project security settings were not applicable.

## Findings

### PPA-001 — High — Hidden tap bindings execute in Off and Zones modes

Status: Confirmed by isolated executable probe.

Evidence:

- On a new touch, tap eligibility is enabled for every non-mouse mode: `Sources/TrackIsBackCore/PadMapper.swift:61-65`.
- On lift, any configured `tapKey` is emitted without checking the active mode: `Sources/TrackIsBackCore/PadMapper.swift:105-114`.
- The menu hides Touch tap in Zones mode but retains the stored binding; it also displays Touch tap while the pad is Off: `Sources/TrackIsBackMenu/PadConfigurationView.swift:58-60`.
- An isolated mapper probe produced Space down/up from both `.disabled` and `.dpad` configurations carrying `tapKey = "space"`.

Impact:

Changing a pad from Pointer or Scroll to Off can still emit its old tap action. In Zones mode, touching the neutral area of radial, corner, or two-way layouts can fire a concealed tap binding. The runtime therefore does something the visible configuration does not describe.

Recommended fix:

- Define tap-capable modes explicitly—based on current product direction, Pointer and Scroll—and gate both tap tracking and emission on that policy.
- Hide Touch tap for Off and all Zones layouts so presentation and runtime share the same rule.
- Add regression tests proving Off and every Zones layout cannot emit `tapKey`, including a saved configuration that changes modes without clearing the binding.

### PPA-002 — High — Device removal does not end the HID session or promptly release output

Status: Inferred manifestation; confirmed lifecycle omission.

Evidence:

- The HID stream registers only an input-report callback and loops solely on the external stop token/deadline: `Sources/TrackIsBackCore/TritonHIDDevice.swift:116-143`.
- Failed report callbacks are ignored and no removal state is recorded: `Sources/TrackIsBackCore/TritonHIDDevice.swift:118-122`.
- Held zone actions are released only when `TrackpadRuntime.run` exits: `Sources/TrackIsBackCore/TrackpadRuntime.swift:60-66`.
- The menu reconnects after open failure or a stopped session, but the active stream has no path to produce either event on removal: `Sources/TrackIsBackMenu/TrackIsBackMenuModel.swift:202-234`.
- IOKit provides [`IOHIDDeviceRegisterRemovalCallback`](https://developer.apple.com/documentation/iokit/1588673-iohiddeviceregisterremovalcallba) specifically to notify clients when a device is removed.

Impact:

If the controller or puck disconnects while a zone is holding a key or mouse button, PuckPads can continue to show output as active and retain that logical press until the user turns output off or quits. Automatic reconnect cannot begin because the old stream has not ended.

Recommended fix:

- Register a device-removal callback before scheduling the device, make it terminate the stream, and unregister it during teardown.
- Convert removal into a typed disconnected event, dispatch one centrally owned release-all operation, and then enter the reconnect state.
- Verify with an injected stream test and a physical unplug/replug test while a key and each mouse button are held.

### PPA-003 — Medium — Independent pad output has no shared binding ownership

Status: Confirmed by isolated executable probe.

Evidence:

- Left and right mappers produce raw actions independently and their arrays are concatenated: `Sources/TrackIsBackCore/TrackpadRuntime.swift:54-55,73-82`.
- Each mapper tracks only its own active zones: `Sources/TrackIsBackCore/PadMapper.swift:48-50,124-133`.
- An isolated probe mapped both pads' Up zone to Space. It emitted two Space-down events, followed by Space-up when the left pad lifted while the right pad remained touched.

Impact:

The same key or mouse button can be assigned to multiple zones or pads. Releasing any one source releases the system-level binding even when another source still holds it; duplicate down events are also posted. This makes overlapping configurations behave inconsistently.

Recommended fix:

Place a central output-state reducer between mappers and `CGEventOutput`. Reference-count or source-own every key/mouse-button binding, emit down only on the first acquisition, emit up only on the final release, and provide an idempotent global release-all operation. Test same-binding overlap across pads, across zone transitions, and between a tap and a held zone.

### PPA-004 — Medium — Session replacement is not serialized

Status: Inferred from thread lifecycle.

Evidence:

- `TrackpadSession.start` requests that the previous token stop, then immediately starts a new `Thread`: `Sources/TrackIsBackCore/TrackpadRuntime.swift:98-134`.
- `stop()` clears the token but does not wait for the old thread or output teardown: `Sources/TrackIsBackCore/TrackpadRuntime.swift:137-150`.
- Save & Apply starts a replacement session whenever output is enabled: `Sources/TrackIsBackMenu/TrackIsBackMenuModel.swift:55-64`.
- The menu's session UUID suppresses stale UI events, but it does not guard `CGEventOutput` posts in the old worker: `Sources/TrackIsBackMenu/TrackIsBackMenuModel.swift:136-146,202-203`.

Impact:

Rapid restart or Save & Apply can allow old and new workers to overlap. The old worker's deferred key-up can cancel a key newly held by the replacement session, even though stale status callbacks are ignored.

Recommended fix:

Use one serialized session owner. Do not open the replacement device until prior stream teardown and release-all complete, or generation-gate all output through the shared output reducer. Add repeated start/stop/start tests that deterministically block teardown to expose overlap.

### PPA-005 — Medium — Finite configuration values can still trap at runtime

Status: Confirmed by isolated executable probe.

Evidence:

- Validation accepts any positive finite `tapMaximumMilliseconds` and sensitivity value: `Sources/TrackIsBackCore/Configuration.swift:186-200`.
- Tap handling multiplies milliseconds and converts directly to `UInt64`: `Sources/TrackIsBackCore/PadMapper.swift:107-112`.
- Scroll output converts rounded `Double` values directly to `Int32`: `Sources/TrackIsBackCore/CGEventOutput.swift:80-89`.
- The CLI accepts arbitrary finite values for these fields: `Sources/TrackIsBackCLI/main.swift:88-92,118-145`.
- A validated configuration using `Double.greatestFiniteMagnitude` for the tap window terminated with: `Fatal error: Double value cannot be converted to UInt64 because it is either infinite or NaN`.

Impact:

A hand-edited config or CLI argument can pass validation and crash the process during normal pad input. Large sensitivity values can likewise overflow intermediate motion/scroll values and reach trapping integer conversion.

Recommended fix:

Give every numeric option a documented operational range, enforce it in shared validation, reject arithmetic overflow before conversion, and clamp only at the final platform boundary where clamping is intentional. Add boundary tests for maximum accepted values and rejection tests immediately above them.

### PPA-006 — Medium — The session, reconnect, permissions, and persistence paths lack test seams

Status: Confirmed structural gap.

Evidence:

- The only test target depends on `TrackIsBackCore`: `Package.swift:13-18`.
- All 18 tests are in `Tests/TrackIsBackTests/TrackIsBackTests.swift` and cover parser/mapping behavior; there are no tests for `TrackpadSession`, `TrackpadRuntime`, `TritonHIDDevice`, `ConfigurationStore`, menu state transitions, reconnect, or permission handling.
- The menu model directly constructs a concrete session and calls static hardware, permission, and storage functions: `Sources/TrackIsBackMenu/TrackIsBackMenuModel.swift:26-30,36-51,55-64,111-147`.
- Baseline and current local code both report 18 passing tests despite the current session/reconnect and UI-state changes.

Impact:

The highest-risk behavior cannot be exercised deterministically without hardware and system permission state. PPA-002 and PPA-004 are consequently harder to fix confidently and easier to regress.

Recommended fix:

Inject narrow interfaces or closures for device discovery/open/stream, session control, output dispatch, permissions, configuration storage, and retry timing. Keep the existing XCTest target unless a separate migration is requested. Add state-machine tests before expanding presentation tests, and use only redacted report fixtures.

### PPA-007 — Medium — App assembly and release archive creation are not clean/reproducible

Status: Confirmed.

Evidence:

- `scripts/build-app.sh` creates directories inside an existing exact bundle path but never removes or recreates `PuckPads.app`: `scripts/build-app.sh:6-25`. Stale resources can survive into a later signed build.
- The script builds, assembles, signs, and verifies the bundle, but there is no checked-in archive, digest, architecture, notarization, or stapling workflow: `scripts/build-app.sh:28-50`.
- The published v0.6.0 ZIP contains `__MACOSX` and AppleDouble `._*` metadata. Its app is ad-hoc signed and arm64-only.
- The public asset digest was verified against GitHub: `f8f18ee4b681fbb74324503ae8f71543b35b40a1a01f52f3c649501cc902ac20`.
- The ad-hoc/not-notarized limitation is clearly disclosed in `README.md:33-34,56-64`; it is an accepted prerelease risk, not an undisclosed defect.

Impact:

Reusing an output directory can include files no longer owned by the current source tree. The downloadable archive is noisier than necessary, and release verification depends on manual steps. Ad-hoc identity also explains permission churn between versions.

Recommended fix:

- Assemble each bundle in a fresh temporary directory and fail if unexpected bundle contents remain.
- Add a deterministic archive script using a resource-fork-free archive path, then verify bundle version, supported architectures, strict signature, archive contents, and SHA-256.
- Keep ad-hoc builds explicitly prerelease-only. Before a stable release, use the available Developer ID identity, hardened runtime, notarization, and stapling under explicit operator approval.
- Decide and document whether arm64-only is intentional; build universal only if supported Intel hardware/OS remains in scope.

### PPA-008 — Low — Header status layout and user-facing strings are not adaptive

Status: Inferred from code; visual verification intentionally deferred.

Evidence:

- Up to four single-line pills are placed in one non-adaptive `HStack`: `Sources/TrackIsBackMenu/AppHeaderView.swift:41-65` and `Sources/TrackIsBackMenu/StatusBadge.swift:8-19`.
- The panel is fixed at 560 points wide: `Sources/TrackIsBackMenu/TrackIsBackStyle.swift:28-43`.
- Status components and model messages use runtime `String` values, and the package has no String Catalog or localization resources.

Impact:

Longer localized labels and accessibility text sizes can truncate or crowd status information. English at the current default text size is likely acceptable, but this does not yet meet a robust localization/accessibility target.

Recommended fix:

Use `ViewThatFits`, wrapping layout, or a small adaptive grid for pills; move user-facing resources to `LocalizedStringResource`/String Catalog boundaries; and verify keyboard navigation, VoiceOver output, Increase Contrast, Reduce Transparency, and large accessibility text sizes once the user authorizes a fresh visual pass.

## Overturned or deferred suspicions

- SDK selection is not a finding. Although Mach-O inspection reports an unexpected SDK load-command value in this beta toolchain, verbose build commands explicitly use `/Applications/Xcode-beta.app/.../MacOSX27.0.sdk`; the README's Xcode 27 SDK claim is supported.
- Repeated privacy permission requests are a documented consequence of the current ad-hoc identity, not a newly undisclosed defect. Stable Developer ID signing and notarization remain the intended remedy.
- Existing README screenshots may no longer match the uncommitted UI refinement. Screenshot validation and replacement were deliberately skipped because the user asked not to take screenshots until the UI is approved.
- `KeyAssignment.swift` and `KeyAssignmentGrid.swift` appear unused. They are cleanup drift, but no runtime impact justified elevating them into the prioritized finding list.
- No credential-like strings or private signing material were found by the scoped repository scan.

## Recommended target shape

The smallest durable architecture keeps `PadMapper` deterministic, adds one source-aware output reducer, and makes a single session coordinator own HID lifetime:

1. `TritonHIDDevice` reports input or removal through an injectable stream boundary.
2. Left/right mappers return desired source transitions, not globally authoritative key-up/down events.
3. One output reducer owns binding reference counts and idempotent release-all behavior.
4. One serialized session coordinator owns open, run, stop, disconnect, teardown, and reconnect transitions.
5. The main-actor menu model presents coordinator state and receives storage/permission services through narrow dependencies.

This keeps report-rate HID work off broad SwiftUI state while making safety-critical transitions testable without physical hardware.

## Phased remediation plan

### Phase 0 — Input safety

- Fix PPA-001 mode gating.
- Add shared output ownership for PPA-003.
- Add HID removal handling and guaranteed release-all for PPA-002.
- Serialize replacement sessions for PPA-004.

Exit criteria:

- Off and all Zones layouts never emit a stored tap binding.
- Two pads holding the same key/button produce one down and one final up.
- Disconnect while holding every output type releases it once, reports disconnected, and begins retry.
- Repeated Save & Apply cannot overlap worker output.

### Phase 1 — Robustness and deterministic tests

- Add numeric bounds and overflow-safe conversion for PPA-005.
- Introduce the test seams in PPA-006 and cover the coordinator state machine.
- Add redacted parser fixtures for validated puck variants when captures are available.

Exit criteria:

- Invalid extreme values fail validation rather than terminating.
- Stop, disconnect, failure, reconnect, stale callback, and permission-denied paths are deterministic tests.
- All tests pass with warnings promoted to errors on the Xcode-beta toolchain.

### Phase 2 — Release hardening

- Make app assembly clean and archive generation deterministic.
- Add artifact checks and document architecture policy.
- Under explicit release approval, sign with Developer ID, notarize, staple, and validate the exact public asset.

Exit criteria:

- A release starts from a fresh output path and contains only expected files.
- The archive has no `__MACOSX`/AppleDouble metadata.
- Signature, notarization ticket, version/build, architecture, ZIP digest, install, launch, and privacy identity are verified before upload.

### Phase 3 — Accessibility and presentation finish

- Make status pills adaptive and establish localization resources.
- Remove unused presentation types after confirming no planned reuse.
- Perform the deferred visual/accessibility pass and refresh README screenshots only after UI approval.

## Validation record

Executed against both the clean v0.6.0 baseline and the isolated current local delta where noted:

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test --disable-sandbox -Xswiftc -warnings-as-errors`
  - Baseline: passed, 18 tests, 0 failures.
  - Current: passed, 18 tests, 0 failures.
  - Delta: no test-count or failure delta.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release --disable-sandbox -Xswiftc -warnings-as-errors`
  - Current: passed.
- `scripts/build-app.sh` with a fresh temporary output and scratch path
  - Current: passed; ad-hoc bundle assembled and strict `codesign` verification passed.
- `plutil -lint Packaging/Info.plist`
  - Passed.
- `PuckPadsMenu --smoke-test`
  - Passed; default modes reported and no device was found, as expected for the isolated run.
- `git diff --check`
  - Passed.
- Scoped credential/private-signing-material scan
  - No matches.
- Isolated behavior probes
  - Confirmed concealed Off/Zones taps.
  - Confirmed cross-pad premature key release.
  - Confirmed runtime trap from an accepted extreme tap duration.
- Public v0.6.0 asset inspection
  - GitHub and local SHA-256 matched; strict bundle signature verification passed; artifact is ad-hoc signed, arm64-only, and includes Finder metadata.

Not executed:

- Physical controller input, unplug/replug, game compatibility, and real permission transitions: no controller was connected to the isolated audit run.
- GUI screenshots or screenshot-based comparison: explicitly deferred by user request.
- Developer ID signing, notarization, stapling, release upload, or any other outward-facing mutation: outside audit authorization.
- Lint/format/hosted CI: no repository-configured tool or workflow exists.

## Assumptions and residual risk

- Tap behavior is assumed to be intentional only in Pointer and Scroll modes. If the product wants taps in some non-grid Zones layouts, that policy needs to be visible and configurable rather than inherited from a hidden stale binding.
- `0x1304` puck behavior remains the only confirmed hardware path; `0x1305`, Bluetooth, direct USB, and future macOS 27 beta behavior remain unvalidated as documented.
- The audit reviewed the current uncommitted local delta without modifying it. Recommendations do not imply authorization to commit, push, publish, sign, notarize, or replace release assets.

## Remediation addendum — 2026-08-11

The original findings above are retained as historical context. The local working tree now contains the following remediation evidence; no commit, push, notarization, release upload, or screenshot capture was performed.

### Finding closure registry

- **PPA-001 — Resolved.** `PadMode.allowsTouchTap` is the shared runtime/UI policy and permits taps only in Pointer and Scroll. Mapper tests prove Off and every Zones layout cannot emit a retained tap binding, while Pointer and Scroll taps remain covered.
- **PPA-002 — Resolved in implementation and simulated acceptance; physical unplug acceptance pending.** IOHID removal now produces typed `.deviceRemoved` termination, discards queued reports, exits the stream, releases centrally owned output, updates the model to disconnected, preserves the enabled toggle, and begins reconnecting. Injected runtime and model tests pass. The connected local `0x28DE:0x1304` puck was probed and opened passively, but the controller was not physically unplugged/replugged while a key and both mouse buttons were held; this finding is therefore not claimed as fully hardware-verified.
- **PPA-003 — Resolved.** `OutputArbiter` source-owns keys and mouse buttons across both pads, suppresses duplicate downs, delays up until final release, protects held bindings from matching taps, and implements idempotent global release. Overlap, duplicate, tap-versus-held, and repeated-release tests pass.
- **PPA-004 — Resolved.** `TrackpadSession` is an actor. It awaits prior worker teardown before replacement, confines the blocking IOKit loop to an explicit detached task, and generation-gates stream events with `Synchronization.Mutex`. Deterministic gated-worker tests prove no overlap and reject late stale events.
- **PPA-005 — Resolved.** Shared validation enforces sensitivity `0.1...20`, tap window `1...5000 ms`, tap movement `0...100000`, mouse radius `0...1`, and D-pad deadzone `0..<1`. Boundary/adjacent-invalid tests pass, tap conversion is bounded, and finite scroll output clamps at `Int32` limits.
- **PPA-006 — Resolved.** HID streaming, output dispatch, session control, permission operations, configuration storage, and retry sleeping have narrow injectable boundaries. The main-actor observable model lives in `PaddrAppSupport`, shared by the executable and a dedicated XCTest target. Model tests cover permissions, disconnected enable, reconnect, removal, persistence, defaults, and failure state.
- **PPA-007 — Resolved.** App assembly occurs in a fresh validated staging directory and replaces the exact destination only after signing and verification. Distribution is arm64-only because Intel Macs cannot run macOS 27, which supplies the required controller support. `scripts/package-release.sh` verifies metadata, the exact arm64 architecture set, resources, strict signature, exact bundle contents, smoke launch, clean ZIP entries, and SHA-256. Stale-file rebuild, ad-hoc signing, and installed Developer ID signing all passed locally. Notarization and publication remain intentionally out of scope.
- **PPA-008 — Resolved in implementation; manual assistive-technology pass pending.** The resizable standalone configuration window, compact menu-bar control, compact status/access surfaces, system appearance, Steam-blue tint, semantic text hierarchy, `ViewThatFits` fallbacks, Reduce Transparency fallback, native glass action family, interactive runtime-aligned pad map, accessible inspector, and compiled English String Catalog are implemented. Warnings-as-errors builds pass. The screenshot-free accessibility automation service timed out while reading the earlier popover build, so VoiceOver, keyboard-only, large-text, Increase Contrast, and Reduce Transparency interaction should receive a final human pass before release.

### Remediation validation record

- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift test -Xswiftc -warnings-as-errors`
  - Passed: 34 core tests and 7 app-support tests, 0 failures.
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer swift build -c release -Xswiftc -warnings-as-errors`
  - Passed for the complete package.
- Clean arm64 app assembly and stale-file injection rebuild
  - Passed; stale content was absent after rebuild; the executable architecture is exactly `arm64`; compiled `en.lproj/Localizable.strings` is present; strict ad-hoc signature verification passed.
- `scripts/package-release.sh`
  - Passed; version `0.6.1`, build `10`, exact bundle whitelist, smoke launch, resource-fork-free ZIP, metadata rejection, and SHA-256 verification passed.
- Developer ID validation
  - Passed with `Developer ID Application: Zachary Skjaveland (9T97GZT4MV)`, hardened runtime, arm64 executable, strict signature verification, clean `Paddr.zip`, and verified SHA-256.
- Standalone-window smoke check
  - Passed without screenshots. The Developer ID-signed `Paddr.app` launched a titled `Paddr` configuration window at the intended 760×900-point content size. Closing the window removed it while the exact Paddr process remained active for menu-bar operation.
- Live read-only hardware check
  - Input Monitoring and Accessibility reported granted; puck `0x28DE:0x1304`, interface 2, usage `0x0001/0x0002`, 54-byte input report was selected and passively opened. No feature report or hardware-mode mutation occurred.
- `git diff --check`
  - Passed.
- README images
  - Untouched, as required.

### Product identity and window architecture addendum

- The user-facing product is now **Paddr**, with bundle identifier `com.partofaday.Paddr`, executable `Paddr`, and app bundle `Paddr.app`.
- Existing configuration is preserved through ordered fallback migration from `~/.config/PuckPads`, `~/.config/TracksBack`, and `~/.config/TrackIsBack`; new saves use `~/.config/Paddr`.
- Configuration now lives in a standard resizable window that opens at launch and can be reopened after closing. The menu-bar surface is intentionally limited to the output toggle, **Open Configuration**, and **Quit Paddr**.
- Per-game and per-app profiles inspired by Paddlr are recorded as a future roadmap item only and are not implemented in this remediation scope.
- Because Paddr has a new bundle identity, macOS permission approval is expected once when moving from a prior PuckPads build. A stable Developer ID signature should preserve identity across subsequent signed Paddr updates.

### Follow-up correction and verification — 2026-08-11

- The first addendum's PPA-004 closure was overturned by follow-up finding PFA-001: concurrent actor calls could reenter while teardown was suspended. The final implementation retains the worker record across that suspension and launches only the latest uncancelled epoch. Deterministic concurrent lifecycle tests now prove `maximumConcurrent == 1`, stale-event rejection, ordered old-worker exit before replacement output, and zero workers after stop.
- PPA-008 now has a successful screenshot-free AX follow-up. The zone editor exposes a native, labeled `AXPopUpButton` with help, value, stable identifier, and keyboard selection; the unknown Canvas accessibility element is gone. Catalog extraction coverage and a reduced-height/adaptive-appearance smoke pass also succeed. A human VoiceOver listening pass remains recommended before publication.
- PPA-002 remains resolved in implementation and simulation but not physically verified. The local `0x28DE:0x1304` puck is detectable; no claim is made that a person completed the held-key/left-click/right-click unplug and reconnect sequence.
- Final automated totals are 36 core tests and 18 app-support tests, all passing under Xcode 27 with warnings as errors. Universal ad-hoc and installed Developer ID packaging both pass strict signature and portable-checksum verification.
