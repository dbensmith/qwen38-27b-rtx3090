# Roadmap: Qwen3.8-27B Deployment (Single-3090)

**Structure:** Horizontal layers — get the stack running, then make switching explicit, then make it survive reboots.

## Phase 1: Bring the Stack Up

**Goal:** `single` and `batch` Compose profiles both run and pass their healthchecks on this machine, with WSL2-correct `.env` knobs.
**Requirements:** DEPLOY-01, DEPLOY-02, DEPLOY-03
**Success Criteria**:

1. `sudo service docker start` + `docker compose run --rm prepare` completes and populates `./models`
2. `docker compose --profile single up -d` reaches `healthy` status on `/health`
3. Stopping `single` and running `docker compose --profile batch up -d` also reaches `healthy`
4. `.env` carries the WSL2 knobs (`GPU_UTIL=0.93`, `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` if needed) documented in REQUIREMENTS.md

**Plans:** 1/1 plans complete
Plans:

- [x] 01-01-PLAN.md — Bring up `single` (daily-driver config) then `batch`, prove both healthy + verify-clean, restore `single` as default

## Phase 2: Explicit Mode Switching

**Goal:** A single command switches between single-user and batch mode safely and remembers the choice.
**Requirements:** SWITCH-01, SWITCH-02, SWITCH-03, SWITCH-04
**Success Criteria**:

1. `./switch.sh single` and `./switch.sh batch` each stop the other profile and bring up the requested one
2. The script waits for VRAM to actually free (mirrors `qwen-serving.service`'s `ExecStartPre` GPU-free loop) before starting the new profile
3. `--kv-cache-memory` is pinned to an explicit byte value rather than a percentage, and survives repeated switches without throughput regressions
4. The chosen profile is persisted to a state file that `switch.sh` reads on the next invocation

**Plans:** 1/1 plans complete
Plans:

- [x] 02-01-PLAN.md — Build `switch.sh` (stop → VRAM gate → KV pin → start → persist), prove explicit switching live in both directions, add no-arg resolution / idempotency / corrupt-state defaults, prove the gate-abort contract, restore `single` healthy

## Phase 3: Boot Autostart

**Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `batch` if nothing was ever chosen.
**Requirements:** BOOT-01, BOOT-02, BOOT-03
**Success Criteria**:

1. A boot hook is installed that follows the existing `/etc/wsl.conf [boot]` chezmoi wrapper convention (extends or sits alongside `paseo-boot-start`, no systemd)
2. After `wsl --shutdown` + reopen, the persisted profile's container comes up without manual intervention
3. On a machine with no persisted state yet, the boot hook starts `batch`
4. Re-running the boot-hook installer is a no-op if already installed (idempotent, matching the paseo wrapper's own idempotency check)

**Plans:** 2 plans
Plans:

- [ ] 03-01-PLAN.md — Create the 045 boot-LLM chezmoi template (local-llm-start wrapper + self-healing combined `[boot]` line), commit in the dotfiles repo, verify with a real `wsl --shutdown` + reopen (human checkpoint)
- [ ] 03-02-PLAN.md — Align the planning docs (REQUIREMENTS/ROADMAP/PROJECT/switch.sh header) with the locked `batch` default (D-08/D-10) and commit the pending Phase 2 bookkeeping

---
*Roadmap created: 2026-09-06*
