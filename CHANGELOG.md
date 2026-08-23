# Changelog

User-visible changes to Paddr are recorded here. Release entries describe confirmed behavior at the time of each release; later entries may supersede earlier limitations.

## 0.11.0 — In development

- Local and release app bundles now record their exact Git source revision and tracked, staged,
  or untracked checkout state (excluding designated root build artifacts).
- Release packaging requires a checkout without tracked, staged, or untracked source changes at
  an annotated version tag, and verifies that the tag, source plist, staged app, archive, version,
  build, and source revision agree.

## Unreleased

- Rebuilt the configuration, guide, status, permission, and menu surfaces as a compact
  dark family console shared with Paddr's sister application, using Paddr-local tokens,
  native macOS controls, stable `paddr.*` accessibility identifiers, and visible MIT
  attribution for the bounded source adaptation ([#76](https://github.com/zachspartofaday/Paddr/issues/76),
  [#78](https://github.com/zachspartofaday/Paddr/issues/78)).
- Blended the configuration and guide titlebars into the dark family background with
  full-size content, transparent titlebar backgrounds, and no separator. The configuration
  window keeps the compact titlebar height and presents its name as a plain 16-point semibold
  leading label rather than a toolbar control, while retaining the native window title for system
  identity. Minimum usable sizes, saved window position, and lifecycle remain unchanged; fresh
  configuration windows now open at a 1280×700-point usable size, while existing v4, v5, and
  short-lived regular-unified v6 frames migrate to v7 without losing their usable size or top-edge
  position. Refresh remains the sole trailing titlebar action; the Trackpad Output switch now sits
  at the trailing edge of the bottom status bar beside the persistent readiness feedback.
- Kept the Left and Right trackpad editors visible together in equal columns at the
  wider default window size, with each pad preview and settings inspector also visible in
  columns and separated by whitespace instead of a rule. Pointer tracking, zone mode, and
  selected-area rows now carry icons and consistent trailing alignment; region headings have
  a deliberate native type ladder; every primary card and inset panel shares a 16-point content
  margin and 16-point sibling rhythm; compact tiles share a 12-point horizontal inset; redundant
  mode summaries have been removed from the pad-card headers; selected-zone outlines now retain a
  uniform white stroke along both internal dividers and rounded exterior pad edges; and status
  pills use uniform type, stronger side padding, and whole-pill wrapping at narrow widths and
  Accessibility text sizes.
  The status sequence is Access, Puck, Controller, Output, then Battery. Completed non-battery
  steps collapse to compact green icon pills, while incomplete states retain their text. Battery
  always retains its percentage and uses green at 60% or higher, amber from 20–59%, red below 20%,
  and a neutral unavailable state.
  The same mounted editor subtrees stack at genuinely narrow widths and Accessibility text sizes.
  Both configurations remain independent and every mapping behavior is unchanged. Wider restored
  windows use their available width, fixed trackpad maps are centered, and inset controls remain
  inside their card boundaries; document overflow scrolls without taking over the saved window
  height ([#77](https://github.com/zachspartofaday/Paddr/issues/77)).
- Added a pure readiness resolver with deterministic next-action guidance and output
  disabled reasons. The menu-bar item now announces output, controller, puck transport,
  and active-profile semantics. While a profile operation temporarily disables output, the
  guidance now asks the user to wait instead of advertising an unavailable enable action.
- Kept **Open Source Notices…** available in both packaged applications and supported
  `swift run Paddr` development launches. Packaged applications prefer the installed notice;
  source-checkout launches fall back to canonical `THIRD_PARTY_NOTICES.md` only from a validated
  checkout root.
- Superseded the 0.9.11 **Center tap radius** known issue ([#50](https://github.com/zachspartofaday/Paddr/issues/50)): Pointer mode can now track across the full pad while the radius continues to define the tap area. Each pad has a **Track pointer inside tap radius** switch for choosing full-pad tracking or the former coupled tracking dead zone. Fresh profile stores and newly created configurations use full-pad tracking; existing canonical and raw configurations preserve coupled behavior until changed, including the built-in Default synthesized for an existing canonical document. Duplicating Default preserves that source document’s behavior.
- Added the controller's passively reported battery percentage and charge state to a reserved **Battery** status pill and the native status menu, with stale battery state cleared whenever the active controller is lost or replaced ([#54](https://github.com/zachspartofaday/Paddr/issues/54)).
- Fixed the controller staying **Not found** on some pucks even though macOS saw the controller ([#52](https://github.com/zachspartofaday/Paddr/issues/52)). Paddr now listens on all four controller slots the puck exposes (USB interfaces 2–5) instead of a single heuristically chosen interface, accepts the shorter controller-state report variants some firmware emits instead of requiring exactly 54-byte reports, and reacts to the puck's explicit wireless connect/disconnect events so controller status updates immediately.
- The bottom-bar puck description now lists every opened puck interface and the observed report sizes, which makes future connectivity reports easier to diagnose.
- Paddr now requests **Input Monitoring** at first launch and surfaces its state ahead of Accessibility in the permissions row, the onboarding guide, and PaddrCLI — it is the grant that makes the controller visible at all, so it leads every permission surface. Without that grant macOS can withhold puck reports, which also presents as **Controller · Not found**.

## 0.9.11 — 2026-08-14

### Controller status and output

- Fixed the bottom controller status staying **Not found** until Trackpad Output was enabled ([#46](https://github.com/zachspartofaday/Paddr/issues/46) — thanks to [@redeemer666](https://github.com/redeemer666) for reporting it). Paddr now observes the controller continuously from launch, so controller presence is accurate while output is off.
- Split the bottom status into separate **Puck** and **Controller** indicators: **Puck Connected** comes from passive receiver discovery alone, and **Controller Connected** comes only from accepted live controller reports.
- Made the Trackpad Output toggle control mapped mouse, scroll, and keyboard emission only. Disabling output releases held keys and mouse buttons before **Output** reads **Idle** (via a brief **Releasing** state), keeps observing the controller, and re-enabling waits for neutral pads before arming.
- Kept the **Puck** indicator truthful when the receiver is visible but cannot be opened (for example while a permission is missing): passive discovery drives the indicator instead of the failed open.
- Detected puck hot-plug while output is off, including when Paddr starts with no puck attached.
- Because Paddr now opens the puck at launch rather than on first enable, any device-access prompt appears at first launch instead of when output is first enabled.

### Interface

- Moved **Save & Apply** and the saved-state indicator into the top profile card, and moved **Restore Defaults** into the profile actions menu. The bottom bar is now a stable status-only row, so it no longer reflows when statuses change.
- **Save & Apply** is enabled only while there are unsaved changes.

### Known issues

- In Pointer mode, **Center tap radius** currently doubles as a tracking dead zone: touch taps register only inside the radius, and pointer tracking responds only outside it, so the pad's center cannot move the pointer while a radius is set. A radius of 0% keeps taps and tracking available across the whole pad. Decoupling these — full-pad tracking with taps confined to the radius, as a togglable default — is planned ([#50](https://github.com/zachspartofaday/Paddr/issues/50)).

## 0.9.9 — 2026-08-13

### Profiles and setup

- Added named profiles for complete left- and right-pad configurations. Profiles can be created, duplicated, renamed, selected, and deleted from the configuration window, with quick switching between saved profiles from the status menu.
- Kept the built-in **Default** profile immutable: it always provides left Scroll and right Pointer, and it cannot be renamed, edited, or deleted. Duplicate it to create an editable profile.
- Existing configurations migrate automatically. An unchanged configuration selects Default, while customized settings become a **Previous configuration** profile; a failed migration leaves the original file intact.
- Protected unsaved work during profile changes. Window switching asks before discarding edits, and status-menu switching pauses until the draft is saved or explicitly discarded.
- Added a native four-step first-launch guide covering connection, Accessibility, pad setup, and everyday use. The guide can be reopened from Help or the status menu and does not request permission, enable output, or change a profile on its own.

### Trackpads and controller status

- Added an independent **Pointer acceleration** control for each pad, alongside the existing per-pad pointer and scroll sensitivity controls. The default of zero preserves the previous pointer response.
- Confirmed that both pads can use **Zones** at the same time, including independent layouts and bindings.
- Made **Controller Connected** reflect live controller reports rather than receiver presence alone. Turning off or losing the controller now releases held mapped keys and mouse buttons, marks the controller unavailable, and waits for neutral pad input before safely resuming after reconnect.
- Kept direct-launch use independent of Steam: Paddr does not require Steam, Steam Input, or Steam Overlay, so mapped trackpad input remains available to games launched normally.

### Interface

- Showed Paddr in the Dock and Command-Tab while the guide or configuration window is open, then returned it to menu-bar-only operation after both windows close.
- Refined the top card around profiles and status: profile controls remain in a stable location, selectors use a fixed width and stronger adaptive contrast, and Default presents a clear **Duplicate to Edit** path.
- Kept both expanded pad cards equal in height across their different modes, while preserving a compact collapsed layout and smooth profile switching without control flicker.

### Compatibility and validation notes

- macOS 27 Developer Beta 5 remains the confirmed environment. macOS 27 Public Beta 3 has been released and is likely compatible; public betas typically correspond to the preceding developer beta, but this specific build identity and Paddr compatibility have not yet been confirmed.
- Puck-connected Steam Controller 2 hardware using the tested receiver remains the confirmed connection. Bluetooth, direct USB, and the alternate receiver product remain unvalidated.
- Final attended coverage is still needed for pointer-acceleration feel; held outputs across controller loss, profile changes, sleep/wake, and reconnect; keyboard and VoiceOver navigation; the largest Zones layout; and a broader range of games and hardware.
- Paddr emits mouse, scroll, and keyboard events rather than native gamepad axes. Games that switch prompts according to the most recent input may alternate between controller and keyboard/mouse glyphs.

## 0.9 — 2026-08-12

Paddr 0.9 was the first Developer ID-signed, notarized, and stapled release.

- Reduced setup to one Accessibility grant for reading pad reports and emitting mapped input.
- Added independent per-pad scroll and pointer sensitivity, with matching command-line controls.
- Refined the compact two-card configuration window and its connection, output, and access status guidance.
- Improved everyday safety and reliability: quitting or losing a session releases held input, directional Zones follow the pressed direction, and delayed loads, saves, or device checks cannot replace newer user choices.
- Strengthened archive and checksum verification for the distributed app.

At the time of the 0.9 release, controller status tracked the receiver, only one pad was documented for Zones, and the configuration window did not appear in the Dock. Those limitations are superseded by 0.9.9.
