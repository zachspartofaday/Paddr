# Kickoff — Paddr audit remediation via /limitless-orchestrate

Consume this document in a fresh session to remediate the open findings from
`docs/audits/2026-08-11-paddr-pr1-refinement-audit.md`. Treat this file as byte-stable once the
session starts; corrections belong in the audit doc or the PR, not here.

## Session prompt

Invoke `limitless-orchestrate` for the repository at `~/Coding/PuckPads`
(GitHub `zachspartofaday/Paddr`), base branch `codex/ui-refinement` (PR #1) — or `main` if PR #1
has merged by then. The task set is the four phases below; phases R1 and R2 are
correctness-critical and take the judgment worker tier (worker-sol-deep, or worker-opus-deep for
a large integrated slice); R3 and R4 are decided-shape work suitable for the mechanical tier
(worker-luna-mech) once the owning judgment worker has fixed the shape. Workers operate in
isolated worktrees off the base branch with the validation gate below; one PR per phase (or one
combined PR for R3+R4 if small), each PR reviewed before merge.

## Fix list (IDs, evidence, and fix directions live in the audit doc — read it first)

- **Phase R1 — teardown and session-boundary correctness**
  - PUA-001 (High): independent per-output release attempts, explicit mouse-up creation failure,
    propagated aggregate cleanup failure; no clean `.deviceRemoved` while holds may remain.
    Closes the PPA-002 partial closure.
  - PUA-002 (Medium): make generation validation and continuation enqueue one serialized
    operation (or tag-validate at delivery inside the session actor).
  - Both must land with tests that fail if the fix reverts (see PUA-005's required stream-empty
    assertion — implement together).
- **Phase R2 — radial keyboard navigation**
  - PUA-010 (Medium): explicit directional transitions (or axis-alignment-first ranking) for
    `.radialFour`; per-direction tests for every layout, folded into the PUA-004 rework.
- **Phase R3 — test hardening**
  - PUA-004: zone-binding tests assert concrete `dpadKeys`/`gridKeys` fields and mapper output.
  - PUA-005: superseded-stream tests assert the old stream is exactly empty across connection,
    progress, and terminal branches.
  - PUA-006: isolated legacy-directory cases, explicit precedence, and old-schema JSON fixtures.
  - PUA-007: `stopCount == 2` exact assertion.
- **Phase R4 — polish/modernization**
  - PUA-003: async off-main-actor configuration I/O and controller probing dependencies.
  - PUA-008: NUL-safe file list in `scripts/check-localization.sh`.
  - PUA-011: suppress animated `setFrame` under Reduce Motion.
  - PUA-012: replace GeometryReader preference probes with `onGeometryChange` (behavior-neutral;
    re-verify the PUA-013 stability probe afterwards — window frame must stay fixed across an
    enable→disable cycle and slider drags).

## Constraints (from CONTRIBUTING.md and the audit)

- Behavioral tests must pin the change: reverting a fix fails at least one test. Never weaken an
  existing assertion to go green; sweep the phase diff for weakened expectations before review.
- Controller removal must release every held key and mouse button; lifecycle changes preserve the
  one-worker invariant and reject stale events; stored-value changes account for
  `~/.config/Paddr/config.json` and the documented legacy migrations.
- UI stays keyboard-operable, system-text-styled, catalog-localized, accessibility-labeled.
- Do not re-raise the verified-clean notes recorded in the audit doc.

## Validation gate (per worker, and once on the integrated head)

```bash
export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
swift test -Xswiftc -warnings-as-errors
scripts/check-localization.sh
swift build -c release -Xswiftc -warnings-as-errors --arch arm64
```

Serialize full `swift test` runs across concurrent workers (shared machine). If packaging or
scripts are touched, additionally run `scripts/test-cli.sh` against the release CLI build and
`scripts/test-release-package.sh`. Baseline at kickoff: 45 + 36 tests, 0 failures.

## Closeout

Append accepted/deferred/rejected dispositions per finding to the audit doc's finding sections
(the PR's established remediation-evidence pattern), update the PR body's validation section, and
leave the physical unplug/replug matrix, assistive-technology matrix, light-appearance runtime
check (PUA-009 residual), and notarization explicitly listed as remaining manual gates.
