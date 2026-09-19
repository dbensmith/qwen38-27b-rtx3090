# Requirements: Qwen3.8-27B Deployment (Single-3090)

**Defined:** 2026-09-06
**Core Value:** The 3090 always comes back serving requests after a reboot, in whichever mode (single-user or batch) was last selected — with batch as the safe default until a mode is explicitly chosen.

## v1 Requirements

### Deploy

- [x] **DEPLOY-01**: `prepare` profile downloads and quantizes the model into `./models` (idempotent — safe to re-run)
- [x] **DEPLOY-02**: `single` profile starts and passes its Compose healthcheck (`/health`) on this machine, with WSL2-appropriate `.env` knobs (`GPU_UTIL=0.93`; `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` if "device not ready" appears during weight repacking — note this is the opposite of the general non-WSL2 recommendation)
- [x] **DEPLOY-03**: `batch` profile starts and passes its Compose healthcheck on this machine

### Switching

- [x] **SWITCH-01**: A `switch.sh single|batch` script stops whichever profile is currently running and starts the requested one
- [x] **SWITCH-02**: The switch script persists the chosen profile to a state file so it survives a reboot
- [x] **SWITCH-03**: Running `switch.sh` with no persisted state yet defaults to `single`
- [x] **SWITCH-04**: `switch.sh` waits for the outgoing profile's VRAM to fully release (matching the existing `qwen-serving.service` `ExecStartPre` GPU-free check pattern) before starting the new one, and pins `--kv-cache-memory` to an explicit byte value rather than a `gpu-memory-utilization` fraction, so restart-to-restart KV pool sizing is stable

### Boot Autostart

- [x] **BOOT-01**: A WSL boot hook (following the existing `/etc/wsl.conf [boot]` chezmoi wrapper convention, not systemd) starts the last-persisted profile after `wsl --shutdown` + restart
- [x] **BOOT-02**: If no profile was ever selected, the boot hook starts `batch` by default
- [x] **BOOT-03**: Boot hook installation is idempotent (safe to re-run, matches the existing paseo-boot-start wrapper pattern)

## v2 Requirements

(None identified — this is a small, single-machine deployment task.)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Bare-metal venv + `qwen-serving.service` systemd units as primary deploy path | This WSL distro has no systemd as PID 1; kept in repo as reference only |
| Running `single` and `batch` concurrently | One GPU, one profile at a time |
| Agent-automated `dockerd` startup inside this sandbox | Requires interactive sudo; user runs it once manually |
| Multi-machine / portable deployment | Scoped to this one WSL2 host |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| DEPLOY-01 | Phase 1 | Complete |
| DEPLOY-02 | Phase 1 | Complete |
| DEPLOY-03 | Phase 1 | Complete |
| SWITCH-01 | Phase 2 | Complete |
| SWITCH-02 | Phase 2 | Complete |
| SWITCH-03 | Phase 2 | Complete |
| SWITCH-04 | Phase 2 | Complete |
| BOOT-01 | Phase 3 | Complete |
| BOOT-02 | Phase 3 | Complete |
| BOOT-03 | Phase 3 | Complete |

**Coverage:**

- v1 requirements: 10 total
- Mapped to phases: 10
- Unmapped: 0 ✓

---
*Requirements defined: 2026-09-06*
*Last updated: 2026-09-06 after initial definition*
