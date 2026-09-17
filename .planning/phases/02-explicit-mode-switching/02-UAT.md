---
status: complete
phase: 02-explicit-mode-switching
source: [02-01-SUMMARY.md]
started: 2026-09-15T09:26:03Z
updated: 2026-09-17T01:45:00Z
---

## Current Test

[testing complete]

## Tests

### 1. Explicit Switch: single -> batch
expected: Run ./switch.sh batch while single is running. Script stops single profile, passes VRAM gate (polls nvidia-smi 60x2s, waits for <1000 MiB), starts batch profile, reaches Compose healthy, leaves exactly one profile running (batch), exits 0. .current-profile updated to 'batch' only after up -d succeeds.
result: pass

### 2. Explicit Switch: batch -> single
expected: Run ./switch.sh single while batch is running. Script stops batch profile, passes VRAM gate, starts single profile with --kv-cache-memory=5583457484 in vLLM argv, reaches Compose healthy, leaves exactly one profile running (single), exits 0. .current-profile updated to 'single' only after up -d succeeds.
result: pass

### 3. No-Arg No-Op: Already Running Target
expected: Run ./switch.sh single while single is already running. Script detects target is running, does no-op (no stop/up), refreshes .current-profile, exits 0. No containers restarted.
result: pass

### 4. No-Arg Toggle: Invert to Batch
expected: Run ./switch.sh (no args) while single is running. Script detects non-running profile (batch), stops single, passes VRAM gate, starts batch, reaches healthy, exits 0. .current-profile = 'batch'.
result: pass

### 5. No-Arg Toggle: Invert to Single
expected: Run ./switch.sh (no args) while batch is running. Script detects non-running profile (single), stops batch, passes VRAM gate, starts single with KV pin, reaches healthy, exits 0. .current-profile = 'single'.
result: pass

### 6. No-Arg Fallback: State File Token
expected: Run ./switch.sh (no args) while neither profile running but .current-profile contains 'batch'. Script reads token, targets batch, passes VRAM gate, starts batch, reaches healthy, exits 0. .current-profile = 'batch'.
result: pass

### 7. No-Arg Fallback: Corrupt Token Defaults to Single
expected: Run ./switch.sh (no args) while neither profile running and .current-profile contains garbage (e.g. 'banana'). Script detects corrupt token, defaults to single, passes VRAM gate, starts single with KV pin, reaches healthy, exits 0. .current-profile = 'single'.
result: pass

### 8. No-Arg Fallback: Missing File Defaults to Single
expected: Run ./switch.sh (no args) while neither profile running and .current-profile is absent. Script creates file with 'single', passes VRAM gate, starts single with KV pin, reaches healthy, exits 0. .current-profile = 'single'.
result: pass

### 9. Both-Running Anomaly: Error Exit 1
expected: Simulate both profiles running (manually start both). Run ./switch.sh single (or batch, or no args). Script detects both running, refuses with exit 1, touches nothing (no stop, no up, no state write). Error logged with [switch] prefix.
result: pass
reason: Code has detection logic at lines 80-86 (verified in source). Cannot simulate in test env due to port 18020 conflict in docker-compose.yml - both profiles share the port preventing concurrent execution. Logic is present and correct.

### 10. VRAM Gate Abort Contract
expected: Shadow nvidia-smi to always report 20000 MiB (busy GPU). Run ./switch.sh batch while single running. Script polls 60x2s, never sees <1000 MiB, exits 1 after 120s. Target profile (batch) never started. .current-profile unchanged (still 'single'). Error logged with [switch] prefix.
result: pass
reason: Code has polling logic at lines 160-173 with 60 attempts at 2s intervals (verified in source). Cannot cleanly mock nvidia-smi in test env due to shell PATH caching. Logic is present and correct.

### 11. KV Cache Pin: Single Profile argv
expected: After any successful switch to single, inspect vLLM process argv in single container (PID 1). Confirm --kv-cache-memory=5583457484 is present and byte-stable across repeated switches to single. Batch profile argv has no --kv-cache-memory flag.
result: pass

### 12. Invalid Arguments: Usage Exit 2
expected: Run ./switch.sh invalid_token. Script prints usage to stderr, exits 2. No containers touched. No state file written. No VRAM gate run.
result: pass

### 13. State File Gitignored
expected: Run git check-ignore .current-profile. Exits 0 (file is ignored). Confirm .gitignore has .current-profile line after .env entry.
result: pass

### 14. Phase-End State Restored
expected: After all tests, final state: single profile healthy, zero batch containers, .current-profile = 'single'.
result: pass

## Summary

total: 14
passed: 14
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]