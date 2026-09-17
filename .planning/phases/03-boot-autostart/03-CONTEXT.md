# Phase 3: Boot Autostart - Context

**Gathered:** 2026-09-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Make the last-selected Compose profile come back up automatically after a WSL2 reboot: install a boot hook that follows the existing `/etc/wsl.conf [boot]` chezmoi wrapper convention (no systemd), reads the `.current-profile` state file written by `switch.sh`, and starts that profile — defaulting to `batch` when nothing was ever chosen. Covers BOOT-01 through BOOT-03.

Not in scope: changing how `switch.sh` works, running both profiles concurrently (one GPU), systemd units, any tuning of either profile.

</domain>

<decisions>
## Implementation Decisions

### Hook placement & ownership
- **D-01:** Separate boot wrapper at `/usr/local/bin/local-llm-start` — vendor/model-agnostic name per user choice. Do NOT append a qwen block into `/usr/local/bin/paseo-boot-start`: the chezmoi template rewrites that file unconditionally on every apply and would clobber it.
- **D-02:** `/etc/wsl.conf [boot]` chains both wrappers (paseo + local-llm-start) in a single boot command, each failing independently without blocking the other.
- **D-03:** The chezmoi template owns both wrappers — `chezmoi apply` is the BOOT-03 installer. There is NO repo-root installer script. — **Reversibility:** costly — undo moves boot-hook ownership back into the repo and splits it from the dotfiles repo's boot management.

### Boot mechanics
- **D-04:** `local-llm-start` reads `.current-profile` at the repo root and runs `docker compose --profile <persisted> up -d` for exactly that profile.
- **D-05:** Run the compose stack as the login user via `su -l pengwin` (mirroring `paseo-boot-start`), not as root — same PATH/env as interactive use so `docker` and `compose` resolve identically.
- **D-06:** Skip the VRAM-release gate at boot — a fresh boot means VRAM is free; the 60×2s poll is a switch-time concern only.
- **D-07:** Fire-and-forget `up -d` at boot; do NOT block on `/health` (the Compose healthcheck owns that with its 900s start period, and `restart: unless-stopped` covers crashes).

### Default (locked)
- **D-08:** The locked default is `batch` — matching current `switch.sh:109` behavior after quick task 260917-2fz. This deliberately overrides the stale `single` wording in ROADMAP/REQUIREMENTS/PROJECT.md. — **Reversibility:** reversible — one-token fallback, trivial to flip.
- **D-09:** Tolerant fallback at boot, same as `switch.sh`: missing, blank, whitespace-only, or corrupt `.current-profile` all resolve to the default (`batch`).
- **D-10:** The plan MUST include aligning the planning docs to `batch`: BOOT-02 wording, ROADMAP Phase 3 success criterion 3, and PROJECT.md Key Decisions (default-profile row).

### Installer & verification
- **D-11:** BOOT-03 idempotency is proven via the template's already-set check: re-running `chezmoi apply` prints the `already set — no change` path and touches nothing (same convention as the paseo template).
- **D-12:** Verify BOOT-01 with a REAL `wsl --shutdown` + reopen cycle (not a dry run) — slow (model load + JIT) but conclusive.
- **D-13:** The boot wrapper logs what it did (timestamp, profile chosen, compose result) to a file so the post-reboot check has evidence.

### the agent's Discretion
- Exact `wsl.conf` chaining syntax (`&&` vs `;` with `|| true` guards), exact log file path, repo-path resolution in the wrapper (fixed path vs discovery), `stop_grace_period`/ordering relative to the Docker-daemon start lines, and the exact doc-wording edits for D-10.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Boot requirements & project decisions
- `.planning/REQUIREMENTS.md` — BOOT-01..03 (note: BOOT-02 wording still says `single`; D-08 locks `batch` — update per D-10)
- `.planning/PROJECT.md` — Key Decisions (boot follows chezmoi `/etc/wsl.conf [boot]` pattern, no systemd) and Constraints (one GPU, no systemd as PID 1)
- `.planning/ROADMAP.md` §"Phase 3: Boot Autostart" — goal and success criteria (note: criterion 3 still says `single`; D-08 locks `batch` — update per D-10)

### Boot wrapper pattern to follow
- `~/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl` — the authoritative template: wrapper-write + `wsl.conf` patch + idempotency grep. The qwen-side work extends this pattern (D-01..D-03, D-11).
- `/usr/local/bin/paseo-boot-start` (live) — current wrapper: Docker-daemon start lines + `su -l pengwin` login-shell convention to mirror (D-05)
- `/etc/wsl.conf` — live `[boot] command` line being chained (D-02)

### State-file contract & compose
- `switch.sh` — `.current-profile` writer (single token, written only after successful `up -d`); tolerant read/fallback logic to mirror at boot (D-04, D-09); NOTE line 109 currently defaults to `batch` (evidence for D-08)
- `.current-profile` (repo root, gitignored) — the persisted token the boot hook reads
- `docker-compose.yml` — `single`/`batch` profiles, `restart: unless-stopped`, `env_file: .env`, healthcheck definition

### Prior-phase carry-forward
- `.planning/phases/02-explicit-mode-switching/02-CONTEXT.md` — D-01..D-07 (state-file contract, idempotency convention, no systemd)
- `.planning/phases/01-bring-the-stack-up/01-CONTEXT.md` — D-01..D-07 (`.env` via `op inject`, WSL2 knobs)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `paseo-boot-start` Docker-start snippet (`service docker status || service docker start`) — the qwen wrapper runs after it in the same boot line, so Docker is up before `compose up -d`.
- `switch.sh` tolerant state-file read (whitespace strip + whitelist case) — copy the predicate verbatim into `local-llm-start` for D-09.
- `docker-compose.yml` `restart: unless-stopped` — an explicitly-stopped profile stays down; boot `up -d` only starts the persisted one.

### Established Patterns
- Compose + Docker restart policy as the deploy vehicle; no systemd (PROJECT.md constraint).
- Idempotent run/install convention: grep-before-patch, `already set — no change` message (paseo template; D-11).
- `su -l` login-shell convention so boot env matches interactive env (D-05).

### Integration Points
- New `/usr/local/bin/local-llm-start` wrapper (owned by chezmoi template, not this repo).
- Modified `/etc/wsl.conf [boot]` command chaining both wrappers.
- Modified chezmoi template `run_onchange_after_04-wsl-boot-paseo.sh.tmpl` (or a sibling template) to own the above.
- Read-only dependency on `<repo>/.current-profile` at boot.

</code>

<specifics>
## Specific Ideas

- Wrapper name `local-llm-start` was explicitly chosen to stay agnostic to vendor (Qwen) and model (3.8-27B) — do not rename it to anything qwen/model-specific.
- User explicitly rejected a repo-root installer script — `chezmoi apply` is the installer; planner must not create one.
- User explicitly chose a real `wsl --shutdown` reboot for verification despite the time cost.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 3-Boot Autostart*
*Context gathered: 2026-09-17*
