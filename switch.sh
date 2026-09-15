#!/bin/bash
# Switch this one-GPU Qwen3.8-27B stack between the "single" (low-latency,
# speculative decoding) and "batch" (throughput) Compose profiles: stop the
# outgoing profile, wait for the GPU to actually free, start the requested
# profile, and persist the choice to .current-profile at the repo root
# (gitignored runtime state; the Phase 3 boot hook reads it).
#
#   ./switch.sh single    # switch to single-user (low-latency) mode
#   ./switch.sh batch     # switch to batch (throughput) mode
#   ./switch.sh           # no-arg resolution arrives with the next task
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

# ---- argument whitelist (D-03 first clause; truth 8) -------------------------
# Only the literal tokens single/batch ever reach a compose command; an
# unvalidated argument is never interpolated anywhere. An invalid invocation
# touches no container and no state file.
if [ $# -gt 1 ]; then
  echo "[switch] error: expected at most one argument (single|batch), got $#" >&2
  usage >&2
  exit 2
fi

TARGET=
case "${1:-}" in
  single|batch) TARGET=$1 ;;
  -h|--help)    usage; exit 0 ;;
  "")           echo "[switch] error: no profile given" >&2; usage >&2; exit 2 ;;
  *)            echo "[switch] error: unknown profile '$1' (expected single or batch)" >&2; usage >&2; exit 2 ;;
esac

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
