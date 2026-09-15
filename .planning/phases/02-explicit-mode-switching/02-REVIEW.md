---
phase: 02-explicit-mode-switching
reviewed: 2026-09-15T02:15:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - switch.sh
  - .gitignore
findings:
  critical: 0
  warning: 1
  info: 4
  total: 5
status: issues_found
---

# Phase 02: Code Review Report

**Reviewed:** 2026-09-15T02:15:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Reviewed `switch.sh` (198 lines, bash) and `.gitignore` (17 lines) from Phase 02 Plan 01. The implementation delivers a robust one-command profile switcher with verbatim VRAM gate mirroring, set-if-unset KV cache pin, write-after-success state persistence, and comprehensive no-arg resolution. The code is well-structured with `set -e`, guarded compose calls, whitelist-only token interpolation, and clear `[switch]`-prefixed logging.

One **Warning** finding: the VRAM gate assumes single-GPU `nvidia-smi` output (one numeric line). Four **Info** findings cover bash-specific whitespace stripping, magic numbers, symlink-related `.gitignore` entries, and the acknowledged concurrency assumption.

## Warnings

### WR-01: VRAM gate assumes single-line nvidia-smi output (single GPU)

**File:** `switch.sh:161-163`
**Issue:** The VRAM gate captures `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits` output into variable `u` and tests `[ "$u" -lt 1000 ]`. If multiple GPUs are present, `nvidia-smi` emits multiple lines (one per GPU), causing the integer comparison to fail with "integer expression expected" and the gate to behave unpredictably. The project context (PROJECT.md:46) confirms a single RTX 3090, so this is not a current defect, but the assumption is not explicitly guarded or documented in the script.
**Fix:** Add a guard to take the first line (GPU 0) explicitly, or document the single-GPU assumption in the gate comment block. For example:
```bash
u=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits 2>/dev/null | head -n1) \
  || { echo "[switch] error: nvidia-smi query failed; '$TARGET' was NOT started" >&2; exit 1; }
```

## Info

### IN-01: Bash-specific whitespace stripping for state token

**File:** `switch.sh:105-106`
**Issue:** The leading/trailing whitespace stripping uses bash parameter expansion patterns (`${var#pattern}`, `${var%pattern}`) with extended globs (`[![:space:]]`). This works in bash (the shebang is `#!/bin/bash`) but is non-POSIX and less readable than alternatives like `read -r` or `sed`.
**Fix:** Consider using a more readable approach, e.g.:
```bash
SAVED=$(cat "$STATE_FILE" 2>/dev/null || true)
SAVED=$(printf '%s' "$SAVED" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
```
Or with `read -r` (handles missing file via `|| true`):
```bash
SAVED=
[ -f "$STATE_FILE" ] && { read -r SAVED < "$STATE_FILE" 2>/dev/null || true; }
SAVED=${SAVED##[[:space:]]}; SAVED=${SAVED%%[[:space:]]}
```

### IN-02: Magic numbers in VRAM gate and KV pin not named

**File:** `switch.sh:159-168, 182`
**Issue:** The VRAM gate uses literal values `60` (attempts), `2` (sleep seconds), `1000` (MiB threshold), and the KV pin uses `5583457484` (bytes). While these mirror `qwen-serving.service:10` exactly per D-05/D-06 requirements, naming them as constants would improve maintainability and self-documentation.
**Fix:** Define constants at the top of the script:
```bash
VRAM_GATE_ATTEMPTS=60
VRAM_GATE_CADENCE=2
VRAM_GATE_THRESHOLD_MIB=1000
SINGLE_KV_MEM_BYTES=5583457484
```

### IN-03: Duplicate .gitignore entries for symlinked directories

**File:** `.gitignore:13-17`
**Issue:** Lines 14-17 repeat `venv`, `models`, `api_key.txt`, `bench/results/` without trailing slashes, with a comment "local reproduction artifacts (symlinks here, so no trailing slash)". These duplicate the earlier directory entries (lines 2, 5, 8, 3-4) which have trailing slashes. While functionally harmless (git ignores both), the duplication is confusing and the symlink rationale belongs in a README or setup doc, not in `.gitignore`.
**Fix:** Remove the duplicate lines 14-17, or consolidate with a single comment explaining the symlink strategy. The current `.gitignore` at lines 1-11 already covers the ignored patterns correctly.

### IN-04: Concurrency assumption (A-1) not documented in switch.sh

**File:** `switch.sh` (header comment)
**Issue:** The plan documents assumption A-1 (PLAN.md:135-140): `switch.sh` holds no lock; concurrent invocations could interleave stop/up and violate the one-GPU invariant or race the state-file write. The assumption is "single-user host, human-initiated script, never invoked in parallel." This is not mentioned in the script's header comment, so a future maintainer might not know this limitation.
**Fix:** Add a note in the header comment block:
```bash
# Concurrency: NOT safe for parallel invocation. Assumes single-user,
# human-initiated sequential use. No locking mechanism is implemented.
```

---

_Reviewed: 2026-09-15T02:15:00Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_