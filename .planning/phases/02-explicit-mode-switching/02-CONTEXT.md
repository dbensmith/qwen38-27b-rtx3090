# Phase 2: Explicit Mode Switching - Context

**Gathered:** 2026-09-14
**Status:** Ready for planning

<domain>
## Phase Boundary

Deliver a single repo-root `switch.sh` command that explicitly switches this single-GPU stack between the `single` and `batch` Compose profiles: stop the currently-running profile, wait for its VRAM to actually free, start the requested profile with a stably-pinned KV cache for `single`, and persist the chosen profile to a state file that the Phase 3 boot hook will read. Covers SWITCH-01 through SWITCH-04.

Not in scope: the WSL boot hook itself (Phase 3), running both profiles concurrently (one GPU), systemd units, any new tuning of the `batch` profile.

</domain>

<decisions>
## Implementation Decisions

### State file & persistence
- **D-01:** The persisted choice lives in `.current-profile` at the repo root — plain text, a single token `single` or `batch`, gitignored (add to `.gitignore`). When the file is absent, blank, or corrupt, the effective profile is `single` (SWITCH-03).
- **D-02:** `switch.sh` writes the chosen profile to `.current-profile` after every successful switch (SWITCH-02). This file is the interface the Phase 3 boot hook reads.

### switch.sh interface
- **D-03:** `switch.sh [single|batch]`. With an explicit argument, switch to that profile. With **no argument**, switch to the non-running profile; if neither profile is running, fall back to `.current-profile`; if that is missing/blank/corrupt, use `single`.
- **D-04:** Idempotency — if the requested profile is already the running one, do not restart it: refresh `.current-profile` and exit 0 (SWITCH-01 no-op; consistent with the BOOT-03 idempotency convention). — **Reversibility:** reversible — behavior is local to the script.

### VRAM release gate
- **D-05:** Mirror `single-user/qwen-serving.service:10` exactly — poll `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits` every 2s for up to 60 attempts and require `< 1000` MB before starting the new profile. On timeout, abort the switch with a non-zero exit and the target profile **not** started (SWITCH-04).

### KV cache pin
- **D-06:** Pin `--kv-cache-memory` for the `single` profile only, via the existing `KV_MEM` env: `switch.sh` exports `KV_MEM=5583457484` **only when `KV_MEM` is unset**, so a user override in `.env` still wins. `single-user/start_qwen.sh` already maps `KV_MEM` to `EXTRA_ARGS="--kv-cache-memory=$KV_MEM ..."` — no new plumbing. `batch` stays stock (`KV=fp8` + `GPU_UTIL` sizing; `batch/start_qwen.sh` has no `KV_MEM` support) (SWITCH-04).

### Stop/start mechanics
- **D-07:** Stop the outgoing profile with `docker compose --profile <other> stop`, then wait for VRAM to free (D-05), then `docker compose --profile <target> up -d`. `restart: unless-stopped` keeps an explicitly-stopped container down.

### the agent's Discretion
- Exact exit codes and messages, `set -euo pipefail` usage, `stop` vs `down` for the outgoing profile, how the running profile is detected (`docker compose ps` parsing), usage/`--help` text, and the `.gitignore` entry for `.current-profile`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Switching requirements & project decisions
- `.planning/REQUIREMENTS.md` — SWITCH-01..04 (authoritative acceptance language)
- `.planning/PROJECT.md` — Key Decisions (explicit `switch.sh`, persisted choice, `single` default) and Constraints (one GPU, no systemd)
- `.planning/ROADMAP.md` §"Phase 2: Explicit Mode Switching" — goal and success criteria

### Existing GPU-free / KV patterns to mirror
- `single-user/qwen-serving.service` §`ExecStartPre` (line 10) — the authoritative GPU-free poll loop for D-05/SWITCH-04
- `single-user/start_qwen.sh` — `KV_MEM` defaults and the `--kv-cache-memory` mapping (approx. lines 273–433), `GPU_UTIL`, WSL2 auto-detection
- `batch/start_qwen.sh` — batch `KV=fp8` / `GPU_UTIL` sizing; confirms there is no `KV_MEM` plumbing to pin

### Compose & environment
- `docker-compose.yml` — `single`/`batch` profiles, `restart: unless-stopped`, `env_file: .env`, healthcheck definition
- `.env.tmpl` — committed template; the `KV_MEM` escape-hatch override would live in the gitignored `.env`
- `docs/docker.md` — container quick-start and WSL2 notes

### Phase 1 carry-forward
- `.planning/phases/01-bring-the-stack-up/01-CONTEXT.md` — D-01..D-07 (`.env` via `op inject`; `single` runs `SPEC=dflash2` + companions; `batch` stock)
- `README.md` §"If you are the only user" — single-user profile baseline

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `single-user/qwen-serving.service:10` — the GPU-free predicate/threshold to copy verbatim into `switch.sh`.
- `single-user/start_qwen.sh` — already accepts `KV_MEM` and emits `--kv-cache-memory=$KV_MEM`; `switch.sh` only needs to export it.
- `docker-compose.yml` profiles — switching is `--profile <name> stop` / `up -d`; no compose changes required.

### Established Patterns
- Compose + Docker restart policy as the deploy vehicle; no systemd (PROJECT.md constraint).
- `.env` is gitignored and generated from `.env.tmpl` via `op inject` (Phase 1 D-01).
- Idempotent run/install convention (BOOT-03; the paseo boot wrapper is idempotent).

### Integration Points
- New `switch.sh` at the repo root; new `.current-profile` state file (gitignored).
- `.current-profile` is the hand-off contract for Phase 3's boot hook.

</code_context>

<specifics>
## Specific Ideas

- No-arg `switch.sh` should intelligently target the non-running profile, falling back to persisted state, then `single`.
- The VRAM wait must mirror the existing `qwen-serving.service` loop rather than inventing a new threshold.
- The KV pin must stay overridable via `.env` — the escape hatch is deliberate.

</specifics>

<deferred>
## Deferred Ideas

- A `switch.sh status`/`current` subcommand to print the active profile — not required by SWITCH-01..04; potential later nicety.
- Pinning the KV cache for the `batch` profile — `batch` is intentionally left stock this phase; revisit only if batch throughput proves unstable across restarts.

</deferred>

---

*Phase: 2-Explicit Mode Switching*
*Context gathered: 2026-09-14*
