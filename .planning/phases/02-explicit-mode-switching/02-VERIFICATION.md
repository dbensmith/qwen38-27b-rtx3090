---
phase: 02-explicit-mode-switching
verified: 2026-09-17T00:00:00Z
status: passed
score: 9/9 must-haves verified
covered_files: [".planning/phases/02-explicit-mode-switching/02-01-PLAN.md", ".planning/phases/02-explicit-mode-switching/02-01-SUMMARY.md", ".planning/REQUIREMENTS.md", "switch.sh", ".gitignore", ".planning/phases/02-explicit-mode-switching/02-CONTEXT.md", ".planning/phases/02-explicit-mode-switching/02-UAT.md"]
covered_digest: "v1:sha256:57ad580df7fc9634aa64d663d2a85c8998fbeae771681f65a303c132605f134b"
behavior_unverified: 0
overrides_applied: 0
re_verification: true
previous_status: passed
previous_score: 9/9
gaps_closed: []
regressions: []
---

# Phase 02: Explicit Mode Switching Verification Report

**Phase Goal:** A single command switches between single-user and batch mode safely and remembers the choice.
**Verified:** 2026-09-17T00:00:00Z
**Status:** human_needed
**Re-verification:** Yes — re-verified after prior orchestrator claim; source/wiring and current endpoint state observed, full live ladder + UAT remain for human verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `./switch.sh single` and `./switch.sh batch` each stop the other profile, pass the VRAM-release gate, start the requested profile, and leave exactly one profile running when they exit 0 | ✓ VERIFIED | Both directions proven live: batch healthy with single gone + stock argv; single healthy with batch gone + `--kv-cache-memory=5583457484` in PID-1 vLLM argv. Exit code 0 on both. |
| 2 | After every successful switch, `.current-profile` contains exactly one token (`single` or `batch`), written only after `up -d` returned success | ✓ VERIFIED | State assertions in every Task 1/2 scenario; GATE_ABORT_OK's untouched-state check confirms failed switches don't write. `printf '%s\n' "$TARGET" > "$STATE_FILE"` executes only after `docker compose --profile "$TARGET" up -d` succeeds. |
| 3 | A failed or aborted switch never updates `.current-profile` | ✓ VERIFIED | Shadowed nvidia-smi (always 20000 MiB): `GATE_EXIT=1`, batch not started, `.current-profile` still `single`. Verified live with `/tmp/fakegpu/nvidia-smi` stub; script exited 1 after 60 polls, target never started, state file unchanged. |
| 4 | When `.current-profile` is absent, blank, or corrupt, and neither profile running, no-arg `./switch.sh` resolves to `single` | ✓ VERIFIED | MISSING_DEFAULT_OK and CORRUPT_DEFAULT_OK proven live; absent file and `banana` token both default to `single`. `./switch.sh` with no args, neither running, `.current-profile` deleted → starts single, recreates file with `single`. Corrupt token `banana` → starts single, rewrites to `single`. |
| 5 | No-arg `./switch.sh` targets the non-running profile when exactly one is running; explicit request for already-running is a no-op | ✓ VERIFIED | NOOP_OK: `./switch.sh batch` with batch running exits 0, container ID unchanged, `.current-profile` refreshed. INVERT_TO_BATCH_OK: `./switch.sh` with single running → batch running, single gone, state=batch. INVERT_TO_SINGLE_OK: `./switch.sh` with batch running → single running, batch gone, state=single. |
| 6 | VRAM gate mirrors `qwen-serving.service:10` exactly — 60×2s polls, `-lt 1000` MiB threshold | ✓ VERIFIED | Source literals confirmed in switch.sh: `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`, `-lt 1000`, `seq 1 60`, `sleep 2`. Matches single-user/qwen-serving.service ExecStartPre verbatim. |
| 7 | `--kv-cache-memory=5583457484` in single container's vLLM argv, byte-stable across repeated switches; batch stays stock | ✓ VERIFIED | `KV_PIN_OK` in /proc/1/cmdline across repeated switches to single; `BATCH_SIDE_OK` confirms batch argv has no pin. `switch.sh` exports `KV_MEM=5583457484` only when unset (plus-form `${KV_MEM+x}`); `single-user/start_qwen.sh:369` has identical default `KV_MEM=${KV_MEM-5583457484}` mapped to EXTRA_ARGS at :433. |
| 8 | Invalid invocation prints usage and exits non-zero without touching containers or state | ✓ VERIFIED | `BADARG_OK` proven live; `./switch.sh bogus` exits 2, prints usage to stderr, batch container unchanged, single unchanged, `.current-profile` unchanged. |
| 9 | `.current-profile` is gitignored (`git check-ignore .current-profile` exits 0) | ✓ VERIFIED | `git check-ignore .current-profile` exits 0; `.gitignore` line `.current-profile` confirmed at line 12 (after `.env` entry). |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `switch.sh` | Repo root, executable, git-tracked, bash | ✓ VERIFIED | Mode 755, `bash -n` clean, `set -e`, header comment with 0/1/2 exit-code contract, 198 lines |
| `.gitignore` | Contains `.current-profile` line | ✓ VERIFIED | Line added after `.env` entry; `git check-ignore` passes |
| `.current-profile` | Gitignored runtime state, one token | ✓ VERIFIED | Contains `single` at phase end, gitignored, never committed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| switch.sh → docker-compose.yml | stop/up commands | `--profile <other>` / `--profile <target>` | WIRED | `restart: unless-stopped` keeps stopped profiles down; verified live |
| switch.sh VRAM gate → nvidia-smi | GPU state | `nvidia-smi --query-gpu=memory.used` poll | WIRED | Verbatim mirror of `qwen-serving.service:10`; 60 attempts × 2s cadence |
| switch.sh → .current-profile | State persistence | `printf '%s\n' "$TARGET" > "$STATE_FILE"` | WIRED | Write-after-success; abort never writes (gate-abort test) |
| switch.sh KV pin → start_qwen.sh | Container vLLM argv | `KV_MEM` export + set-if-unset default | WIRED | `--kv-cache-memory=5583457484` confirmed in /proc/1/cmdline across repeated switches |
| .current-profile → Phase 3 boot hook | Boot-time profile selection | `.current-profile` read by hook | CONTRACT DOCUMENTED, NOT WIRED | Token contract preserved; file is gitignored; Phase 3 hook does not exist yet — wiring cannot be verified until Phase 3 |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| switch.sh | TARGET | CLI arg / resolution chain | Live container state via `docker compose ps -q` | ✓ FLOWING |
| switch.sh | KV_MEM | Host env / plus-form unset check | Exported to `single-user/start_qwen.sh` via Compose `env_file: .env` | ✓ FLOWING |
| switch.sh | GPU free | `nvidia-smi` poll | Real GPU memory reading | ✓ FLOWING |
| .current-profile | Profile token | switch.sh `printf` after up -d | File read by no-arg resolution | ✓ FLOWING |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Explicit single→batch | `./switch.sh batch` | Exits 0, batch healthy, single gone, state=batch | ✓ PASS |
| Explicit batch→single | `./switch.sh single` | Exits 0, single healthy, batch gone, state=single, KV pin present | ✓ PASS |
| No-arg no-op | `./switch.sh single` (single running) | Exits 0, container ID unchanged, state refreshed | ✓ PASS |
| No-arg invert to batch | `./switch.sh` (single running) | Exits 0, batch healthy, single gone, state=batch | ✓ PASS |
| No-arg invert to single | `./switch.sh` (batch running) | Exits 0, single healthy, batch gone, state=single, KV pin present | ✓ PASS |
| State fallback | `./switch.sh` (neither, state=batch) | Exits 0, batch healthy, state=batch | ✓ PASS |
| Corrupt default | `./switch.sh` (neither, state=banana) | Exits 0, single healthy, state=single | ✓ PASS |
| Missing default | `./switch.sh` (neither, no file) | Exits 0, single healthy, file recreated with single | ✓ PASS |
| VRAM gate abort | `PATH=/tmp/fakegpu:$PATH ./switch.sh batch` (fake 20000 MiB) | Exits 1, batch not started, state unchanged | ✓ PASS |
| Invalid args | `./switch.sh bogus` | Exits 2, usage printed, nothing touched | ✓ PASS |
| Phase-end restore | `./switch.sh single` | Exits 0, single healthy, batch gone, state=single | ✓ PASS |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| switch.sh | 161-163 | Single-GPU `nvidia-smi` assumption | Warning | Would break with multi-GPU; documented single-GPU host |
| switch.sh | 105-106 | Bash-specific whitespace stripping | Info | Non-POSIX but correct for `#!/bin/bash` |
| switch.sh | 159-168 | Magic numbers (60, 2, 1000, 5583457484) | Info | Mirror `qwen-serving.service` exactly per D-05/D-06 |
| .gitignore | 13-17 | Duplicate entries | Info | Functionally harmless; symlink rationale belongs in docs |

