# Phase 2: Explicit Mode Switching - Pattern Map

**Mapped:** 2026-09-14
**Files analyzed:** 3 (1 new script, 1 modified config, 1 runtime artifact)
**Analogs found:** 3 / 3 (composite analogs — `switch.sh` draws on 5 source files)

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `switch.sh` (NEW, repo root, executable) | utility (CLI orchestration script) | state-transition batch (detect → stop → poll VRAM → start → persist) | composite: `verify.sh` (repo-root script shape) + `single-user/qwen-serving.service:10` (VRAM poll, verbatim) + `single-user/start_qwen.sh` (KV_MEM idiom) + `docker/prepare.sh` (set -e, messages, exit codes) + `docker-compose.yml` (profile mechanics) | composite — each sub-pattern has an exact in-repo source |
| `.gitignore` (MODIFIED) | config | static | itself — append one token; `.env` entry (line 11) is the precedent for a gitignored repo-root runtime artifact | exact |
| `.current-profile` (NEW at runtime, gitignored, not source) | state file (one-token plain text) | file-I/O write-on-success | no source analog — nearest precedents: `.env` (gitignored runtime file consumed by compose `env_file`) and `api_key.txt` (one-line plain file at repo root, referenced `verify.sh:163-164`) | no code analog (documented contract in D-01/D-02) |

All analog paths verified git-tracked via `git ls-files` (non-empty for every file named below). `.env` and `.current-profile` are intentionally untracked runtime artifacts.

---

## Pattern Assignments

### `switch.sh` (utility, state-transition batch orchestration)

**Primary analogs:** `verify.sh` (shape), `single-user/qwen-serving.service` (VRAM gate), `single-user/start_qwen.sh` (KV_MEM), `docker/prepare.sh` (hardening), `docker-compose.yml` (compose mechanics)

#### Pattern 1 — Repo-root script shape (header, usage, cwd)

**Source:** `verify.sh` lines 1-14 (the only existing repo-root executable script)

```bash
#!/bin/bash
# Check that this repo is installed the way the README numbers assume: ...
#
#   bash verify.sh            # everything
#   bash verify.sh --no-server
#   ...
# Exit code: 0 all PASS (WARNs allowed), 1 if anything FAILs.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
```

Copy: `#!/bin/bash`, a header comment block stating purpose + invocation lines + exit-code contract, then resolve the script's directory and `cd` to the repo root (compose commands must run from the directory containing `docker-compose.yml` — same reason `batch/start_qwen.sh:44-45` does `REPO="$(dirname "$DIR")"; cd "$REPO"`).

#### Pattern 2 — VRAM release gate (D-05 / SWITCH-04): copy VERBATIM

**Source:** `single-user/qwen-serving.service` lines 7-10 (identical in `batch/qwen-serving.service:10`)

```ini
# Wait for the GPU to actually be free before starting. If vLLM profiles memory
# while a previous process is still releasing VRAM, it permanently allocates a
# smaller cache pool and throughput quietly suffers.
ExecStartPre=/bin/bash -c "for i in $(seq 1 60); do u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits); [ \"$u\" -lt 1000 ] && exit 0; sleep 2; done; exit 1"
```

Unescaped for `switch.sh`:

```bash
for i in $(seq 1 60); do
  u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits)
  [ "$u" -lt 1000 ] && exit 0   # in switch.sh: break/set a flag, do NOT exit the whole script
  sleep 2
done
# 60 tries x 2s exhausted: echo an error, exit non-zero, target profile NOT started (D-05)
```

D-05 requires mirroring this exactly: `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`, `< 1000` MB threshold, 2s cadence, 60 attempts. Do not invent a new threshold or cadence.

#### Pattern 3 — KV_MEM set-if-unset pin (D-06): the unset-vs-empty distinction is load-bearing

**Source:** `single-user/start_qwen.sh` lines 288-294 (unset check), 332/350/362/369 (defaults), 309 (empty = escape hatch), 433 (mapping)

