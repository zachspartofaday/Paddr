## Summary

<!-- What changed, and why? Keep this focused on one coherent outcome. -->

## Validation

- [ ] `swift test -Xswiftc -warnings-as-errors`
- [ ] `scripts/check-localization.sh`
- [ ] arm64 release build with warnings as errors
- [ ] Relevant manual controller/UI checks described below

Manual checks:

<!-- Include macOS build, connection path, relevant mappings, and anything not tested. -->

## Safety and compatibility

- [ ] No credentials, signing material, serial numbers, private IOHID paths, or unredacted captures are included.
- [ ] Existing configuration files remain compatible or include a migration.
- [ ] Controller disconnect and cancellation paths release held output where applicable.
- [ ] User-facing behavior or workflow changes include documentation updates.
