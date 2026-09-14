# Phase 2: Explicit Mode Switching - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-14
**Phase:** 2-explicit-mode-switching
**Areas discussed:** State file: location & format, VRAM-release gate semantics, KV cache pin mechanism & values, Already-running / idempotency behavior

---

## State file: location & format

| Option | Description | Selected |
|--------|-------------|----------|
| `.current-profile` at repo root | Plain text, one word, gitignored; adjacent to compose; trivial for Phase 3 | ✓ |
| `.state/profile` dir | More structure, more moving parts | |
| `~/.config/qwen-3090/profile` | Outside repo; survives moves but invisible to repo | |
| You decide | Let planner choose | |

**User's choice:** `.current-profile` at repo root
**Notes:** Absent/blank/corrupt => `single` (SWITCH-03).

---

## VRAM-release gate semantics

| Option | Description | Selected |
|--------|-------------|----------|
| Mirror the service exactly | `memory.used < 1000` MB, 2s, 60 tries, then abort | ✓ |
| Same loop, warn-and-proceed | Start anyway on timeout with a warning | |
| Wait for container removal too | Poll until container stopped AND VRAM free | |
| You decide | Pick the safest variant | |

**User's choice:** Mirror the service exactly (abort on timeout, target not started)
**Notes:** Identical to `single-user/qwen-serving.service:10`.

---

## KV cache pin mechanism & values

| Option | Description | Selected |
|--------|-------------|----------|
| `KV_MEM` for `single` only | Reuse existing `KV_MEM` -> `--kv-cache-memory` mapping | ✓ |
| Pin both profiles | Add `KV_MEM` plumbing to `batch/start_qwen.sh` | |
| Write `KV_MEM` into `.env` | Static, profile-independent pin | |
| You decide | Let planner choose | |

**User's choice:** `KV_MEM` for `single` only
**Notes:** `batch` stays stock (`KV=fp8` + `GPU_UTIL`); revisit only if unstable.

---

## Already-running / idempotency behavior

| Option | Description | Selected |
|--------|-------------|----------|
| No-op + persist, exit 0 | Refresh state file, do not restart | ✓ |
| Force restart | Guarantees clean KV pool at reload cost | |
| Error out | Non-zero, user must stop first | |
| You decide | Let planner choose | |

**User's choice:** No-op + persist, exit 0
**Notes:** Matches the BOOT-03 idempotency convention.

---

## CLI no-argument behavior (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| No-arg defaults to single | `switch.sh` acts on `single` | |
| Require explicit profile | Usage error without `single`/`batch` | |
| Toggle to non-running profile | Switch to whichever profile is not running | ✓ |

**User's choice (free text):** "if no profile specified, switch should switch to the non-running profile. if nothing is running and current state is missing/blank/corrupt, default to single."
**Notes:** Fallback chain: non-running profile -> persisted `.current-profile` -> `single`.

---

## KV value source (follow-up)

| Option | Description | Selected |
|--------|-------------|----------|
| Default + honor `.env` override | Export `KV_MEM=5583457484` only when unset | ✓ |
| Hardcode, ignore `.env` | Maximally deterministic, no escape hatch | |
| Use `5261334938` (CTX=huge) | Only correct if `single` runs CTX=huge (D-04 did not set CTX) | |

**User's choice:** Default + honor `.env` override
**Notes:** `single-user/start_qwen.sh:433` consumes `KV_MEM`.

---

## the agent's Discretion

- Exit codes and messages, `stop` vs `down` for the outgoing profile, running-profile detection, usage text, `.gitignore` entry for `.current-profile`.

## Deferred Ideas

- `switch.sh status` / `current` subcommand — not required by SWITCH-01..04.
- KV pin for the `batch` profile — intentionally left stock this phase.
