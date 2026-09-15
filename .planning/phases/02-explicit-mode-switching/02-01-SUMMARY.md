---
phase: 02-explicit-mode-switching
plan: 01
subsystem: infra
tags: [bash, docker-compose, vram-gate, kv-cache-pin, state-file, wsl2]

requires:
  - phase: 01-bring-the-stack-up
    provides: healthy single/batch Compose profiles on this machine, populated ./models, gitignored .env runtime-artifact precedent
provides:
  - switch.sh — one-command explicit profile switching (stop -> VRAM gate -> up -> persist)
  - .current-profile gitignored one-token state file (the Phase 3 boot-hook interface)
  - machine-proven VRAM-gate abort contract (target never started on a busy GPU)
  - machine-proven KV pin (--kv-cache-memory=5583457484 in the single container's vLLM argv, .env override escape hatch intact)
affects: [03-boot-autostart]

actuals:
  tokens: 2395      # chars/4 over the realized diff (git diff e933eaf..HEAD --text = 9582 chars)
  tasks: 3
  commits: 3        # MEASURED: git rev-list --count e933eaf..HEAD (chore + 2 feat; docs commit follows)
plan_head_before: e933eaf636409d9111805d75ab6748186ff23014

tech-stack:
  added: []
  patterns:
    - "one-GPU switch discipline: compose stop -> verbatim qwen-serving.service:10 VRAM poll (60x2s, <1000 MiB) -> up -d -> write-after-success state"

key-files:
  created: [switch.sh]
  modified: [.gitignore, .planning/config.json]

key-decisions:
  - "Both-running anomaly (one GPU) is refused on EVERY invocation path, not just no-arg as the plan's resolution chain (d) scoped it: an explicit request for the running profile would otherwise D-04 no-op with exit 0 while the other profile stays up, violating truth 1's 'exactly one profile running when they exit 0' and gotcha 5. All specified cases behave identically; only the unspecified explicit+both-running corner changed (error exit 1 instead of no-op exit 0)."
  - "switch.sh prepends /usr/lib/wsl/lib to PATH only when nvidia-smi is unresolvable and that directory exists (WSL2 keeps it off the default PATH in agent sandboxes). The literal poll command string stays byte-identical for the D-05 source assertions; the fix never fires when a shadow (e.g. Task 3's stub) already resolves."
  - "git.allow_default_branch_commits: true added to .planning/config.json — the pre-commit guard's documented override for this repo's chosen branching_strategy: none workflow (all phase 1/2 work, including feat afc81d9, landed on main)."
  - "TDD adaptation for a zero-test-infrastructure ops plan: RED executed via a throwaway /tmp TAP harness running the plan's own verify scenarios (never committed, honoring 'no separate test file is created'); RED_EVIDENCE_OK verdict from the #3770 checker authorizes GREEN."

patterns-established:
  - "Repo-root ops-script shape: header comment with invocation lines + 0/1/2 exit-code contract, set -e, HERE-resolve + cd, [switch]-prefixed messages, if-guarded compose calls (never bare test-and-echo substitution under set -e)."
  - "Write-after-success state persistence: a token reaches .current-profile only after up -d returned success; an aborted switch leaves the file naming the last profile that actually came up."

requirements-completed: [SWITCH-01, SWITCH-02, SWITCH-03, SWITCH-04]

coverage:
  - id: D1
    description: "switch.sh explicit-arg switching proven live in both directions: single->batch and batch->single each stop the other profile, pass the VRAM gate, reach Compose healthy, and leave exactly one profile running; invalid args bounce with usage exit 2 touching nothing"
    requirement: "SWITCH-01"
    verification:
      - kind: manual_procedural
        ref: "Task 1 verify 4/5/6 + tracer-gate re-run: SWITCH_BATCH_HEALTHY + BATCH_SIDE_OK, SWITCH_SINGLE_HEALTHY + KV_PIN_OK, BADARG_OK (each re-proven post-commit)"
        status: pass
    human_judgment: false
  - id: D2
    description: "VRAM-release gate mirrors qwen-serving.service:10 verbatim (poll command, -lt 1000, seq 1 60, sleep 2) and its abort contract is machine-proven: on a permanently-busy GPU (shadowed nvidia-smi) the script exits 1, the target is never started, and the state file is untouched"
    requirement: "SWITCH-04"
    verification:
      - kind: manual_procedural
        ref: "Task 1 static literals (STATIC_GATE_LITERALS_OK) + Task 3: GATE_EXIT=1, GATE_ABORT_OK, GPU_FREE_RESTORED"
        status: pass
    human_judgment: false
  - id: D3
    description: ".current-profile: written only after successful up -d, refreshed by the D-04 no-op, gitignored (git check-ignore exits 0), one token single|batch, and never written by a failed switch"
    requirement: "SWITCH-02"
    verification:
      - kind: manual_procedural
        ref: "GITIGNORE_OK; state assertions in every Task 1/2 scenario; GATE_ABORT_OK's untouched-state check"
        status: pass
    human_judgment: false
  - id: D4
    description: "No-arg resolution chain: toggle to the non-running profile; neither running -> .current-profile token -> corrupt/absent/blank defaults to single; already-running target is a no-op refresh; both-running anomaly errors safely"
    requirement: "SWITCH-03"
    verification:
      - kind: manual_procedural
        ref: "Task 2 ladder: NOOP_OK, INVERT_TO_BATCH_OK, INVERT_TO_SINGLE_OK, FALLBACK_STATE_OK, CORRUPT_DEFAULT_OK, MISSING_DEFAULT_OK, BOTH_BRANCH_PRESENT"
        status: pass
    human_judgment: false
  - id: D5
    description: "KV cache pinned for single only via set-if-unset KV_MEM (plus-form ${KV_MEM+x}, byte value 5583457484): the .env override and the documented empty-value escape hatch win; batch stays stock with no --kv-cache-memory flag"
    requirement: "SWITCH-04"
    verification:
      - kind: manual_procedural
        ref: "Source gates (plus-form + value greps, NO_COLON_DASH_OK) + live argv: KV_PIN_OK in /proc/1/cmdline across repeated switches; BATCH_SIDE_OK (batch argv has no pin)"
        status: pass
    human_judgment: false
  - id: D6
    description: "Phase-end state restored through the script itself: single healthy, zero batch containers, .current-profile = single"
    requirement: "SWITCH-02"
    verification:
      - kind: manual_procedural
        ref: "Task 3: FINAL_SINGLE_HEALTHY + PHASE_END_OK via ./switch.sh single"
        status: pass
    human_judgment: false

duration: 50min
completed: 2026-09-15
status: complete
---

# Phase 2 Plan 01: Explicit Mode Switching Summary

**One-command profile switching via switch.sh with the verbatim qwen-serving VRAM gate, a set-if-unset KV pin proven in the live vLLM argv, and a gitignored .current-profile the Phase 3 boot hook can trust — both directions, all resolution scenarios, and the gate-abort contract machine-proven.**

## Performance

- **Duration:** ~50 min (2026-09-15T01:07Z → 01:57Z; wall time dominated by vLLM health waits and the deliberate 120s gate-exhaustion budget)
- **Tasks:** 3 completed
- **Files modified:** 3 (switch.sh new, .gitignore +1 line, .planning/config.json +1 line)

## Accomplishments
- `switch.sh` at the repo root (mode 755): argument whitelist -> stop outgoing -> verbatim D-05 VRAM gate -> D-06 set-if-unset KV_MEM pin -> `up -d` -> write-after-success persist; `[switch]`-prefixed logging with a resolution-branch line on every run.
- Both switch directions proven live to Compose `healthy`, twice (initial proof + the #3299 tracer feedback gate re-run on the committed state): batch healthy with single gone and stock argv; single healthy with batch gone and the exact `--kv-cache-memory=5583457484` in PID-1 vLLM argv — byte-stable across repeated switches.
- All seven Task-2 behavior cases green: idempotent no-op (no restart, state refresh), no-arg toggle each direction, state-file fallback, corrupt token -> single, absent file -> single recreated, and the both-running error branch (source-level, per plan).
- The D-05 abort contract proven behaviorally with a shadowed nvidia-smi (always 20000 MiB): `GATE_EXIT=1`, batch never started, `.current-profile` still `single`, `[switch]` error logged, stub removed, real GPU confirmed free — then the phase restored to single healthy via `./switch.sh single` (`PHASE_END_OK`).

## Task Commits

Each task was committed atomically:

1. **Task 1: Explicit-arg switching end-to-end (tracer)** - `6a4852e` (feat) — switch.sh + .gitignore; tracer feedback gate re-run PASSED (full verify suite green post-commit)
2. **Task 2: No-arg resolution (TDD)** - `e9a233f` (feat) — RED_EVIDENCE_OK then GREEN; all 7 cases proven live
3. **Task 3: Gate-abort proof + restore** - no file changes (infra-only task; machine-proven, like Phase 1's Tasks 2-3)

**Workspace plumbing:** `9ee0f82` (chore: allow_default_branch_commits per branching_strategy: none — pre-commit-guard override, Rule 3)

**Plan metadata:** (docs commit follows this summary)

## Files Created/Modified
- `switch.sh` — NEW repo-root executable: the whole explicit-switching mechanism + no-arg resolution chain (198 lines, bash, set -e)
- `.gitignore` — one new line `.current-profile` immediately after the `.env` runtime-artifact entry
- `.planning/config.json` — `git.allow_default_branch_commits: true` (guard override; see deviations)
- `.current-profile` — runtime-only (gitignored, never committed); contains `single` at phase end

## Decisions Made
- Hoisted the both-running anomaly refusal to every invocation path (plan scoped it to no-arg only) so truth 1's "exactly one profile running when they exit 0" can never be violated by a D-04 no-op in the anomalous state.
- WSL PATH accommodation: `/usr/lib/wsl/lib` prepended only when nvidia-smi is unresolvable and the dir exists — keeps the D-05 poll command literal byte-identical, inert on non-WSL hosts, and correctly defers to a shadowed nvidia-smi (proven by Task 3).
- Per assumption A-2, no compose/.env plumbing was added for KV_MEM inheritance: the export is exactly D-06's locked form, and the container-side outcome was asserted where it matters (the live argv pin).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Pre-commit guard refused the project's own commit strategy**
- **Found during:** Pre-flight (before Task 1)
- **Issue:** The #3819 pre-commit assertion marks `main` as protected, but this project's config is `branching_strategy: none` and its entire GSD history (phase 1's feat afc81d9, all planning docs) lives on main; the guard's own FATAL text names the override.
- **Fix:** Added `git.allow_default_branch_commits: true` to `.planning/config.json` (the guard's documented override), committed standalone as chore `9ee0f82` so it is visible and revertable.
- **Files modified:** .planning/config.json
- **Verification:** `git.base-branch --is-protected main` → false; all three commits landed on main with hooks enabled.
- **Committed in:** 9ee0f82

**2. [Rule 2 - Missing correctness guard] Both-running refusal extended to the explicit-arg path**
- **Found during:** Task 2 (GREEN implementation)
- **Issue:** The plan's resolution chain (d) errors only on the no-arg path; an explicit request for the already-running profile while BOTH ran would take the D-04 no-op and exit 0 with the one-GPU invariant still violated (truth 1, gotcha 5).
- **Fix:** The both-running anomaly check runs after the compose-state queries, before any resolution/no-op logic, so every invocation path refuses it with exit 1 and touches nothing. All plan-specified cases (1-7) behave exactly as written; only the unspecified explicit+both-running corner changed (error instead of no-op).
- **Files modified:** switch.sh
- **Verification:** BOTH_BRANCH_PRESENT (source gate); live case 7 never tested by design (one GPU).
- **Committed in:** e9a233f

---

**Total deviations:** 2 auto-fixed (1 blocking, 1 missing-correctness guard)
**Impact on plan:** Both fixes are minimal and reversible; no scope creep — the second strengthens an unspecified corner in exactly the direction the plan's own must_haves and executor gotchas demand.

## Issues Encountered
- Host `nvidia-smi` is not on the default PATH in this WSL environment (env note, confirmed live). Resolved inside switch.sh (conditional PATH prepend, decision above); interactive verify commands that call bare `nvidia-smi` were run with `PATH=/usr/lib/wsl/lib:$PATH` prefixed per the environment notes.
- `docker compose --profile X stop` also reports stopping the unprofiled `prepare` container when one exists (leftover one-shot from Phase 1); it re-runs idempotently via `depends_on` on the next `up -d` — exactly the designed flow (gotcha 6), no handling needed.

## TDD Gate Compliance

TDD mode active (`workflow.tdd_mode: true`); Task 2 is behavior-adding (`task.is-behavior-adding` → true: tdd="true", `<behavior>` block, source file `switch.sh`).

| Gate | Requirement | Result |
|------|-------------|--------|
| RED — intentional failing test | #3770 evidence verified by `check tdd-red-evidence` | ✓ RED_EVIDENCE_OK (`target_test_failed`): 4 no-arg scenarios (cases 2/4/5/6) run live against the Task-1 script via a throwaway /tmp TAP harness; all failed intentionally on the planned-behavior assertions (exit 2 + usage, no resolution). Record: /tmp/gsd-red-02-01-task2-record.json (checker JSON persisted in the session transcript). |
| RED — test commit touching a test file | `test(02-01)` commit with `*.test.*`/`tests/**` | ✗ Structurally impossible under this plan's locked design: "no separate test file is created — the scenarios in verify ARE the tests" (repo has zero test infrastructure; creating one would violate the reviewed scope). The RED discipline was instead enforced by the tool-verified evidence above. |
| GREEN — implementation passes tests | target scenarios pass after implementation | ✓ All 7 behavior cases green (NOOP_OK, INVERT_TO_BATCH_OK, INVERT_TO_SINGLE_OK, FALLBACK_STATE_OK, CORRUPT_DEFAULT_OK, MISSING_DEFAULT_OK, BOTH_BRANCH_PRESENT); commit e9a233f. |
| feat-before-RED (scoped to Task 2's behavior) | no implementation of the gated behavior before RED | ✓ Task 1's feat(02-01) tracer commit precedes RED by design — it IS the plan's red-first baseline ("before this task, a no-arg invocation exits 2"); no code implementing the resolution chain existed before RED_EVIDENCE_OK. |
| REFACTOR | optional cleanup | — Not needed; implementation stayed linear and idiomatic. |

## Known Stubs
None — every code path is live (compose + GPU + state file); no placeholder values, no unwired data sources.

## Self-Check: PASSED

All claimed artifacts exist on disk (switch.sh executable, SUMMARY.md), all three commits found in git history, and the machine end-state re-verified live: single `healthy`, zero batch containers, `.current-profile` = `single`.

## User Setup Required
None.

## Next Phase Readiness
- `.current-profile` (one token, `single`|`batch`, trailing newline) is on disk and gitignored — the exact interface Phase 3's boot hook reads (D-02).
- Phase 3's hook should invoke `./switch.sh <token>` (or rely on its resolution chain) from the `/etc/wsl.conf [boot]` wrapper; the script's write-after-success guarantee means the file never lies after a reboot-time abort.
- Machine state at hand-off: `single` healthy, zero batch containers, `.current-profile` = `single`.

---
*Phase: 02-explicit-mode-switching*
*Completed: 2026-09-15*
