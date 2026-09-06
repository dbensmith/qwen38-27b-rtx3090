# Phase 1: Bring the Stack Up - Context

**Gathered:** 2026-09-06
**Status:** Ready for planning

<domain>
## Phase Boundary

Get both Compose profiles (`single`, `batch`) running and passing their healthchecks on this machine, with a correctly configured, gitignored `.env`. Includes generating that `.env` via 1Password injection, running `prepare`, bringing up `single` then `batch`, and confirming health via both the Compose healthcheck and `verify.sh`. Single-user mode gets its intended day-to-day config (`SPEC=dflash2`) rather than stock defaults, since it's the mode that will run daily.

</domain>

<decisions>
## Implementation Decisions

### .env generation & secrets
- **D-01:** `.env` is generated from a committed `.env.tmpl` via `op inject`, following the exact pattern already used in the sibling repo `~/repos/agent-selfhosted` (`.env.tmpl` with `VAR=op://vault/item/credential` refs → gitignored `.env` with real values).
- **D-02:** `VLLM_API_KEY` in `.env.tmpl` points at the **same 1Password item** agent-selfhosted uses for `LLAMA_SERVER_API_KEY` (`op://ops-dotfiles/qbdcgbhl4olpro6wrx4x4cg5qq/credential`) — one shared key across both local model servers, not a new item.
- **D-03:** `.env` also gets `GPU_UTIL=0.93` and an explicit `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False`, even though `single-user/start_qwen.sh` / `batch/start_qwen.sh` already auto-detect WSL2 and default to `False` — pin it explicitly in `.env.tmpl` so it's visible/documented rather than relying on runtime auto-detection. — **Reversibility:** reversible — just an env var line, trivial to remove or flip.

### Single-user mode config
- **D-04:** `SPEC=dflash2` is set now (not deferred to a later phase), plus its required companions: `DFLASH_TOKENS` (repo's documented default, e.g. 15 per README's "fastest single-user decode" recipe), `PREFIX_CACHE=1`, and `VLLM_WSL2_ENABLE_PIN_MEMORY=1` (mandatory on WSL2 per `docker-compose.yml`'s own comment — SPEC=dflash2 forces the V2 model runner, which aborts with "UVA is not available" on WSL2 without this flag). — **Reversibility:** reversible — env-var-only, no code changes; ripping it back to stock config is a one-line `.env` edit.
- **D-05:** `batch` profile stays on stock/default config — the roadmap's batch requirement (DEPLOY-03) is just "starts and passes healthcheck," no tuning requested.

### Execution & verification workflow
- **D-06:** Claude runs the bring-up directly in this session (`op inject`, `docker compose run --rm prepare`, `docker compose --profile single up -d`, curl `/health`, stop single, `docker compose --profile batch up -d`, curl `/health`) — docker and `op` access were confirmed working in this session (docker daemon start's earlier `ulimit` failure was resolved by the user outside this session). Report results/failures as they happen rather than handing off a runbook.
- **D-07:** "Passes healthcheck" = both the Compose healthcheck reaching `healthy` AND an explicit `docker compose run --rm single verify` / `batch verify` pass (verify.sh is the repo's own correctness gate — cheap to run once bring-up succeeds, catches things the HTTP healthcheck alone wouldn't).

### Claude's Discretion
- Exact `DFLASH_TOKENS` value and any other dflash2-adjacent knob not explicitly named above — use the repo's own documented "fastest single-user decode" recipe from README as the baseline, adjust only if verify.sh or the healthcheck surfaces a problem.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Compose & environment knobs
- `docker-compose.yml` — profiles, env_file wiring, healthcheck definition, WSL2 pin-memory note in the header comment
- `docs/docker.md` — container quick-start, WSL2 `expandable_segments` gotcha (§4), `GPU_UTIL` guidance
- `docs/wsl2-4090.md` — WSL2-specific GPU_UTIL/allocator findings referenced in PROJECT.md

### Single-user config recipe
- `README.md` §"If you are the only user" (fastest single-user decode recipe: `SPEC=dflash2`, `DFLASH_TOKENS=15`, `PREFIX_CACHE=1`) — baseline for D-04
- `single-user/start_qwen.sh` — WSL2 auto-detection logic for `PYTORCH_CUDA_ALLOC_CONF` (lines ~646-663), `GPU_UTIL` default

### Verification
- `verify.sh` — install/runtime correctness gate; invoked via `docker compose run --rm <profile> verify` per D-07

### Secrets pattern (external repo, reference only)
- `~/repos/agent-selfhosted/.env.tmpl` — the `op://vault/item/credential` pattern being replicated (D-01, D-02)
- `~/repos/agent-selfhosted/README.md` §"Secrets" — documents the `op inject` workflow this phase follows

### Project-level
- `.planning/REQUIREMENTS.md` — DEPLOY-01/02/03
- `.planning/PROJECT.md` — sandbox/docker-daemon constraint (now resolved — see Specifics below)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `docker-compose.yml`'s `env_file: .env` wiring — no compose changes needed, `.env` is the only new artifact besides `.env.tmpl`
- `verify.sh` — already supports being invoked as `docker compose run --rm <profile> verify`

### Established Patterns
- `.env.tmpl` + `op inject` → gitignored `.env` is an established convention on this machine (agent-selfhosted), not something to invent fresh
- WSL2 auto-detection for `PYTORCH_CUDA_ALLOC_CONF` already exists in both launcher scripts — the explicit `.env` pin (D-03) is redundant with working code, purely for documentation/visibility

### Integration Points
- `.env.tmpl` is a new file at repo root (committed); `.env` itself stays gitignored per existing `.gitignore`/`.dockerignore` conventions

</code_context>

<specifics>
## Specific Ideas

- **Docker daemon blocker resolved mid-discussion:** `sudo service docker start` initially failed with `ulimit: error (Invalid argument)` in `/etc/init.d/docker`. Diagnosed that `/proc/sys/fs/nr_open` (1048576) wasn't the ceiling — likely a sudo/PAM process-context quirk. User fixed it independently outside this session; `docker ps` now succeeds in this session (confirmed against a live `docker-model-runner` container). **PROJECT.md's "Sandbox cannot start Docker daemon" constraint is now stale** for this session — planner/executor should verify docker access live rather than assuming the constraint still holds, since it depends on session state.
- User wants the exact same 1Password op-ref pattern as `agent-selfhosted`, reusing its `LLAMA_SERVER_API_KEY` item's ref rather than minting a new 1Password item.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within Phase 1 scope. (SPEC=dflash2 tuning was pulled *into* scope per D-04 rather than deferred, since the user wants single-user mode running its intended daily config rather than a throwaway stock config that gets reconfigured in a later phase.)

</deferred>

---

*Phase: 1-Bring the Stack Up*
*Context gathered: 2026-09-06*