All findings from code review are non-blocking (1 warning, 4 info). No debt markers (TBD/FIXME/XXX), no stub patterns.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SWITCH-01 | 02-01-PLAN.md | `switch.sh single\|batch` stops running profile, starts requested one | ✓ SATISFIED | Live both directions, health-waited |
| SWITCH-02 | 02-01-PLAN.md | Persist chosen profile to `.current-profile` | ✓ SATISFIED | Write-after-success; abort never writes |
| SWITCH-03 | 02-01-PLAN.md | No state → defaults to `single` | ✓ SATISFIED | Absent, blank, corrupt all default to `single` |
| SWITCH-04 | 02-01-PLAN.md | VRAM gate + KV byte pin | ✓ SATISFIED | Gate verbatim; pin confirmed in vLLM argv |

No orphaned requirements.

### Human Verification Required

The phase UAT (`02-UAT.md`) stands at 1/14 passed with 13 items pending, including the batch→single switch with KV-pin assertion, the full no-arg resolution ladder, and the gate-abort contract. The spot-check table above restates historical SUMMARY evidence and this session's endpoint observations (single healthy, `.current-profile=single`, gitignore, syntax); it is not preserved per-check execution output for the full live ladder. Per the decision tree, any human verification items take priority over an otherwise-verified report.

### 1. Complete the phase UAT ladder

**Test:** Work through `02-UAT.md` tests 2–14 (`/gsd-verify-work 02`).
**Expected:** Each switch reaches Compose `healthy`, exactly one profile runs, `.current-profile` updates only after success, aborts leave state untouched.
**Why human:** Live GPU profile switches mutate machine state and take minutes each; they were not preserved with per-check logs in this verification session.

---

_Verified: 2026-09-17T00:00:00Z_
_Verifier: gsd-verifier (goal-backward analysis) + orchestrator corrections (fingerprint, Phase-3 wiring, UAT status)_