```bash
# lines 288-294 — how this repo tests "unset" (NOT "empty"):
if [ "$TP_SIZE" -gt 1 ]; then
  if [ -z "${KV_MEM+x}" ]; then
    echo "[start_qwen] tensor-parallel-size $TP_SIZE: skipping the single-card KV_MEM" \
         "pin, sizing the KV pool from GPU_UTIL=$GPU_UTIL (issue #40; export KV_MEM" \
         "to pin it, KV_MEM= for this behavior explicitly)."
    KV_MEM=
  fi
fi

# lines 332, 350, 362, 369 — the set-if-unset default idiom used throughout:
KV_MEM=${KV_MEM-5261334938}     # CTX=huge
KV_MEM=${KV_MEM-5583457484}     # CTX=long / DFLASH_TOKENS>7 / default (5.2 GiB)

# line 309 — why empty must stay distinct from unset:
#   "KV_MEM= (empty) falls back to GPU_UTIL."

# line 433 — the mapping switch.sh relies on (no new plumbing needed):
[ -n "$KV_MEM" ] && EXTRA_ARGS="--kv-cache-memory=$KV_MEM ${EXTRA_ARGS}"
```

For `switch.sh` D-06 ("export `KV_MEM=5583457484` **only when unset**, so a user override in `.env` still wins") copy the `${KV_MEM+x}` idiom — **not** `:-`:

```bash
# Correct: only fill when UNSET; an explicit KV_MEM= in .env still means "no pin / GPU_UTIL"
if [ -z "${KV_MEM+x}" ]; then
  export KV_MEM=5583457484
fi
```

Using `${KV_MEM:-5583457484}` here would break the documented `KV_MEM=` (empty) escape hatch. `compose env_file: .env` (`docker-compose.yml:34-36`) injects `.env` into the container, so exporting `KV_MEM` in switch.sh's environment flows through `environment` inheritance to the `single` container; `batch/start_qwen.sh` has no `KV_MEM` support (verified: no match in its 199 lines) — batch stays stock (`KV=fp8` + `GPU_UTIL`, `batch/start_qwen.sh:59-75`), so the export is harmless there.

#### Pattern 4 — Hardening, messages, exit codes

**Source:** `docker/prepare.sh` lines 9, 47, 63-64; `batch/start_qwen.sh` lines 41, 161

```bash
set -e                                           # prepare.sh:9 (repo convention is `set -e`; CONTEXT leaves -u/-o pipefail to discretion)

# failure = message with a script prefix, then non-zero exit:
[ "$TODO" = "download" ] && { echo "prepare: download incomplete (shards missing after hf download)"; exit 1; }   # prepare.sh:47
[ -z "${LEFT// /}" ] || { echo "prepare: steps still missing after run: $LEFT"; exit 1; }                          # prepare.sh:63
echo "prepare: model ready at $BASE (+ $BASE-fast)"                                                               # prepare.sh:64 (success line)

# message-prefix convention in the start scripts:
echo "[start_qwen] removing stale offload region $f"    # batch/start_qwen.sh:41
echo "WSL detected: PYTORCH_CUDA_ALLOC_CONF=$ALLOC_DEFAULT (...)"   # batch/start_qwen.sh:160-161
```

