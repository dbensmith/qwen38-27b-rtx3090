#!/bin/bash
# Switch this one-GPU Qwen3.8-27B stack between the "single" (low-latency,
# speculative decoding) and "batch" (throughput) Compose profiles: stop the
# outgoing profile, wait for the GPU to actually free, start the requested
# profile, and persist the choice to .current-profile at the repo root
# (gitignored runtime state; the Phase 3 boot hook reads it).
#
#   ./switch.sh single    # switch to single-user (low-latency) mode
#   ./switch.sh batch     # switch to batch (throughput) mode
#   ./switch.sh           # no argument: switch to the non-running profile;
#                         # with neither running, fall back to the persisted
#                         # .current-profile token; absent/blank/corrupt -> single
#                         # (requesting the already-running profile is a no-op)
#
# Exit code: 0 switched (or no-op), 1 operational failure (VRAM-release gate
# timeout, compose failure), 2 usage error (unknown token or extra arguments).
#
# The VRAM gate mirrors single-user/qwen-serving.service:10 exactly: if vLLM
# profiles memory while a previous process is still releasing VRAM, it
# permanently allocates a smaller cache pool and throughput quietly suffers.
set -e
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
STATE_FILE="$HERE/.current-profile"

# WSL2 keeps nvidia-smi in /usr/lib/wsl/lib, which is not on PATH in every
# shell (agent sandboxes in particular). Add it when present so the VRAM gate
# below resolves; a no-op when nvidia-smi is already reachable or the path
# does not exist (non-WSL hosts).
if ! command -v nvidia-smi >/dev/null 2>&1 && [ -d /usr/lib/wsl/lib ]; then
  export PATH="/usr/lib/wsl/lib:$PATH"
fi

usage() {
  cat <<'EOF'
usage: ./switch.sh [single|batch]
  single   switch to the single-user low-latency profile
  batch    switch to the batch high-throughput profile
EOF
}

# ---- argument whitelist + no-arg resolution (D-03; truth 8) -----------------
# Only the literal tokens single/batch ever reach a compose command; an
# unvalidated argument is never interpolated anywhere. An invalid invocation
# touches no container and no state file.
if [ $# -gt 1 ]; then
  echo "[switch] error: expected at most one argument (single|batch), got $#" >&2
  usage >&2
  exit 2
fi

TARGET=
RESOLVED_FROM=
if [ $# -eq 0 ]; then
  NOARG=1
else
  case "$1" in
    single|batch) TARGET=$1 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "[switch] error: unknown argument '$1' (expected single or batch)" >&2; usage >&2; exit 2 ;;
  esac
fi

# ---- which profiles are running (D-03/D-04 detection) -------------------------
# docker compose ps -q <profile> (without -a) lists running containers only:
# empty output = not running. Built with if-guards so a compose query failure
# is a clean [switch] error, not a bare set -e abort.
if ! SINGLE_RUNNING=$(docker compose ps -q single); then
  echo "[switch] error: cannot query compose state (is the Docker daemon running?)" >&2
  exit 1
fi
if ! BATCH_RUNNING=$(docker compose ps -q batch); then
  echo "[switch] error: cannot query compose state (is the Docker daemon running?)" >&2
  exit 1
fi

# Both-running anomaly (one GPU: docker-compose.yml:22) — refuse on every
# invocation path rather than no-op or switch against a contended GPU; the
# operator resolves it manually with a profile-scoped compose stop.
if [ -n "$SINGLE_RUNNING" ] && [ -n "$BATCH_RUNNING" ]; then
  echo "[switch] error: both profiles 'single' and 'batch' are running — one GPU," \
       "one profile at a time (docker-compose.yml:22). Resolve manually, e.g." \
       "docker compose --profile batch stop, then re-run; aborting without" \
       "touching anything." >&2
  exit 1
fi

if [ -n "$NOARG" ]; then
  # D-03 no-arg resolution chain (both-running already rejected above).
  if [ -n "$SINGLE_RUNNING" ]; then
    TARGET=batch
    RESOLVED_FROM="no-arg: single is running -> targeting the other profile"
  elif [ -n "$BATCH_RUNNING" ]; then
    TARGET=single
    RESOLVED_FROM="no-arg: batch is running -> targeting the other profile"
  else
    # Neither running: .current-profile token, tolerantly read (a missing
    # file yields an empty token, never an abort); anything outside the
    # whitelist — absent, blank, corrupt — lands on the same default
    # `single` (D-01, SWITCH-03).
    SAVED=
    if [ -f "$STATE_FILE" ]; then
      SAVED=$(cat "$STATE_FILE" 2>/dev/null || true)
    fi
    SAVED="${SAVED#"${SAVED%%[![:space:]]*}"}"   # strip leading whitespace
    SAVED="${SAVED%"${SAVED##*[![:space:]]}"}"   # strip trailing whitespace
    case "$SAVED" in
      single|batch) TARGET=$SAVED; RESOLVED_FROM="no-arg: neither running -> .current-profile" ;;
      *)            TARGET=batch; RESOLVED_FROM="no-arg: neither running, no valid .current-profile -> default batch" ;;
    esac
  fi
