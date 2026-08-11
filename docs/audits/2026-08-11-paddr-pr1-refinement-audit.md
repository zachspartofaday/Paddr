# Paddr PR #1 refinement audit — 2026-08-11

Status: Complete — 13 findings (1 High / 7 Medium / 5 Low); PUA-009 and PUA-013 fixed in this PR;
remaining items routed to the remediation kickoff (`docs/kickoffs/2026-08-11-audit-remediation-orchestrate.md`)

## Scope and method

- **Target**: the full repository state at commit `65db6a9` ("Remediate audit findings and polish
  Paddr UI"), the head of PR #1 (`codex/ui-refinement`). PR #1 is the repository bootstrap, so the
  PR diff and the repository state are the same surface.
- **Checkout**: a detached read-only git worktree pinned to `65db6a9`; the live checkout was left
  free for the concurrent UI refinement pass. All finding evidence refers to `65db6a9`.
- **Method**: file/target inventory first, then three specialist review lanes (SwiftUI, Swift
  concurrency/lifecycle, Swift Testing + scripts/packaging/docs) run against the installed
  `swiftui-pro`, `swift-concurrency-pro`, and `swift-testing-pro` skill references, plus sampled
  re-verification of closure claims from the four prior audits in `docs/audits/`. Findings are
  spot-verified against source before registration.
- **Evidence bar**: `file:line` references at `65db6a9`, or a command plus its observed output.
  Confidence is recorded as confirmed (verified in source/runtime) or inferred (judged from
  reading, not exercised).
- **Exclusions**: Apple notarization/stapling (explicitly out of PR scope), physical-puck manual
  gates (unplug/replug matrix), the human assistive-technology matrix, and hosted CI (none is
  configured; local gates are the merge authority for this repository).

## Inventory

- **Swift targets** (`Package.swift`): `TrackIsBackCore` (10 files — HID device, parser, runtime,
  mapper, output arbiter, CGEvent output, configuration + store, key catalog),
  `PaddrAppSupport` (6 files — menu model, dependencies, status, window/zone geometry, zone
  selection policy), `TrackIsBackMenu` (20 SwiftUI files — app delegate, configuration window,
  pad/zone views, style tokens), `TrackIsBackCLI` (1 file), test targets `TrackIsBackTests`
  (7 files) and `PaddrAppSupportTests` (4 files). ~6.0k lines of Swift total.
- **Domain sweep**: SwiftUI + AppKit shell, @Observable/@MainActor + IOHID/CF-run-loop callbacks,
  XCTest test suites (no Swift Testing usage; judged in place, migration not treated as a defect),
  no SwiftData, no legacy UIKit shared-state APIs, no C sources.
  Specialist routing: `swiftui-pro`, `swift-concurrency-pro`, `swift-testing-pro`;
  `swiftdata-pro`/`uikit-app-modernization`/`c-bounds-safety` not applicable.
- **Scripts**: 9 shell scripts (build, run, packaging, release verification, localization check,
  CLI smoke, icon generation). **Docs**: README, CONTRIBUTING, SECURITY, 4 prior audits, issue
  templates. **Validation authority**: CONTRIBUTING §Development (Xcode 27 beta toolchain,
  macOS 26 deployment target, arm64-only distribution).

## Findings

Severity index: **High** PUA-001 · **Medium** PUA-002, PUA-004, PUA-005, PUA-006, PUA-009,
PUA-010, PUA-013 · **Low** PUA-003, PUA-007, PUA-008, PUA-011, PUA-012.
Sections below are in stable-ID order; IDs never renumber.

### PUA-001 — Device-removal cleanup can abandon held outputs yet report successful removal

- **Domain**: concurrency/lifecycle. **Severity**: High. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Sources/TrackIsBackCore/TrackpadRuntime.swift:98-105,126-129` and
  `Sources/TrackIsBackCore/CGEventOutput.swift:29-50,60-75,134-142`. Teardown sends all held-output
  releases through one throwing batch and suppresses its error with `try?`; a failure creating one
  release event aborts every later release, after which `run` still returns `.deviceRemoved` as if
  cleanup succeeded. Mouse-button posting also returns silently when the cursor-location lookup
  fails, so a mouse-up can be treated as dispatched without being posted.
- **Why it matters**: CONTRIBUTING's hard rule is that controller removal must release every held
  key and mouse button. On these error paths the app can leave a key or button logically held
  while presenting a clean removal/reconnect.
- **Fix direction**: attempt every held-output release independently, make mouse-up creation
  failure explicit, propagate aggregate cleanup failure, and prevent a clean removal/reconnect
  transition until cleanup has succeeded or been surfaced as a terminal failure.

### PUA-002 — Generation gate has a check-then-yield stale-event window

- **Domain**: concurrency. **Severity**: Medium. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Sources/TrackIsBackCore/TrackpadRuntime.swift:164-170,181-219,281-290`.
  Callbacks release the gate mutex after `isCurrent(request)` and only then call
  `continuation.yield`; a replacement can activate a newer epoch between those two operations,
  letting an old `.connected`, `.progress`, or terminal event into the superseded stream. The menu
  model's second operation/session-ID check (`PaddrAppSupport/PaddrMenuModel.swift:241-245`)
  currently masks this, but the public session boundary itself does not satisfy strict stale-event
  rejection.
- **Fix direction**: make generation validation and enqueue one serialized operation, or route
  tagged events through the session actor and validate the tag immediately before delivery.

### PUA-003 — Synchronous filesystem and HID discovery work on the main actor

- **Domain**: concurrency/responsiveness. **Severity**: Low. **Confidence**: Inferred.
- **Evidence** (`65db6a9`): `Sources/PaddrAppSupport/PaddrMenuModel.swift:41-64,69-91,289-304`,
  `Sources/PaddrAppSupport/MenuDependencies.swift:38-47`. Main-actor initialization, status
  refreshes, saves, and one-second reconnect probes call synchronous configuration I/O and
  `IOHIDManagerOpen`/device enumeration directly. Normally short, but a delayed filesystem or
  IOKit service can stall launch, menus, and configuration interaction.
- **Fix direction**: move configuration reads/writes and controller probing behind async
  dependencies that execute off the main actor and return Sendable snapshots.

### PUA-004 — Zone-binding test is self-referential

- **Domain**: testing. **Severity**: Medium. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Tests/PaddrAppSupportTests/ZoneSelectionPolicyTests.swift:41-48` sets
  and immediately reads each zone binding through the same subscript, so identically incorrect
  getter/setter mappings still pass. The runtime independently reads concrete fields
  (`Sources/TrackIsBackCore/PadMapper.swift:238-257`), which this test never cross-checks.
- **Fix direction**: assign all zone values before verification, assert the corresponding concrete
  `dpadKeys`/`gridKeys` fields, and drive mapper output for each zone/layout.

### PUA-005 — Stale-event coverage checks only late connection

- **Domain**: testing. **Severity**: Medium. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Tests/TrackIsBackTests/SessionTests.swift:89-105` rejects only a late
  `.connected` from the superseded stream and does not require that stream to be empty. The
  production gate has separate connection, progress, and terminal-event branches
  (`Sources/TrackIsBackCore/TrackpadRuntime.swift:187-218`), so removing either of the latter
  guards leaves the suite green. Compounds PUA-002.
- **Fix direction**: make the superseded runtime emit late connection and progress callbacks plus
  a terminal result, then assert the old stream is exactly empty.

### PUA-006 — Configuration migration tests do not pin every legacy path or older schema

- **Domain**: testing. **Severity**: Medium. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Tests/TrackIsBackTests/ConfigurationBoundaryTests.swift:12-27` checks
  only that PuckPads outranks TracksBack when both exist; TracksBack and TrackIsBack are never
  tested independently against the three fallbacks in
  `Sources/TrackIsBackCore/ConfigurationStore.swift:66-76`, and the missing-field schema defaults
  in `Sources/TrackIsBackCore/Configuration.swift:209-227` lack migration fixtures.
- **Fix direction**: add isolated cases for each legacy directory, explicit precedence, and
  representative old JSON documents missing every subsequently added field.

### PUA-007 — Termination test permits duplicate teardown calls

- **Domain**: testing. **Severity**: Low. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Tests/PaddrAppSupportTests/MenuModelTests.swift:253-266` accepts any
  `stopCount >= 2`; the scenario has exactly one pre-start stop and one termination stop, so an
  unintended third destructive stop would not fail the test.
- **Fix direction**: assert `stopCount == 2` and retain the completion-order assertion.

### PUA-008 — Localization gate breaks on repository paths containing whitespace

- **Domain**: packaging/scripts. **Severity**: Low. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `scripts/check-localization.sh:17-28` captures absolute filenames into
  a scalar and expands `$source_files` unquoted, so a checkout path with spaces word-splits.
- **Fix direction**: build the source-file argument list from NUL-delimited output via a quoted
  array or another NUL-safe invocation.

### PUA-009 — Accent color used as text fails light-appearance contrast

- **Domain**: SwiftUI/accessibility. **Severity**: Medium. **Confidence**: Confirmed (calculated).
- **Evidence** (`65db6a9`): `Sources/TrackIsBackMenu/PaddrStyle.swift:20-22`,
  `StatusCell.swift:17-35`, `ApplyBarView.swift:9-15`. `#1A9FFF` is used directly for
  caption/callout text; its sRGB contrast is 2.82:1 against white and ~2.62:1 against the cell's
  light accent-tinted background — below 4.5:1 for normal text and 3:1 for large text.
- **Fix direction**: keep the bright accent for controls, fills, and icons; use an
  appearance-adaptive darker variant for light-mode textual status values.
- **Disposition**: **fixed in this PR** — `PaddrStyle.accentText`/`warningText` adaptive colors
  applied to status values, apply-bar labels, mode capsules, and selected zone keycaps; dark
  rendering verified unchanged at runtime, light values chosen at ≥5:1 by calculation.

### PUA-010 — Opposite arrow keys select perpendicular zones in the radial map

- **Domain**: SwiftUI/keyboard accessibility (logic lives in `PaddrAppSupport`).
  **Severity**: Medium. **Confidence**: Confirmed.
- **Evidence** (`65db6a9`): `Sources/TrackIsBackMenu/ZonePadMap.swift:91-104`,
  `Sources/PaddrAppSupport/ZoneSelectionPolicy.swift:35-52,60-69,96-106`. For `.radialFour`,
  pressing Down from Up scores Right and Left at 11 but Down at 20, so stable candidate ordering
  returns Right; likewise Right from Left returns Up. Keyboard focus moves contrary to the
  pressed direction.
- **Fix direction**: give the four-way radial layout explicit directional transitions, or rank
  axis alignment ahead of nearest-row/column distance; pin with per-direction tests (interacts
  with PUA-004's test rework).

### PUA-011 — Animated window fitting does not honor Reduce Motion

- **Domain**: SwiftUI/accessibility. **Severity**: Low. **Confidence**: Inferred.
- **Evidence** (`65db6a9`): `Sources/TrackIsBackMenu/WindowContentFitter.swift:41-73`. Post-initial
  visible frame adjustments request animation based only on visibility and prior fitting; the
  fitter never consults the system Reduce Motion preference.
- **Fix direction**: suppress `setFrame(..., animate:)` when Reduce Motion is enabled and observe
  preference changes.

### PUA-012 — Content sizing uses legacy GeometryReader preference probes

- **Domain**: SwiftUI/modernization. **Severity**: Low. **Confidence**: Confirmed (no current
  sizing defect observed).
- **Evidence** (`65db6a9`): `Sources/TrackIsBackMenu/ConfigurationView.swift:47-65,86-93,113-127`.
  Content and command-bar heights are measured via background `GeometryReader` + custom preference
  keys; the macOS 26 target supports the narrower `onGeometryChange(for:of:action:)`.
- **Fix direction**: replace the two background readers and preference keys with
  `onGeometryChange` height observations, preserving the positive-height guards. Deliberately
  deferred out of this PR: the sizing plumbing was just behaviorally fixed (PUA-013) and this
  refactor deserves its own validated change.

### PUA-013 — Status-row insertion caused window refits and layout shifts during interaction

- **Domain**: SwiftUI/UX (operator-reported, reproduced). **Severity**: Medium.
  **Confidence**: Confirmed at runtime.
- **Evidence** (`65db6a9`): `Sources/TrackIsBackMenu/AppHeaderView.swift` inserted/removed the
  header status message row per `MenuStatus.needsActionMessage`; each status flip (e.g. the
  enable toggle's `.connecting` → `.active` sequence) changed measured content height, and
  `WindowContentFitter` animated a window resize — visible as window size shifts on toggle and
  as control movement/lag during slider drags whenever a status transition coincided.
- **Disposition**: **fixed in this PR** — the status line is a permanently reserved header slot
  that always shows the current status message, so status flips no longer change geometry.
  Verified by frame-sampling the window at 25 ms across a full enable→disable cycle: exactly one
  frame observed. (The same session removed `Slider(step:)` tick marks by quantizing through the
  binding — a requested refinement, recorded here for traceability, not a defect.)

## Prior-audit closure spot-checks

- **PCA-001** — VERIFIED-RESOLVED. `PaddrAppSupport/PaddrMenuModel.swift:126-168,396-405`:
  termination has a dedicated non-supersedable state/task, invalidates ordinary lifecycle work,
  awaits session stop and captured tasks, and invokes queued completions exactly once, matching
  the resolution recorded in `docs/audits/2026-08-11-paddr-current-state-repository-audit.md`.
- **PPA-002** — PARTIAL. Removal detection, queued-report discard, typed `.deviceRemoved`, and
  reconnect-preserving enablement are implemented
  (`TrackIsBackCore/TritonHIDDevice.swift:35-69,149-187`,
  `PaddrAppSupport/PaddrMenuModel.swift:358-370`), but `TrackpadRuntime.swift:98-105` suppresses
  release-dispatch failure, so the claim that removal releases every centrally owned output is not
  guaranteed on all error paths — see PUA-001.

- **PFA-001** (one-worker serialization) — VERIFIED-RESOLVED. Session code retains the active
  worker through awaited teardown and revalidates the request
  (`TrackIsBackCore/TrackpadRuntime.swift:160-170,231-237`); deterministic tests assert
  `maximumConcurrent == 1` and final zero activity (`Tests/TrackIsBackTests/SessionTests.swift:7-34,37-67`).
- **PRA-003** (archived-app verification) — VERIFIED-RESOLVED. The verifier rejects unsafe paths,
  extracts the ZIP, validates both app copies, and compares them recursively
  (`scripts/verify-release.sh:86-105`), with the substituted-executable regression covered in
  `scripts/test-release-package.sh:54-67`.

### Testing/packaging lane — verified-clean notes

The one-worker invariant is strongly pinned by tests; removal cleanup has a key-hold runtime test
(`Tests/TrackIsBackTests/RuntimeTests.swift:7-30`) plus key-and-mouse arbiter coverage
(`Tests/TrackIsBackTests/OutputArbiterTests.swift:55-65`); packaging metadata consistently
identifies Paddr 0.6.1 (10), `com.partofaday.Paddr`, arm64; no user-facing stale
PuckPads/TrackIsBack naming outside historical audits and migration paths; only the two current
`paddr-*.png` README images are tracked and `dist/` is absent/ignored.

### Concurrency lane — verified-clean notes

The one-worker invariant holds across concurrent start/start/stop (epoch/worker-record
transaction); HID callbacks mutate only mutex-protected state; mapper/arbiter state stays
worker-confined; successful removal releases mid-zone and mid-drag holds with synchronous tap
press/up pairs; `ConfigurationStore` writes atomically and loads legacy candidates in documented
precedence order. These were checked and are recorded so they are not re-raised.

## Validation performed

- Full local gate on the PR head after the UI refinement and same-PR fixes: `swift test
  -Xswiftc -warnings-as-errors` (TrackIsBackTests 45 + PaddrAppSupportTests 36, 0 failures),
  `scripts/check-localization.sh` (pass), `swift build -c release -Xswiftc -warnings-as-errors
  --arch arm64` (pass), CLI release build + `scripts/test-cli.sh` (pass).
- Runtime verification (real puck connected): live window captures of pointer/scroll, radial
  deadzone editing, and 3×3 zone editing; synthetic slider-drag and enable/disable probes with
  25 ms window-frame sampling (PUA-013 fix verified — one stable frame across the cycle).
- Skipped / residual risk: no light-appearance runtime session (PUA-009 light values are
  calculated, not screenshot-verified); no physical unplug/replug matrix; no assistive-technology
  matrix; notarization out of scope. Lane findings are source-level; no executable validation was
  run inside the pinned audit worktree itself.

## Target shape and phased fix list

**Target shape**: removal/teardown either provably releases every held output or surfaces a
terminal failure (never a clean `.deviceRemoved` with holds abandoned); the session boundary
enforces strict stale-event rejection without relying on the menu model's second check; tests pin
each hard rule so reverting any fix fails at least one test; UI keeps system-semantic,
contrast-safe colors and honors motion/contrast accessibility preferences end to end.

Phased list for the follow-up `/limitless-orchestrate` session (see the kickoff doc):

1. **Phase R1 — acts-wrong runtime**: PUA-001 (independent release attempts + explicit mouse-up
   failure + propagated cleanup state), PUA-002 (serialize gate check and enqueue), with tests
   pinning both (subsumes the PPA-002 partial closure).
2. **Phase R2 — acts-wrong UI logic**: PUA-010 (radial arrow navigation) with per-direction
   tests folded into the PUA-004 rework.
3. **Phase R3 — test-quality hardening**: PUA-004, PUA-005, PUA-006, PUA-007.
4. **Phase R4 — polish/modernization**: PUA-003 (async dependencies), PUA-008 (NUL-safe script),
   PUA-011 (Reduce Motion), PUA-012 (`onGeometryChange`).

## Summary

PR #1's repository state at `65db6a9` is broadly sound: the one-worker invariant, atomic
configuration persistence, zone-map/runtime geometry parity, packaging identity, and release
verification all checked out clean, and four sampled prior-audit closures were confirmed (one
partial). The material risks are concentrated in teardown error paths (PUA-001) and the
session-boundary stale-event gate (PUA-002), with a band of medium test-quality gaps that would
let regressions of the hard rules pass green. Two findings (PUA-009 contrast, PUA-013 window
refit) were fixed in this PR alongside the UI refinement pass; the rest are sized into four
remediation phases above.