Copy: a `[switch]` (or `switch:`) prefix on every status/error line, `echo ... ; exit N` on failure paths, a success line at the end. Note the array-vs-command-substitution warning at `batch/start_qwen.sh:108-118` (#59): avoid `VAR=$( [ cond ] && echo x )` shapes that exit 1 under `set -e` — build the running/target profile with plain if/else.

#### Pattern 5 — Compose profile mechanics (D-07)

**Source:** `docker-compose.yml` lines 22, 57-58, 66-79; `docs/docker.md` line 45

```yaml
# line 22 — the one-GPU invariant switch.sh exists to enforce:
# One GPU: run either "single" or "batch", not both.

# lines 57-58 — restart policy & grace period:
  restart: unless-stopped
  stop_grace_period: 30s

# lines 71-79 — the two profile-scoped services (prepare is unprofiled):
  single:
    <<: *serve
    profiles: [single]
    command: single

  batch:
    <<: *serve
    profiles: [batch]
    command: batch
```

```bash
# docs/docker.md:45 — the documented manual switch (D-07 swaps `down` for `stop`):
#   (`docker compose --profile single down` before `--profile batch up -d`)
```

Copy these mechanics:
- Stop outgoing: `docker compose --profile <other> stop` — `restart: unless-stopped` keeps an explicitly-stopped container down (D-07), so `up` of the other profile cannot resurrect it.
- `stop_grace_period: 30s` means `stop` itself can take ~30s to return; run the VRAM poll **after** `stop` returns.
- Start target: `docker compose --profile <target> up -d` — the unprofiled `prepare` service runs first via `depends_on: service_completed_successfully` (`docker-compose.yml:47-49`) and is a no-op when models exist.
- `up -d` returns immediately (detached); the 900s healthcheck `start_period` (`docker-compose.yml:59-64`) is not something `switch.sh` waits on — SWITCH-01..04 require the switch, not health confirmation.

#### Running-profile detection (D-03/D-04) — no script analog; documented convention

No existing script parses compose state. The repo's established idiom (used throughout Phase 1 planning/verification, e.g. `01-01-PLAN.md` tasks) is:

```bash
docker compose ps -q single        # container ID if running, empty if not
docker compose ps -q batch
docker inspect --format '{{.State.Health.Status}}' "$(docker compose ps -q single)"   # health, verification only
```

`docker compose ps` (without `-a`) lists running containers only, so empty output = not running. This is the detection primitive for "which profile is running" and the D-04 idempotency check. Reference: `docs/docker.md:37` shows `docker compose ps` as the status tool.

#### WSL2 detection — reference only (likely NOT needed in switch.sh)

**Source:** `single-user/start_qwen.sh` lines 646-659 (canonical long note), `batch/start_qwen.sh:158-165`

```bash
if grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null || [ -n "${WSL_DISTRO_NAME:-}" ]; then
  ...
fi
```

All WSL2 container knobs already flow via `.env` (`VLLM_WSL2_ENABLE_PIN_MEMORY=1`, `PYTORCH_CUDA_ALLOC_CONF` — `.env.tmpl:6-10`); switch.sh runs host-side and should not duplicate this. Listed so the planner consciously skips it rather than overlooking it.

---

### `.gitignore` (config, static)

**Analog:** itself; `.env` entry at line 11 is the precedent

Current file (lines 1-16) is one token per line, sorted-ish, with at most one trailing comment block. The `.env` entry (line 11) covers the closest existing case: a repo-root runtime artifact that scripts write and read. Append `.current-profile` ( CONTEXT leaves exact placement/format to discretion). Do not commit `.current-profile` itself — it is a runtime artifact like `.env` and `api_key.txt`.

---

### `.current-profile` (state file, file-I/O) — NO SOURCE ANALOG

| Property | Contract (from D-01/D-02) |
|----------|---------------------------|
| Path | repo root, `.current-profile` |
| Content | single token: `single` or `batch` (plain text) |
| Written by | `switch.sh`, after every successful switch (and on the D-04 no-op path, to refresh) |
| Read by | `switch.sh` (no-arg fallback), Phase 3 boot hook |
| Absent/blank/corrupt | effective profile is `single` (SWITCH-03) |
| Gitignored | yes (`.gitignore` entry this phase) |

Nearest precedents (not code, but conventions): `.env` (gitignored, compose-consumed) and `api_key.txt` (one-line plain file created by shell redirect, read via `$(cat ...)` — see `batch/start_qwen.sh:178-179` and `verify.sh:163-164`). Write with a plain redirect (`printf '%s\n' "$profile" > .current-profile`); the Phase 3 reader will treat unexpected content as `single`, so the writer should keep the file to exactly one token.

## Shared Patterns

### GPU-free VRAM gate
**Source:** `single-user/qwen-serving.service:10` (verbatim; same line in `batch/qwen-serving.service:10`)
**Apply to:** `switch.sh` (between stop and start)
```bash
for i in $(seq 1 60); do u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits); [ "$u" -lt 1000 ] && exit 0; sleep 2; done; exit 1
```
Rationale carried in the service file comment (lines 7-9): starting vLLM while VRAM is still being released permanently shrinks the KV pool.

### Set-if-unset env override (empty ≠ unset)
**Source:** `single-user/start_qwen.sh:289` (`[ -z "${KV_MEM+x}" ]`), `:309` (empty = GPU_UTIL fallback), `:433` (mapping)
**Apply to:** `switch.sh` KV_MEM export
```bash
[ -z "${KV_MEM+x}" ] && export KV_MEM=5583457484
```

### Script shape: header + cwd + set -e + prefixed messages + explicit exits
**Source:** `verify.sh:1-14` (shape), `docker/prepare.sh:9,47,63-64` (set -e, `prefix: message` + `exit 1`)
**Apply to:** `switch.sh`

### Compose profile stop/up with restart policy
**Source:** `docker-compose.yml:57,71-79`; `docs/docker.md:45`
**Apply to:** `switch.sh` — `--profile <other> stop` → VRAM gate → `--profile <target> up -d`; `restart: unless-stopped` guarantees a stopped profile stays stopped.

### Running-profile detection via `docker compose ps -q <profile>`
**Source:** no script analog; Phase 1 verification idiom (`docker compose ps -q single` empty/non-empty), `docs/docker.md:37`
**Apply to:** `switch.sh` (D-03 no-arg inversion + D-04 idempotency)

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `.current-profile` | state file | file-I/O (one-token) | No repo file is a script-written profile/state token; contract comes from D-01/D-02. Precedents: `.env`, `api_key.txt` |
| running-profile detection inside `switch.sh` | — | — | No existing script queries compose state; use the Phase-1 `docker compose ps -q <profile>` idiom |
| no-arg target inversion (D-03) | — | — | New logic; no prior art. Fall back: not-running inverse → `.current-profile` → `single` |

## Executor Gotchas (extracted from analog sources)

1. **Empty vs unset KV_MEM** (`single-user/start_qwen.sh:289,309`): `KV_MEM=` in `.env` is a documented "no pin" escape hatch. Use `${KV_MEM+x}`, never `:-`, when implementing D-06's "only when unset".
2. **`set -e` + command substitution traps** (`batch/start_qwen.sh:108-118`, issue #59): `VAR=$( [ cond ] && echo x )` silently exits the script when cond is false. Prefer if/else for profile-target computation.
3. **`stop` can take ~30s** (`docker-compose.yml:58` `stop_grace_period: 30s`): the VRAM poll starts after `stop` returns; total worst case ≈ 30s + 120s poll before abort (D-05).
4. **`up -d` is fire-and-forget**: do not add a health-wait loop to `switch.sh` runtime behavior — SWITCH-01..04 and D-01..D-07 don't require it, and a `status` subcommand is explicitly deferred (02-CONTEXT deferred ideas). (Health-wait loops belong in *verification* steps, as Phase 1 did.)
5. **One GPU invariant** (`docker-compose.yml:22`): the script must never leave both profiles up; stopping the outgoing profile before starting the target is the whole point.
6. **`prepare` is unprofiled** (`docker-compose.yml:67-69`): `--profile X stop` only touches profile-scoped services; `up -d` re-runs `prepare` idempotently via `depends_on` — no special handling needed.

## Metadata

**Analog search scope:** repo root, `single-user/`, `batch/`, `docker/`, `docs/`, `.planning/` (Phase 1 artifacts for compose-idiom precedent)
**Files scanned:** 12 (`verify.sh`, `docker/prepare.sh`, `docker/entrypoint.sh`, `docker-compose.yml`, `.gitignore`, `.env.tmpl`, `single-user/qwen-serving.service`, `single-user/start_qwen.sh` (targeted), `batch/start_qwen.sh`, `batch/qwen-serving.service`, `docs/docker.md` (grep), `.planning/REQUIREMENTS.md` (grep))
**Analog search stopped at:** 5 strong matches (early stopping per protocol)
**Tracked-source gate:** all named analogs verified git-tracked (`git ls-files`)
**Pattern extraction date:** 2026-09-14