else
  RESOLVED_FROM="explicit argument"
fi

echo "[switch] resolved target: '$TARGET' ($RESOLVED_FROM)"

# ---- D-04 idempotent no-op ----------------------------------------------------
# Target already running: do not restart it — refresh the state file and exit 0.
# (The refresh is safe to write unconditionally here: the profile is
# demonstrably running, unlike a switch whose state write waits for up -d.)
if [ "$TARGET" = single ]; then
  TARGET_RUNNING=$SINGLE_RUNNING
else
  TARGET_RUNNING=$BATCH_RUNNING
fi
if [ -n "$TARGET_RUNNING" ]; then
  printf '%s\n' "$TARGET" > "$STATE_FILE"
  echo "[switch] profile '$TARGET' is already running — no-op; refreshed .current-profile"
  exit 0
fi

if [ "$TARGET" = single ]; then
  OTHER=batch
else
  OTHER=single
fi

# ---- stop the outgoing profile (D-07) -----------------------------------------
# `stop` (not `down`): restart: unless-stopped keeps an explicitly-stopped
# container down, and stop_grace_period: 30s means this can take ~30s.
# Tolerate the outgoing profile not running (compose stop is a no-op success
# with no matching container); abort only if containers are genuinely still up.
echo "[switch] target profile '$TARGET'; stopping outgoing profile '$OTHER'"
if ! docker compose --profile "$OTHER" stop; then
  STILL_RUNNING=$(docker compose ps -q "$OTHER" 2>/dev/null || true)
  if [ -n "$STILL_RUNNING" ]; then
    echo "[switch] error: compose stop of profile '$OTHER' failed" >&2
    exit 1
  fi
  echo "[switch] note: profile '$OTHER' was not running (nothing to stop)"
fi

# ---- VRAM-release gate (D-05, SWITCH-04) -------------------------------------
# Mirror of single-user/qwen-serving.service:10: poll up to 60 times at a 2s
# cadence and require < 1000 MiB used before starting anything. On exhaustion
# the target is NOT started (exit 1, state file untouched) — profiling against
# unreleased VRAM permanently shrinks the KV pool with no error in any log.
gpu_free=0
for i in $(seq 1 60); do
  u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null) \
    || { echo "[switch] error: nvidia-smi query failed; '$TARGET' was NOT started" >&2; exit 1; }
  if [ "$u" -lt 1000 ]; then
    gpu_free=1
    break
  fi
  sleep 2
done
if [ "$gpu_free" -ne 1 ]; then
  echo "[switch] error: GPU memory did not free within 60 attempts (2s apart);" \
       "profile '$TARGET' was NOT started" >&2
  exit 1
fi

# ---- KV-cache pin (D-06, SWITCH-04) -------------------------------------------
# Pin the single-profile KV pool by bytes, set-if-unset only: a KV_MEM value
# from the environment — including the documented KV_MEM= empty escape hatch,
# which sizes the pool from GPU_UTIL — always wins. Plus-form test: ${KV_MEM+x}
# expands to x exactly when KV_MEM is set (even to the empty string), so the
# pin applies only when KV_MEM is entirely unset. batch stays stock.
if [ "$TARGET" = single ] && [ -z "${KV_MEM+x}" ]; then
  export KV_MEM=5583457484
fi

# ---- start the target (D-07) --------------------------------------------------
# Fire-and-forget: no health-wait here — the compose healthcheck owns that,
# and the unprofiled prepare service re-runs idempotently via depends_on.
echo "[switch] starting profile '$TARGET'"
if ! docker compose --profile "$TARGET" up -d; then
  echo "[switch] error: compose up of profile '$TARGET' failed" >&2
  exit 1
fi

# ---- persist the choice (D-01/D-02, SWITCH-02) --------------------------------
# Write AFTER up -d succeeded — a failed or aborted switch must never update
# the state file; the Phase 3 boot hook trusts it blindly. Exactly one token.
printf '%s\n' "$TARGET" > "$STATE_FILE"
echo "[switch] profile '$TARGET' is up; choice persisted to .current-profile"
