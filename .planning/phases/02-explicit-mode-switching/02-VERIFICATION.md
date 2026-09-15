---
phase: 02-explicit-mode-switching
verified: 2026-09-15T02:16:00Z
status: passed
score: 9/9 must-haves verified
covered_files: ["switch.sh", ".gitignore", ".current-profile"]
covered_digest: "v1:sha256:32f909ed1e546605c1225fde15bdf3871202286e40daca5a4b597102cd8c358e"
behavior_unverified: 0
overrides_applied: 0
re_verification: false
---

# Phase 02: Explicit Mode Switching Verification Report

**Phase Goal:** A single command switches between single-user and batch mode safely and remembers the choice.
**Verified:** 2026-09-15T02:16:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `./switch.sh single` and `./switch.sh batch` each stop the other profile, pass the VRAM-release gate, start the requested profile, and leave exactly one profile running when they exit 0 | ✓ VERIFIED | Both directions proven live: batch healthy with single gone + stock argv; single healthy with batch gone + `--kv-cache-memory=5583457484` in PID-1 vLLM argv |
| 2 | After every successful switch, `.current-profile` contains exactly one token (`single` or `batch`), written only after `up -d` returned success | ✓ VERIFIED | State assertions in every Task 1/2 scenario; GATE_ABORT_OK's untouched-state check confirms failed switches don't write |
| 3 | A failed or aborted switch never updates `.current-profile` | ✓ VERIFIED | Shadowed nvidia-smi (always 20000 MiB): `GATE_EXIT=1`, batch not started, `.current-profile` still `single` |
| 4 | When `.current-profile` is absent, blank, or corrupt, and neither profile running, no-arg `./switch.sh` resolves to `single` | ✓ VERIFIED | MISSING_DEFAULT_OK and CORRUPT_DEFAULT_OK proven live; absent file and `banana` token both default to `single` |
| 5 | No-arg `./switch.sh` targets the non-running profile when exactly one is running; explicit request for already-running is a no-op | ✓ VERIFIED | NOOP_OK, INVERT_TO_BATCH_OK, INVERT_TO_SINGLE_OK all proven live |
| 6 | VRAM gate mirrors `qwen-serving.service:10` exactly — 60×2s polls, `-lt 1000` MiB threshold | ✓ VERIFIED | Source literals confirmed: `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`, `-lt 1000`, `seq 1 60`, `sleep 2` |
| 7 | `--kv-cache-memory=5583457484` in single container's vLLM argv, byte-stable across repeated switches; batch stays stock | ✓ VERIFIED | `KV_PIN_OK` in /proc/1/cmdline across repeated switches; `BATCH_SIDE_OK` confirms batch argv has no pin |
| 8 | Invalid invocation prints usage and exits non-zero without touching containers or state | ✓ VERIFIED | `BADARG_OK` proven live; switch.sh exits 2 for unknown tokens |
| 9 | `.current-profile` is gitignored (`git check-ignore .current-profile` exits 0) | ✓ VERIFIED | `git check-ignore .current-profile` exits 0; `.gitignore` line confirmed |

**Score:** 9/9 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `switch.sh` | Repo root, executable, git-tracked, bash | ✓ VERIFIED | Mode 755, `bash -n` clean, `set -e`, header comment with 0/1/2 exit-code contract |
| `.gitignore` | Contains `.current-profile` line | ✓ VERIFIED | Line added after `.env` entry; `git check-ignore` passes |
| `.current-profile` | Gitignored runtime state, one token | ✓ VERIFIED | Contains `single`, gitignored, never committed |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| switch.sh → docker-compose.yml | stop/up commands | `--profile <other>` / `--profile <target>` | WIRED | `restart: unless-stopped` keeps stopped profiles down |
| switch.sh VRAM gate → nvidia-smi | GPU state | `nvidia-smi --query-gpu=memory.used` poll | WIRED | Verbatim mirror of `qwen-serving.service:10` |
| switch.sh → .current-profile | State persistence | `printf '%s\n' "$TARGET" > "$STATE_FILE"` | WIRED | Write-after-success; abort never writes |
| switch.sh KV pin → start_qwen.sh | Container vLLM argv | `KV_MEM` export + set-if-unset default | WIRED | `--kv-cache-memory=5583457484` confirmed in /proc/1/cmdline |
| .current-profile → Phase 3 boot hook | Boot-time profile selection | `.current-profile` read by hook | WIRED | Token contract preserved; file is gitignored |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| switch.sh | 161-163 | Single-GPU `nvidia-smi` assumption | Warning | Would break with multi-GPU; documented single-GPU host |
| switch.sh | 105-106 | Bash-specific whitespace stripping | Info | Non-POSIX but correct for `#!/bin/bash` |
| switch.sh | 159-168 | Magic numbers (60, 2, 1000, 5583457484) | Info | Mirror `qwen-serving.service` exactly per D-05/D-06 |
| .gitignore | 13-17 | Duplicate entries | Info | Functionally harmless; symlink rationale belongs in docs |

All findings from code review are non-blocking (1 warning, 4 info).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SWITCH-01 | 02-01-PLAN.md | `switch.sh single\|batch` stops running profile, starts requested one | ✓ SATISFIED | Live both directions, health-waited |
| SWITCH-02 | 02-01-PLAN.md | Persist chosen profile to `.current-profile` | ✓ SATISFIED | Write-after-success; abort never writes |
| SWITCH-03 | 02-01-PLAN.md | No state → defaults to `single` | ✓ SATISFIED | Absent, blank, corrupt all default to `single` |
| SWITCH-04 | 02-01-PLAN.md | VRAM gate + KV byte pin | ✓ SATISFIED | Gate verbatim; pin confirmed in vLLM argv |

No orphaned requirements.

---

_Verified: 2026-09-15T02:16:00Z_
_Verifier: orchestrator (inline verification per user instruction to use only OpenCode Zen Free models)_
