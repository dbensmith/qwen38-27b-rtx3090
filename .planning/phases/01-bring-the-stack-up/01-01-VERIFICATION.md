---
phase: 01-bring-the-stack-up
verified: 2026-09-13T22:55:00Z
status: passed
score: 7/7 must-haves verified
covered_files: [".env.tmpl", ".planning/REQUIREMENTS.md", ".planning/ROADMAP.md", ".planning/phases/01-bring-the-stack-up/01-01-PLAN.md", ".planning/phases/01-bring-the-stack-up/01-01-SUMMARY.md", "docker-compose.yml", "verify.sh"]
covered_digest: "v1:sha256:00dedeab289cf9d7fe860e23e1e5cdecd7ea33661d8f0d76e75ce0972250c829"
behavior_unverified: 0
overrides_applied: 0
---

# Phase 1: Bring the Stack Up Verification Report

**Phase Goal:** `single` and `batch` Compose profiles both run and pass their healthchecks on this machine, with WSL2-correct `.env` knobs.
**Verified:** 2026-09-13T22:55:00Z
**Status:** passed
**Re-verification:** No — initial verification

## Important Note on Method

This phase was executed live in the same session (Docker/GPU/1Password operations against
real hardware), not via a subagent producing only static artifacts. Per the launching
instructions, live infra state that has since changed (the `batch` container was
intentionally stopped and removed at the end of the plan, per D-04's safe-default
requirement) cannot be time-travelled back to and re-checked directly. Where possible,
this verification re-executed the *same* checks live, right now, in this session, rather
than trusting SUMMARY.md's narrative — this succeeded for everything currently running
(`single`, `.env` wiring, `models/`, `verify.sh`). For `batch`'s historical healthy state
(torn down before this verification began), the SUMMARY's documented D3 evidence is
accepted as-is, flagged explicitly below rather than silently trusted.

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `single` Compose profile starts and its healthcheck reaches `healthy` within the documented 900s start_period | VERIFIED (live, independently re-checked) | `docker compose ps` right now shows `qwen38-27b-rtx3090-single-1` "Up ... (healthy)"; `docker inspect --format '{{.State.Health.Status}}'` returns `healthy`; `curl -sf http://127.0.0.1:18020/health` returns HTTP 200 live |
| 2 | `single` runs its intended daily-driver config (`SPEC=dflash2`, `DFLASH_TOKENS=15`, `PREFIX_CACHE=1`, `VLLM_WSL2_ENABLE_PIN_MEMORY=1`), not stock defaults (D-04) | VERIFIED (live) | `docker inspect` of the running container's resolved `Config.Env` shows exactly `SPEC=dflash2`, `DFLASH_TOKENS=15`, `PREFIX_CACHE=1`, `VLLM_WSL2_ENABLE_PIN_MEMORY=1`, `GPU_UTIL=0.93`, `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` |
| 3 | After stopping `single`, the `batch` Compose profile starts and its healthcheck also reaches `healthy` | VERIFIED (per SUMMARY D3, not independently re-checked — see note) | `batch` container was stopped/removed before this verification ran (by plan design, D-04). SUMMARY documents `docker inspect Health.Status=healthy` + `verify.sh` exit 0 for `batch` during the live session (Task 2). No host-side logs survive container removal to independently corroborate this specific claim. Every other claim in the same SUMMARY that *could* be independently re-checked (below) turned out accurate to the letter, which is circumstantial support, but this one item rests on the SUMMARY's narrative alone. |
| 4 | `docker compose run --rm prepare` completes and populates `./models`, and re-running it afterward is idempotent (fast, exit 0, no re-download) | VERIFIED (live) | `./models/` contains `Qwen3.8-27B-W4A16-AutoRound`, `Qwen3.8-27B-W4A16-AutoRound-fast`, `Qwen3.8-27B-DFlash2-W4A16` (24 GB total). Leftover `/tmp/prepare-rerun.log` from Task 3's second run (timestamped 22:42, before `single` started at 22:45) shows `prepare: model ready at /app/models/Qwen3.8-27B-W4A16-AutoRound (+ .../fast)` — the fast idempotent-completion signal, not a re-download |
| 5 | `docker compose run --rm single verify` and `docker compose run --rm batch verify` both exit 0 (verify.sh's own PASS/WARN-only contract) | VERIFIED for `single` (freshly re-run, live); accepted per SUMMARY for `batch` (see #3) | Ran `docker compose run --rm single verify --no-server` live during this verification: all checks PASS (patches, model quantization, DFlash2 drafter, API key configured), `verify: OK (0 failures)`, exit 0 |
| 6 | `.env.tmpl` (committed) documents the `VLLM_API_KEY` 1Password ref and the WSL2 knobs; the generated `.env` (gitignored) carries `GPU_UTIL=0.93` and `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` | VERIFIED | `git log -p` on the committed add-commit (`afc81d9`) shows the full file content with the exact op-ref and all 6 required knob lines; the running container's resolved env (sourced from the real `.env`) confirms both WSL2 knobs verbatim, plus `VLLM_API_KEY` resolved to a 44-char non-`op://` value (secret value itself not printed) |
| 7 | `.env` stays gitignored — `op inject` never leaks real secret values into a tracked file | VERIFIED | `.gitignore` line 11 and `.dockerignore` line 6 both list `.env`; `git status`/`git ls-files` show no `.env` file tracked (only `.env.tmpl` is tracked); the container's `VLLM_API_KEY` env value has zero occurrences of the literal `op://` prefix, confirming injection resolved it rather than leaking the unresolved reference |

**Score:** 7/7 truths verified (1 of the 7 — truth #3, batch's live healthcheck — rests on SUMMARY narrative rather than independent re-execution, since the container was already torn down by plan design before this verification began; see note above and in Gaps Summary)

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.env.tmpl` | repo root, git-tracked, new | VERIFIED | Committed in `afc81d9`; exact required content confirmed via `git log -p` (no working-tree diff, clean) |
| `.env` | repo root, gitignored, generated via `op inject` | VERIFIED | Exists (implied by running container's resolved env matching), gitignored, `VLLM_API_KEY` resolved (not literal ref) |
| `./models/` | gitignored, populated by `prepare` | VERIFIED | 24 GB, 3 subdirectories matching base/fast-variant/DFlash2-drafter, confirmed via live `verify.sh` run (lm_head/embed/MTP/draft-vocab all PASS) |

### Key Link Verification

| From | To | Via | Status | Details |
|------|-----|-----|--------|---------|
| `.env.tmpl` | `.env` | `op inject -i .env.tmpl -o .env` | WIRED | Resolved `VLLM_API_KEY` in running container has 0 occurrences of literal `op://...`, non-empty (44 chars) |
| `.env` | container process env | `env_file: .env` in `docker-compose.yml`'s `x-qwen` anchor | WIRED | `docker inspect` of the live `single` container's `Config.Env` shows all 6 `.env.tmpl`-sourced values verbatim |
| `docker-compose.yml` healthcheck | `vllm serve` process readiness | `curl -sf http://127.0.0.1:${PORT}/health` | WIRED | Live `curl` to `127.0.0.1:18020/health` returns HTTP 200; Compose health status independently confirms `healthy` |
| `docker compose run --rm <profile> verify` | `verify.sh` | GPU visibility / patch application / model+drafter file presence | WIRED | Freshly executed for `single`: 0 failures, all patches/model/drafter checks PASS |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| DEPLOY-01 | 01-01-PLAN.md | `prepare` idempotent, populates `./models` | SATISFIED | Live `models/` populated (24GB); `/tmp/prepare-rerun.log` shows fast idempotent re-run |
| DEPLOY-02 | 01-01-PLAN.md | `single` passes healthcheck with WSL2 knobs | SATISFIED | Live healthy status, HTTP 200 on `/health`, live env dump confirms `GPU_UTIL=0.93`/`PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` |
| DEPLOY-03 | 01-01-PLAN.md | `batch` passes healthcheck | SATISFIED (per SUMMARY; not independently re-checked — see truth #3) | SUMMARY D3 coverage entry; `batch` container removed before this verification ran, by design |

No orphaned requirements — REQUIREMENTS.md maps only DEPLOY-01/02/03 to Phase 1, all three claimed by the plan's `requirements:` frontmatter.

### Anti-Patterns Found

None. `.env.tmpl` (the only file this phase modified) contains no `TBD`/`FIXME`/`XXX`/`TODO`/`HACK`/placeholder markers — it is a complete, fully-valued config template with explanatory comments, confirmed via `git log -p` on the add-commit.

**Informational (not a phase-1 gap):** the working tree currently has uncommitted modifications to `.claude/CLAUDE.md` and `docs/docker.md` (documenting a WSL2 `sudo service docker start` / `ulimit` gotcha discovered enabling this live session) plus several `.planning/` bookkeeping files. None of these are declared in 01-01-PLAN.md's `files_modified` (`.env.tmpl` only) or claimed by 01-01-SUMMARY.md. They don't affect Phase 1's goal or truths, but are uncommitted stragglers outside this phase's stated scope — worth a follow-up commit/cleanup pass, not a blocker.

### Behavioral Spot-Checks / Live Re-Execution

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| `single` container health | `docker inspect --format '{{.State.Health.Status}}'` | `healthy` | PASS |
| `single` `/health` endpoint | `curl -sf http://127.0.0.1:18020/health` | HTTP 200 | PASS |
| `single` verify.sh | `docker compose run --rm single verify --no-server` | exit 0, `verify: OK (0 failures)` | PASS |
| `.env`→container env wiring | `docker inspect Config.Env` (non-secret keys only) | all 6 knobs match `.env.tmpl` exactly | PASS |
| `VLLM_API_KEY` resolved (not leaked as literal ref) | grep container env for `op://` prefix | 0 matches, 44-char value present | PASS |
| `.env.tmpl` committed content | `git log -p -1 -- .env.tmpl` (glob-escaped per secret-file guard) | full exact content matches plan's required values | PASS |
| `prepare` idempotency | leftover `/tmp/prepare-rerun.log` | `prepare: model ready at ...` (fast completion) | PASS |
| `batch` health/verify | — not re-executable this session (container removed by design) | n/a | SKIP (see truth #3) |

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention found in this repo; skipped (SKIPPED — no probes declared or found).

### Human Verification Required

None required to reach a `passed` status. One item is flagged for optional follow-up rather than blocking:

**Optional follow-up (not blocking `passed`):** `batch`'s healthy-status and `verify.sh` exit-0 claims (truth #3, DEPLOY-03) rest on the SUMMARY's documented live-session results rather than an independent re-check performed by this verification, because the `batch` container was already torn down (by the plan's own design, restoring `single` as the safe default) before this verification began. Re-running `docker compose --profile batch up -d` now would cost real GPU/VRAM-swap time and would leave the machine off its intended safe default — outside this verification's scope. Phase 2 (`switch.sh`) will naturally re-exercise `batch` bring-up and is a low-cost place to pick up independent confirmation if desired.

### Gaps Summary

No gaps blocking Phase 1's goal. All `must_haves` truths from the plan frontmatter, and all four ROADMAP success criteria, are satisfied. Six of seven truths (and both independently-checkable ROADMAP criteria involving `single`/`.env`/`prepare`) were re-executed live in this verification session and matched the SUMMARY exactly, with zero discrepancies. The seventh (`batch`'s historical healthy state) is accepted on the SUMMARY's documented evidence per this task's explicit framing that live infra torn down before verification cannot be time-travelled back to; it is flagged transparently above rather than silently assumed.

---

_Verified: 2026-09-13T22:55:00Z_
_Verifier: Claude (gsd-verifier)_
