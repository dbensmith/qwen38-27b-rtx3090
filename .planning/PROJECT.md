# Qwen3.8-27B Deployment (Single-3090)

## What This Is

This repo already builds a patched-vLLM serving stack for Qwen3.8-27B on one
RTX 3090, with two mutually-exclusive serving modes (single-user low-latency
via MTP/DFlash2 speculative decoding, and batch high-throughput) exposed as
Docker Compose profiles (`single`, `batch`). This milestone turns that stack
into something that's actually running day to day on this machine: single-user
mode as the default, batch mode available as a one-command switch, and whichever
mode was last selected comes back up automatically when the WSL2 distro reboots
— following the same `/etc/wsl.conf [boot]` autostart pattern already used for
the Paseo daemon (chezmoi) and the Docker-on-GPU-host boot hook, rather than
systemd units (this WSL distro has no systemd as PID 1).

## Core Value

The 3090 always comes back serving requests after a reboot, in whichever mode
(single-user or batch) was last selected — with batch as the safe default
until a mode is explicitly chosen.

## Requirements

### Validated

- ✓ vLLM 0.28.0 patched and containerized for Qwen3.8-27B on one RTX 3090 — existing
- ✓ `docker-compose.yml` with `prepare` / `single` / `batch` profiles, `restart: unless-stopped` — existing
- ✓ `single-user/` and `batch/` launcher scripts, READMEs, env knobs — existing
- ✓ `verify.sh` install/runtime correctness gate — existing

### Active

- [ ] Model is downloaded/quantized and `single` profile runs and passes health check on this machine
- [ ] A switch command (e.g. `./switch.sh single|batch`) stops the other profile, starts the chosen one, and persists the choice
- [ ] WSL boot hook starts whichever profile was last persisted, defaulting to `batch` on first run
- [ ] Boot hook follows the existing chezmoi `/etc/wsl.conf [boot]` wrapper pattern (no systemd dependency)

### Out of Scope

- Bare-metal venv + `qwen-serving.service` systemd units as the primary path — this WSL distro has no systemd as PID 1; Compose + Docker's own restart policy is the deploy vehicle instead. The `.service` files stay in the repo as a reference/alternate path for systemd-capable hosts.
- Running both `single` and `batch` simultaneously — one GPU, one profile at a time.
- Automating the *initial* Docker daemon start inside an agent sandbox session — starting `dockerd` requires interactive sudo; the user runs that step manually.

## Context

- **Platform:** WSL2 (no systemd as PID 1 — confirmed `ps -p 1` is `init(WLinux)`), NVIDIA RTX 3090 (24GB), Docker via `service docker start`.
- **Existing WSL boot pattern:** `/etc/wsl.conf` `[boot] command = "/usr/local/bin/paseo-boot-start"`, managed by chezmoi (`~/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl`). That wrapper already starts the Docker service on GPU hosts (`.has_nvidia_gpu`) before starting the Paseo daemon as the login user via `su -l`. The qwen boot hook should extend or follow this same wrapper convention rather than introducing a second, conflicting boot mechanism.
- **Sibling repo convention:** `agent-selfhosted` (`~/repos/agent-selfhosted`) runs its own model stack via plain `docker-compose.yml`, no systemd — confirms Compose + Docker restart policy is the established local convention for GPU-model serving on this machine, not systemd units.
- **Docker daemon note:** not running by default in a bare agent-sandbox shell. `sudo service docker start` now has passwordless sudo, but can still fail with `ulimit: error setting limit (Invalid argument)` on a fresh WSL2 session — see docs/docker.md WSL2 notes item 6 (a `/etc/security/limits.d/99-docker-nofile.conf` pin, applied once from a real terminal, fixes it).
- **Upstream docs checked (DeepWiki, syv-ai/qwen38-27b-rtx3090):** confirms no existing systemd/boot-autostart guidance is published upstream — this is genuinely new ground for the repo, not a documented-but-unused feature. Also surfaces WSL2 knobs worth setting in `.env` when bringing the stack up: `GPU_UTIL=0.93` (vs. default `0.972`, to account for WSL2 VRAM overhead) and disabling `expandable_segments:True` if CUDA allocation errors appear on this driver.

## Constraints

- **Platform:** No systemd as PID 1 on this WSL distro — any boot automation must use the `/etc/wsl.conf [boot]` mechanism, not `systemctl enable`.
- **Hardware:** Single RTX 3090 (24GB VRAM) — single and batch profiles are mutually exclusive, never run concurrently.
- **Sandbox:** `sudo service docker start` has passwordless sudo now (scoped to `service docker {start,stop,restart,status}`), but a fresh WSL2 session can still fail on a kernel-level `ulimit` rejection — see docs/docker.md WSL2 notes item 6. The PAM-limits fix for that needs unrestricted sudo + a real terminal + session restart, which an agent session cannot do; everything downstream of a fixed session is unblocked.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Deploy via Docker Compose profiles, not bare-metal venv + systemd units | This WSL distro has no systemd; Compose + `restart: unless-stopped` + Docker's existing boot-start already covers most of the auto-restart behavior | ✓ Good |
| Explicit `switch.sh single\|batch` script, not "whatever was running wins" | User wants deliberate mode selection with a persisted choice, not implicit state inferred from container status | — Pending |
| Default profile is `batch` on first run | Quick task 260917-2fz (2026-09-17) made batch the current default; boot follows the same fallback (switch.sh:109) | ✓ Good |
| Boot autostart follows the existing chezmoi `/etc/wsl.conf [boot]` wrapper pattern | Consistency with the Paseo daemon boot hook already on this machine; avoids introducing systemd as a second, unsupported autostart mechanism | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-09-05 after initialization*
