# Contributing to Paddr

Bug reports, compatibility notes, documentation improvements, and focused pull requests are welcome. Paddr sits on top of controller support that first appeared in a macOS beta, so the most useful contributions explain the exact environment and behavior they exercised.

## Before you start

Small fixes and documentation changes can go straight to a pull request. For a larger feature, a stored-configuration change, or work that touches controller I/O, please open an issue first. That gives us a chance to agree on scope and avoid asking you to rework hardware-sensitive code after the fact.

Keep one coherent change together. A fix may need several files; that is still one change. Avoid parallel pull requests that redesign the same runtime, configuration, or SwiftUI surface.

## What to include in a report

For controller or compatibility bugs, include:

- the macOS version and build;
- whether the controller is connected through the puck, Bluetooth, or USB;
- the Paddr version and whether it is ad-hoc signed, Developer ID signed, or locally built;
- the trackpad mode and relevant bindings; and
- concise steps that reproduce the problem.

Remove controller serial numbers, local IOHID paths, private filesystem paths, signing details, and account information. Do not attach raw hardware captures unless they have been deliberately redacted.

Permission behavior depends on the app's bundle identity, path, and signature. If macOS requested Input Monitoring or Accessibility again after an update, mention whether the app moved and how both builds were signed.

## Quality bar

Behavioral tests should pin the behavior being changed: reverting the fix should make at least one test fail. Prefer the existing runtime, session, configuration, and app-support seams over adding a parallel abstraction. When a stored value changes, account for existing `~/.config/Paddr/config.json` files and the documented legacy migration paths.

Controller removal must release every held key and mouse button. Lifecycle changes must preserve the one-worker invariant and reject stale events. UI changes must remain keyboard-operable, expose meaningful native accessibility semantics, use system text styles, and keep known user-facing text in the String Catalog.

## Development

Paddr requires Xcode 27 beta and keeps macOS 26.0 as its deployment target. Distribution is arm64-only.

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test -Xswiftc -warnings-as-errors
scripts/check-localization.sh
swift build -c release -Xswiftc -warnings-as-errors --arch arm64
swift build -c release -Xswiftc -warnings-as-errors --arch arm64 --product PaddrCLI
scripts/test-cli.sh "$(swift build -c release --arch arm64 --show-bin-path)/PaddrCLI"
```

To assemble a local ad-hoc app without touching the repository's `dist` directory:

```bash
OUTPUT_DIR="$(mktemp -d)/output" \
BUILD_SCRATCH_PATH="$(mktemp -d)/build" \
scripts/build-app.sh
```

If your change affects a physical launch path, say what you tested manually. Useful checks include pointer movement, scroll, keyboard and mouse-button zones, touch taps, permission refresh, closing and reopening the configuration window, and puck unplug/replug while an output is held.

## Pull requests

Before opening a pull request:

- run the test, localization, and release-build commands above;
- keep generated build products, credentials, certificates, private keys, and unredacted captures out of the repository;
- update README or contributor documentation when behavior or workflow changes; and
- describe anything you could not test directly, especially physical-controller and assistive-technology behavior.

The repository does not publish, notarize, or upload artifacts from contributor pull requests. Never run release publication against this project unless the maintainer has explicitly coordinated it.

## Brand assets

`Assets/PaddrIcon.png` is the single source of truth for the app icon. Regenerate the checked-in AppIcon renditions after changing it:

```bash
scripts/generate-app-icon.sh
```

The generator requires a square PNG at least 1024 pixels wide and writes only the filenames declared by the AppIcon catalog.

`@zachspartofaday` is the code owner and sole merge authority. Community review is welcome, but only the maintainer approves and merges changes.

Thanks for helping make an intentionally fast beta experiment safer and more useful.
