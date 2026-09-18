---
phase: 03-boot-autostart
verified: 2026-09-18T10:10:25Z
status: human_needed
score: 6/8
covered_files:
  - ".planning/PROJECT.md"
  - ".planning/REQUIREMENTS.md"
  - ".planning/ROADMAP.md"
  - ".planning/phases/03-boot-autostart/03-01-PLAN.md"
  - ".planning/phases/03-boot-autostart/03-01-SUMMARY.md"
  - ".planning/phases/03-boot-autostart/03-02-PLAN.md"
  - ".planning/phases/03-boot-autostart/03-02-SUMMARY.md"
  - "switch.sh"
covered_digest: "v1:sha256:bb32b99ad233878287b1e7ddc33eec6a37128e8654245689cb0d1345609346f7"
behavior_unverified: 2
overrides_applied: 0
behavior_unverified_items:
  - truth: "No persisted state -> the boot hook starts batch (ROADMAP SC3 / BOOT-02)"
    test: "In WSL: mv .current-profile .current-profile.bak ; then from Windows: wsl --shutdown ; reopen WSL; wait for the boot chain; check tail /var/log/local-llm-boot.log and docker compose ps; then restore the file"
    expected: "A fresh log line 'OK: profile=batch (from .current-profile=<absent>; ...)' and the batch container Up. CAUTION (review IN-02): the default-applied= field will misreport 'no' in exactly this case (inverted test) — judge from the from .current-profile=<absent> field and the started batch profile, not from default-applied=yes"
    why_human: "Requires mutating runtime state (removing .current-profile) and a real wsl --shutdown reboot (Windows interop, outside the sandbox). The only recorded boot (2026-09-18) had .current-profile=batch, so the default branch has never been exercised at runtime"
  - truth: "The wrapper's up -d branch starts the persisted profile when the container is not already up (03-01 must-have T3 start branch)"
    test: "In WSL: docker compose --profile batch down (stop the batch service); then from Windows: wsl --shutdown ; reopen WSL; wait; check tail /var/log/local-llm-boot.log and docker compose ps"
    expected: "A fresh log line 'OK: profile=batch ...; already-running-before-up=no' and the batch container Up (health may read 'starting' for up to ~15 min — the 900s compose start period is not a fault)"
    why_human: "Requires creating a down-container state (mutation) and a real wsl --shutdown reboot. The only recorded boot hit the already-running branch — the docker daemon's restart: unless-stopped policy brought the container up before the wrapper's up -d ran — so the actual start transition has never been exercised"
human_verification:
  - test: "Prove the boot hook's own start path: docker compose --profile batch down, then wsl --shutdown + reopen WSL"
    expected: "Fresh /var/log/local-llm-boot.log line with already-running-before-up=no; docker compose ps shows batch-1 Up (health may be 'starting' for up to ~15 min)"
    why_human: "Requires a stopped-container state and a real VM reboot (wsl --shutdown is Windows interop the sandbox cannot perform)"
  - test: "Prove the no-persisted-state default: move .current-profile aside, then wsl --shutdown + reopen WSL, then restore it"
    expected: "Fresh log line 'from .current-profile=<absent>' with profile=batch and the batch container Up (note: default-applied= misreports 'no' here — review IN-02 — so judge on the <absent> field and the batch profile)"
    why_human: "Requires mutating the runtime state file and a real VM reboot"
---

# Phase 3: Boot Autostart Verification Report

