# Phase 1: Bring the Stack Up - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-06
**Phase:** 1-Bring the Stack Up
**Areas discussed:** .env scope & auth, Execution & verification workflow, Model/config scope, verify.sh's role

---

## .env scope & auth

| Option | Description | Selected |
|--------|-------------|----------|
| WSL knob only | Just GPU_UTIL=0.93, no explicit alloc pin, no auth | |
| WSL knob + explicit alloc pin | GPU_UTIL=0.93 + explicit PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False | ✓ |
| WSL knob + API key | GPU_UTIL=0.93 + generate/set VLLM_API_KEY | ✓ |

**User's choice:** Both option 2 and 3 — explicit alloc pin AND an API key.
**Notes:** User then specified the API key should follow the same 1Password `op inject` pattern used in `~/repos/agent-selfhosted`, reusing its `LLAMA_SERVER_API_KEY` op-ref rather than minting a new 1Password item.

---

## Docker daemon blocker (unplanned detour)

Not a gray-area question — a live blocker discovered while discussing execution workflow. `sudo service docker start` failed with `ulimit: error (Invalid argument)`. Diagnosed as not a kernel-ceiling issue (`/proc/sys/fs/nr_open` = 1048576). User resolved it independently outside this session; `docker ps` confirmed working afterward.

---

## Execution & verification workflow

| Option | Description | Selected |
|--------|-------------|----------|
| I run it directly | Claude runs op inject/compose/curl commands directly in-session, reports results as it goes | ✓ (after docker access confirmed) |
| Exact commands, you run + report back | Claude hands over command sequence, user runs and pastes output | (initially considered before docker access was confirmed) |
| Standalone runbook doc | RUNBOOK.md checklist, user works through independently | |

**User's choice:** Claude runs it directly, now that docker/op access is confirmed working in this session.
**Notes:** Initial attempt at this question surfaced the docker daemon blocker above; resolved before re-asking.

---

## Model/config scope for this phase

| Option | Description | Selected |
|--------|-------------|----------|
| Stock config only | No SPEC/DRAFT_TOKENS/INT8 knobs, default launcher behavior | |
| Include SPEC=dflash2 now | Set SPEC=dflash2 + DFLASH_TOKENS + PREFIX_CACHE + VLLM_WSL2_ENABLE_PIN_MEMORY in .env now | ✓ |

**User's choice:** Include SPEC=dflash2 now — single-user mode gets its intended daily config rather than a throwaway stock one.
**Notes:** batch profile stays stock (roadmap only asks for it to start and pass healthcheck).

---

## verify.sh's role

| Option | Description | Selected |
|--------|-------------|----------|
| Compose healthcheck + verify.sh | Both the /health Compose healthcheck AND `docker compose run --rm <profile> verify` as explicit pass/fail gates | ✓ |
| Compose healthcheck only | Rely on Compose reaching "healthy" only | |

**User's choice:** Both — verify.sh runs as an explicit gate in addition to the Compose healthcheck.

---

## Claude's Discretion

- Exact `DFLASH_TOKENS` value and any other dflash2-adjacent knob not explicitly named — use README's documented "fastest single-user decode" recipe as baseline.

## Deferred Ideas

None — discussion stayed within Phase 1 scope.
