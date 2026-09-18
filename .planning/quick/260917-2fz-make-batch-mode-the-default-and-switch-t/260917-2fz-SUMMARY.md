---
status: complete
completed_at: 2026-09-17T07:45:35.393Z
---

# Quick Task Summary: Make batch mode the default and switch to it now

## Description
Make batch mode the default profile and switch to it now.

## Changes Made
1. **Modified `switch.sh`** (line 109): Changed the default profile from `single` to `batch` when no profile is running and no `.current-profile` exists.
   - Before: `TARGET=single; RESOLVED_FROM="no-arg: neither running, no valid .current-profile -> default single"`
   - After: `TARGET=batch; RESOLVED_FROM="no-arg: neither running, no valid .current-profile -> default batch"`

2. **Switched to batch mode** by running `./switch.sh batch`:
   - Stopped the running `single` profile
   - Waited for GPU memory to free (< 1000 MiB)
   - Started the `batch` profile
   - Persisted choice to `.current-profile` (now contains `batch`)

## Verification
- ✅ `switch.sh` default changed to `batch`
- ✅ `./switch.sh batch` executed successfully
- ✅ Batch profile is running (container `qwen38-27b-rtx3090-batch-1` is up)
- ✅ `.current-profile` contains `batch`
- ✅ When neither profile running and no `.current-profile`, `./switch.sh` defaults to `batch`

## Commit
Commit: 960cca5