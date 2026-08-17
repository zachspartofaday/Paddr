# Changelog

User-visible changes to Paddr are recorded here. Release entries describe confirmed behavior at the time of each release; later entries may supersede earlier limitations.

## 0.10.1 — 2026-08-17

Paddr 0.10.1 makes controller setup more dependable, pointer tracking more natural, and the configuration window easier to understand at a glance.

### More dependable controller setup

- Paddr now asks for **Input Monitoring** first, before Accessibility. This is the permission macOS needs to make the puck's controller reports available at all.
- Controller discovery works across every controller interface exposed by the puck, accepts the shorter report variants used by some firmware, and responds immediately to wireless connect/disconnect events.
- The status bar now separates **Puck**, **Controller**, **Battery**, **Output**, and **Access**, so each status describes one thing clearly. Battery percentage and charge state are also available from the native status menu.
- The puck diagnostic description lists every opened interface and observed report size, making connection problems easier to diagnose.

### Pointer behavior that feels right

- Pointer mode can now track across the full pad while **Center tap radius** continues to limit touch taps. Each pad has a **Track pointer inside tap radius** switch for restoring the former coupled behavior when needed.
- New profiles use full-pad pointer tracking by default. Existing configuration files preserve their previous behavior until you change the setting.
- Pointer tracking, scrolling, touch taps, and Zones continue to work independently on the left and right pads.

### Safer everyday use

- Turning output off releases held keyboard keys and mouse buttons before the interface reports **Idle**.
- If the controller disconnects, Paddr releases mapped input and waits for neutral pad input before resuming after reconnect.
- The first-launch guide now explains connection, permissions, pad setup, and everyday use without changing a profile or enabling output on its own.

### A clearer native interface

- Profile actions, save state, and connection status now have a more consistent hierarchy.
- Pad surfaces, status cards, permission tiles, and Zone maps use a unified adaptive appearance with stronger accessibility contrast and more predictable sizing.
- The configuration window and onboarding guide retain their established pad appearance while fitting compact windows and larger text more reliably.

### Compatibility

- Confirmed environment: macOS 27 Developer Beta 5 or later with a puck-connected Steam Controller 2.
- Bluetooth, direct USB, and alternate receiver hardware remain unvalidated.
- Paddr emits standard mouse, scroll, and keyboard events; it does not replace native controller axes or require Steam Input.

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