**Phase Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `batch` if nothing was ever chosen. (ROADMAP.md Phase 3; success criteria: (1) boot hook follows /etc/wsl.conf [boot] chezmoi wrapper convention, no systemd; (2) after wsl --shutdown + reopen the persisted profile's container comes up unaided; (3) no persisted state -> hook starts batch; (4) re-running installer is a no-op.)

**Verified:** 2026-09-18T10:10:25Z
**Status:** human_needed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | A boot hook is installed following the `/etc/wsl.conf [boot]` chezmoi wrapper convention (sits alongside `paseo-boot-start`, no systemd) — SC1 | ✓ VERIFIED | `/etc/wsl.conf:17` carries the combined `[boot]` line; `/usr/local/bin/local-llm-start` installed (mode 755, `bash -n` clean, 2984 B); source of truth is the committed dotfiles template `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl` (commit `fba1a8a`) — same `run_onchange`/`su -l`/no-systemd pattern as the 04 paseo template; zero systemd references anywhere in the chain |
| 2 | The combined `[boot]` line is byte-exact: paseo prefix first, single `;`, no trailing quote, no pipe (03-01 T2) | ✓ VERIFIED | `od -c` of /etc/wsl.conf tail: `...oot-start" ; /usr/local/bin/local-llm-start\n` — no trailing quote, one `;`; `grep -c '\|' /etc/wsl.conf` = 0 (no pipe in the whole file). 04 template's `grep -qF` anchor (`command = "/usr/local/bin/paseo-boot-start"`) is a substring of the line, so both templates converge to no-op (convergence independently re-checked by 03-REVIEW.md) |
| 3 | After `wsl --shutdown` + reopen, the persisted profile's container comes up unaided — SC2 | ✓ VERIFIED | Live 2026-09-18: VM start 03:26:34 -0600 (`uptime -s`); boot log line `[2026-09-18T09:26:43Z] OK: profile=batch (from .current-profile=batch; default-applied=no); already-running-before-up=yes` = 9 s after VM start, 3 min after the wrapper's 03:23:45 install; `docker compose ps` shows `qwen38-27b-rtx3090-batch-1` `Up 33 minutes (healthy)` on 0.0.0.0:18020. **Caveat (see truth 8):** the container's actual start came from the docker daemon's `restart: unless-stopped` policy (paseo-boot-start starts dockerd first in the same `[boot]` chain); the wrapper's own `up -d` was a confirming no-op. The plan's Task-2 contract explicitly accepts this variant as the desired state being achieved |
| 4 | No persisted state -> the hook starts `batch` — SC3 / BOOT-02 | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | The installed wrapper carries the verbatim tolerant read (missing/blank/whitespace/corrupt all resolve to `PROFILE=batch`; whitelist `single|batch` before any interpolation — mirror of `switch.sh:96-114`), present and wired. But the only recorded boot had `.current-profile=batch` (`default-applied=no`), so the no-state -> batch branch has never been exercised at runtime and no test covers it — see Human Verification #2 |
| 5 | Re-running the boot-hook installer (`chezmoi apply`) is a no-op — SC4 / BOOT-03 | ✓ VERIFIED | Observed re-apply (2026-09-18): `run_onchange` hash-skip left the 045 script un-re-executed; orchestrator-side `chezmoi apply --dry-run --verbose --force` emitted zero pending actions (045 not re-run); wrapper mtime still the 03:23:45 install time (frozen through the re-apply); the `[boot]` line remained byte-exact with no duplicated marker. The inner `grep -qF` gate adds defense-in-depth for forced re-runs. (Plan's literal "must print the no-change path" expectation was corrected against `run_onchange` skip semantics — 03-01 Deviation 2; substance verified twice over) |
| 6 | Commit hygiene: the dotfiles commit adds only the 045 template + the 04 ps1 comment and is never pushed; the qwen-repo commits never stage `.current-profile` / `.gsd/` / `state.json` (03-01 T5, 03-02 T12) | ✓ VERIFIED | dotfiles `git show --name-only --format='' fba1a8a` lists exactly the two templates; `git log @{u}..HEAD` = 1 (still unpushed — the plan's prohibition holds, and the reboot that would unlock a push has since happened, so a push is now *permitted* but is the user's call, not a phase requirement). qwen `85fbb99` = exactly 3 files (REQUIREMENTS, state.json, quick SUMMARY); `d746902` = exactly 4 files (PROJECT, REQUIREMENTS, ROADMAP, switch.sh); `.gsd/` and `.current-profile` untracked, in neither commit; `switch.sh` diff in `d746902` is the single header-comment line (code untouched) |
| 7 | 03-02 doc alignment: all eight D-10 locations state the `batch` default; do-not-touch items byte-identical (03-02 T6–T11) | ✓ VERIFIED | REQUIREMENTS: BOOT-02 "starts `batch` by default" + Core Value "with batch as the safe default"; ROADMAP: goal "defaulting to `batch` if nothing was ever chosen" + criterion 3 "the boot hook starts `batch`"; PROJECT: Key Decisions row "Default profile is `batch` on first run … ✓ Good" + Core Value + active-requirement line; switch.sh header line 12 "absent/blank/corrupt -> batch" matching line-109 code `*) TARGET=batch`. Do-not-touch items intact: SWITCH-03 line 18 still "defaults to `single`" (completed historical requirement, stale-by-design per 03-02), switch.sh inline comment 97-100 still says `single`, the GSD mirrors (`STATE.md:25`, `.claude/CLAUDE.md`) untouched by `d746902` (absent from its file list) and still carry the stale sentence by design — they resync from PROJECT.md at the next GSD state update |
| 8 | The wrapper's `up -d` branch starts the profile when the container is not already up (03-01 T3 start branch) | ⚠️ PRESENT_BEHAVIOR_UNVERIFIED | Code present and wired: `ALREADY=$(docker compose ps -q "$PROFILE")` forensics check, then `su -l "pengwin" -c '… docker compose --profile "$PROFILE" up -d'` (username expanded, mise-activate prelude byte-identical to the 04 wrapper, fire-and-forget, no `/health` wait, no VRAM gate — both prohibitions hold by inspection). But the only recorded boot hit the *other* branch (`already-running-before-up=yes`): the daemon's restart policy beat the wrapper, so the actual start transition has never been exercised — see Human Verification #1 |

**Score:** 6/8 truths verified (2 present + wired, behavior not yet exercised — see behavior_unverified_items)

### Deferred Items

None — no failed truth is scheduled for a later phase (this is the last phase of the milestone; the two behavior-unverified items are testable by the user on the live machine now, not deferred work).

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl` (dotfiles repo) | The boot-hook source of truth (D-03) | ✓ VERIFIED | On disk byte-identical to committed `fba1a8a` (no uncommitted drift); renders: `chezmoi apply --dry-run` clean; installs the wrapper + patches the `[boot]` line; cleanup branch for non-GPU/non-personal hosts |
| `/usr/local/bin/local-llm-start` | Runtime wrapper, mode 755, untracked | ✓ VERIFIED | `-rwxr-xr-x`, 2984 B, installed 2026-09-18 03:23:45 -0600; content matches the template heredoc exactly with `su -l "pengwin"` expansion; `bash -n` passes; executed at the recorded boot (log line 9 s after VM start) |
| `/etc/wsl.conf` `[boot]` line | Combined paseo + local-llm-start line, untracked | ✓ VERIFIED | Line 17 byte-exact (od-verified); single `[boot]` section (line 16); no pipe, no trailing quote |
| `/usr/local/bin/paseo-boot-start` | Pre-existing paseo wrapper, unmodified by this phase | ✓ VERIFIED | 1076 B, mtime 2026-09-14 (pre-phase); content is the 04 template's heredoc only — no qwen block appended (prohibition holds) |
| `/var/log/local-llm-boot.log` | Boot forensics (D-13) | ✓ VERIFIED | Contains the post-reboot `OK:` line; log path has no `local-llm-boot-boot` typo |
| `.chezmoiscripts/run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl` (dotfiles) | Comment-only note that 04 + 045 co-manage the `[boot]` line | ✓ VERIFIED | Lines 13-17 reference both templates; in commit `fba1a8a`; no behavioral change (review IN: confirmed comment-only) |
| 03-02 doc files (REQUIREMENTS, ROADMAP, PROJECT, switch.sh header) | Aligned to the locked `batch` default | ✓ VERIFIED | All eight locations verified in truth 7 above |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| chezmoi 045 template | `/usr/local/bin/local-llm-start` | `sudo tee` heredoc (install path only) + `chmod 755` + idempotent marker gate | ✓ WIRED | Installed file matches the template body byte-for-byte (username expansion included); mtime frozen on re-apply |
| chezmoi 045 template | `/etc/wsl.conf [boot]` → both wrappers at VM start | replace-not-append `sed` (paseo prefix first), post-mutation self-check of both markers | ✓ WIRED | Live line byte-exact; the `[boot]` chain demonstrably ran at the 2026-09-18 VM start (log line 9 s after `uptime -s`; dockerd up, hence the restart-policy container start) |
| `switch.sh` | `.current-profile` → read by `/usr/local/bin/local-llm-start` | `switch.sh:197` `printf '%s\n' "$TARGET" > "$STATE_FILE"` after a successful `up` (also line 128 no-op refresh); wrapper reads it tolerantly with whitelist | ✓ WIRED | File contains `batch` — the profile that is running and that the boot log reports; hand-off contract (write only after success, read tolerantly) holds |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| boot chain → running container | `.current-profile` token → `docker compose --profile <p>` | Real file at repo root, written by `switch.sh` after each successful switch | Yes — live container `qwen38-27b-rtx3090-batch-1` (23 h old, restarted on the 2026-09-18 boot, healthy, serving on :18020) | ✓ FLOWING |
| boot log forensics | `SAVED` / `PROFILE` / `ALREADY` from the state file and `docker compose ps` | Live reads at boot | Yes — the recorded `OK:` line reflects the real state at that moment | ✓ FLOWING |

No static returns, hardcoded literals, or mocks anywhere in the boot path — every value traces to a live source.

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Wrapper is syntactically valid bash | `bash -n /usr/local/bin/local-llm-start` | exit 0 (also `bash -n` on the paseo wrapper) | ✓ PASS |
| Combined `[boot]` line byte-exact, no pipe, no trailing quote | `grep -n 'command =' /etc/wsl.conf`; `grep -c '\|' /etc/wsl.conf`; `od -c` tail | `17:command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start`; 0 pipes; ends `local-llm-start\n` | ✓ PASS |
| Boot chain executed at the recorded VM start | `uptime -s` vs `tail /var/log/local-llm-boot.log` | VM start 03:26:34 -0600; log `OK:` at 09:26:43Z = 03:26:43 -0600, 9 s after VM start, 3 min after wrapper install | ✓ PASS |
| Persisted profile's container up + healthy | `docker compose ps` (qwen repo) | `qwen38-27b-rtx3090-batch-1 … Up 33 minutes (healthy)` on 0.0.0.0:18020 | ✓ PASS |
| Re-apply leaves installer artifacts untouched | wrapper `stat` + `[boot]` line after the 2nd apply | mtime still 03:23:45 install time; line byte-exact, no duplicate marker; dry-run verbose: zero pending actions | ✓ PASS |

### Probe Execution

SKIPPED — no `scripts/*/tests/probe-*.sh` probes are declared or conventional for this phase (not a migration/tooling phase). The behavioral test for this phase is the human `wsl --shutdown` + reopen reboot, which was performed 2026-09-18 and whose evidence was independently re-verified from this sandbox (read-only).

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| BOOT-01 | 03-01 | WSL boot hook (existing `/etc/wsl.conf [bot]` chezmoi wrapper convention, not systemd) starts the last-persisted profile after `wsl --shutdown` + restart | ✓ SATISFIED | Live hook installed + combined `[boot]` line + recorded reboot evidence (truths 1, 3). Checkbox still `[ ]` in REQUIREMENTS.md — the flip is the orchestrator's phase-completion bookkeeping (03-02 explicitly left it; 03-01 records `requirements-completed: [BOOT-01, BOOT-02, BOOT-03]`) |
| BOOT-02 | 03-01, 03-02 | No profile ever selected -> boot hook starts `batch` | ⚠️ CODE SATISFIED, RUNTIME PENDING HUMAN | Wrapper's verbatim tolerant read resolves missing/blank/corrupt to `batch` (inspected in the installed file); documented wording aligned across all four docs. The no-state runtime branch has not been exercised — Human Verification #2 |
| BOOT-03 | 03-01 | Boot-hook installation is idempotent (safe to re-run, matches the paseo-boot-start wrapper pattern) | ✓ SATISFIED | Re-apply observed as a true no-op (hash skip + frozen mtime + byte-exact line + zero pending actions); matches the paseo convention's marker-anchored idempotency (truth 5) |

**Orphan check:** every Phase-3-mapped requirement in REQUIREMENTS.md (BOOT-01, BOOT-02, BOOT-03) is claimed by a plan's frontmatter (03-01: all three; 03-02: BOOT-02). No orphaned or dangling IDs.

### Prohibitions (must-NOT)

| Prohibition | Status | Evidence |
|-------------|--------|----------|
| 03-01: never append a qwen block into `/usr/local/bin/paseo-boot-start` | ✓ NOT VIOLATED | paseo wrapper mtime 2026-09-14 (pre-phase), 1076 B, content is the 04 heredoc only — no qwen block |
| 03-01: no trailing double-quote or pipe on the combined `[boot]` line | ✓ NOT VIOLATED | od dump ends `local-llm-start\n`; 0 pipes in the whole file |
| 03-01: no `/health` block at boot (Compose healthcheck owns it) | ✓ NOT VIOLATED | installed wrapper contains no `/health` reference — fire-and-forget `up -d` only |
| 03-01: no VRAM-release gate at boot | ✓ NOT VIOLATED | no `nvidia-smi`/VRAM check in the wrapper |
| 03-01: raw `.current-profile` bytes never interpolated into a command (T-03-01) | ✓ NOT VIOLATED | whitelist `case` (`single|batch`, default `batch`) precedes any use; `SAVED` only compared/logged, never executed |
| 03-01: dotfiles commit never pushed in this plan; qwen runtime state never staged | ✓ NOT VIOLATED | `fba1a8a` still unpushed (1 ahead of upstream); qwen commits' file lists contain no `.current-profile`/`.gsd`/`state.json` beyond the two planned commits' declared sets |
| 03-02: do-not-touch items byte-identical (SWITCH-03 line 18, switch.sh inline 97-100, GSD mirrors, `.gsd/`) | ✓ NOT VIOLATED | all four verified intact (truth 7); mirrors absent from `d746902`'s file list |
| 03-02: no `.gsd/` / `.current-profile` staged; no push from the plan; switch.sh code untouched | ✓ NOT VIOLATED | negative file-list checks pass; `d746902`'s `switch.sh` diff is the single header-comment line. (Note: `origin/main` is now at `655f88a`, i.e. the earlier qwen commits have since been pushed by the user/orchestrator outside plan execution — that is post-plan activity, not a plan violation; the 3 most recent bookkeeping commits remain unpushed) |

### Anti-Patterns Found

No `TBD`/`FIXME`/`XXX` debt markers in any phase-3 artifact or modified code file. No stubs: the 045 template is a complete 154-line script, the installed wrapper is complete and executed, and no hardcoded/empty returns feed user-visible output. The one stale comment (`switch.sh:97-100` "lands on the same default `single`") is a deliberate do-not-touch item (03-02 scope) and is carried in the advisory list below (WR-01) rather than as an anti-pattern.

### Advisory (New Scope / Carry-Forward)

Non-blocking findings from `03-REVIEW.md` (mode: advisory, "no blockers") plus this verification's own scan:

| # | Finding | Category | Why Advisory |
|---|---------|----------|--------------|
| 1 | WR-01: `switch.sh:97-100` inline comment still says "lands on the same default `single`" while line 109 implements `batch` — a future editor could "fix" the code back to `single` | docs | Deliberate do-not-touch (03-02); fix is a one-line comment edit for a future cleanup task |
| 2 | WR-02: D-11 blind spot — a future *wrapper-body* edit changes the chezmoi hash, the script re-runs, but the inner marker gate then skips, so the edit silently never lands (the 04 sibling rewrites unconditionally) | architectural | Known trade-off documented in 03-01; suggested fix: version marker in the wrapper compared before skipping |
| 3 | WR-03: foreign-`command` branch echoes "WARNING … not touching it" then falls through to the self-check, which `exit 1`s — message/exit disagree (near-dead branch: 04 runs first lexically and aggressively adopts foreign lines) | shell-correctness | Rare path; fix is a two-line message/exit change in the 045 template |
| 4 | IN-02: boot-log `default-applied=` misreports the absent-file first-boot case as `no` (inverted test) — the most common default event logs as not-applied | forensics | Log-field only, but it directly affects Human Verification #2's evidence reading (flagged there) |
| 5 | IN-01: `SWITCH-03` `[x]` "defaults to `single`" vs BOOT-02's `batch` with no in-file pointer to the amendment | docs | Documented stale-by-design historical record; suggested inline note |
| 6 | IN-03: unused loop variable in the docker-readiness poll (`for i in $(seq 1 60)`) | cosmetic | shellcheck SC2034 only |
| 7 | Uncommitted `apm.yml` + untracked `opencode.json`/`.mcp.json` in the dotfiles repo (mtime 02:27:17 -0600, same second as `opencode.json`; adds a personal `home-assistant` MCP entry with the user's own HASS URL) — inside the 03-01 window but not in any commit and not claimed by either SUMMARY ("Files modified: 2") | scope observation | Attribution points to user personalization, not the GSD executor (the executor only ran dry-run `chezmoi apply`, which writes no source files; `mise run format` cannot add an MCP entry). No impact on the boot-hook goal; noted so the dotfiles working tree isn't a mystery later |
| 8 | Bookkeeping pending at phase completion (orchestrator's): REQUIREMENTS BOOT-01..03 checkboxes still `[ ]` + traceability "Pending"; PROJECT line 65 "Boot autostart … — Pending" marker; GSD mirrors `STATE.md:25` / `.claude/CLAUDE.md:19` still carry the stale `single-user` Core Value (they resync from PROJECT.md on the next GSD state update); unpushed `fba1a8a` (now permitted to push post-reboot) and 3 unpushed qwen bookkeeping commits | docs | Expected state at verification time — these flips belong to the post-verification phase-completion step, not to this phase's plans |

### Human Verification Required

Two runtime branches were never exercised (the only recorded boot hit the already-running case with `.current-profile=batch` present). Both are human-only: they require state mutations and a real `wsl --shutdown` (Windows interop outside this sandbox).

### 1. Prove the boot hook's own start path (wrapper `up -d` branch)

**Test:** In WSL: `docker compose --profile batch down` (or `docker stop qwen38-27b-rtx3090-batch-1`). From a Windows terminal: `wsl --shutdown`. Reopen WSL and wait for the `[boot]` chain (the compose healthcheck's 900 s start period means "healthy" can legitimately take up to ~15 min).
**Expected:** `tail /var/log/local-llm-boot.log` shows a fresh `OK: profile=batch (from .current-profile=batch; …); already-running-before-up=no` line; `docker compose ps` shows `batch-1` `Up`.
**Why human:** Requires creating a down-container state (a mutation this verifier must not make) and a real VM reboot.

### 2. Prove the no-persisted-state default (BOOT-02)

**Test:** In WSL: `mv .current-profile .current-profile.bak`. From Windows: `wsl --shutdown`. Reopen WSL; check the log and `docker compose ps`; then `mv .current-profile.bak .current-profile` to restore.
**Expected:** A fresh log line `OK: profile=batch (from .current-profile=<absent>; …)` with the batch container coming up. **Caution:** because of IN-02's inverted flag, the `default-applied=` field will read `no` in exactly this case — judge the result on the `from .current-profile=<absent>` field and the started `batch` profile, not on `default-applied=yes`.
**Why human:** Requires mutating the runtime state file and a real VM reboot.

### Gaps Summary

**No gaps.** All four ROADMAP success criteria are met to the extent this sandbox can verify: the hook is installed per the chezmoi `[boot]` convention (SC1), the persisted profile demonstrably came back up unaided after a real reboot (SC2, via the accepted already-running variant), the installer is a proven no-op on re-run (SC4), and commit hygiene/wording alignment hold. The two open items are not gaps but unexercised runtime branches of implemented, wired code (SC3's no-state branch and the wrapper's actual `up -d` start branch) — both are cheap for the user to prove on the live machine (items 1 and 2 above), and doing so also gives real evidence against review findings IN-02 and WR-02's worst case.

---

_Verified: 2026-09-18T10:10:25Z_
_Verifier: the agent (gsd-verifier)_
