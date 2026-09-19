---
status: issues
phase: 03-boot-autostart
reviewed: 2026-09-18
scope_qwen: "git log 51f85cf..HEAD (docs alignment, switch.sh header, SUMMARYs, tracking)"
scope_dotfiles: "run_onchange_after_045-wsl-boot-llm.sh.tmpl (new, fba1a8a) + 04 ps1 comment edit"
mode: advisory
findings:
  warning: 3
  info: 3
---

# Phase 03 (Boot Autostart) — Advisory Code Review

**Scope (qwen repo):** `51f85cf..HEAD` — six docs-only commits. The only
source change is a one-line header comment in `switch.sh` (`single` → `batch`).
**Scope (dotfiles repo):** new `045` boot template (commit `fba1a8a`) plus a
comment-only edit to the 04 ps1 template. Reviewed the 045 template for shell
correctness, idempotency, and `[boot]`-line handling, including convergence
against `run_onchange_after_04-wsl-boot-paseo.sh.tmpl`.

**Verdict:** no blockers. The combined-line design (paseo prefix first) converges
in either apply order — each template's `grep -qF` anchor is a substring of the
combined line, so both no-op once it exists; the cleanup paths agree (both
templates want the boot command gone on non-GPU hosts), so the whole-line
`sed ... d` in the 045 cleanup is consistent, not collateral damage. The
`su -l` quote-split idiom, PROFILE whitelist before interpolation, docker-socket
poll, and fail-closed self-check are all sound. Findings below are advisory.

## Warnings

### WR-01: `switch.sh` inline comment still states the old `single` default

**File:** `switch.sh:97-100` (comment) vs `switch.sh:109` (code) and `switch.sh:12` (header)
**Issue:** the no-arg resolution comment block says anything outside the
whitelist "lands on the same default `single` (D-01, SWITCH-03)", but line 109
implements `TARGET=batch`, and the header fixed in `d746902` says `-> batch`.
Two of three statements agree; the inline comment is now factually wrong and,
sitting directly above the code it misdescribes, invites a future editor to
"fix" line 109 back to `single`.
**Fix:** update the comment to match, e.g.:

```bash
    # whitelist — absent, blank, corrupt — lands on the same default
    # `batch` (D-08, SWITCH-03 as amended by quick task 260917-2fz).
```

### WR-02: 045 wrapper-body edits will never propagate on re-apply (D-11 blind spot)

**File:** dotfiles `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl:38-40,42-113`
**Issue:** the wrapper `tee` lives inside the install path gated on LLM-marker
absence. Deliberate (SUMMARY documents the D-11 tradeoff for a true no-op), but
the consequence is unrecorded in the template: any *future* edit to the wrapper
body changes the chezmoi hash, the script re-runs, the inner `grep` gate sees
the marker and skips — the fix silently never lands. The sibling 04 template
rewrites its wrapper unconditionally and has no such trap.
**Fix (advisory):** add a wrapper version marker and compare before skipping,
e.g. `# LOCAL-LLM-START v1` in the wrapper plus `grep -qF "v2"` in the gate; or
a one-line comment in the template warning that wrapper-body changes require a
marker bump or manual reinstall.

### WR-03: foreign-command branch says "WARNING … not touching it" then hard-fails

**File:** dotfiles `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl:119-134`
**Issue:** when `[boot]` exists with an unrecognized `command =` line, the
script echoes WARNING and skips patching — but execution falls through to the
self-check at line 131, which finds the LLM marker absent and `exit 1`s. The
"warn and leave it" message is really a fatal error for `chezmoi apply`.
(Rare in practice: 04 runs first in lexical order and aggressively adopts
foreign lines, so this branch is near-dead — but the message/exit disagree.)
**Fix:** either `exit 1` with an ERROR message that says what to do (adopt or
remove the foreign line), or skip the self-check on that path and return
non-zero explicitly:

```bash
echo "ERROR: /etc/wsl.conf has an unrecognized [boot] command; refusing to overwrite it — resolve manually." >&2
exit 1
```

## Info

### IN-01: REQUIREMENTS SWITCH-03 text ("defaults to `single`") marked `[x]` Complete contradicts batch behavior

**File:** `.planning/REQUIREMENTS.md:18` vs `:24` (BOOT-02 `batch`), `switch.sh:109`
**Issue:** SWITCH-03 still reads "defaults to `single`" yet is checked complete
while the implementation defaults to `batch`. The 03-02 SUMMARY records this as
intentional ("stale-by-design historical records"), but a reader comparing
SWITCH-03 `[x]` against BOOT-02 sees two opposite defaults with no in-file
pointer to the rationale.
**Fix:** append a brief note on line 18, e.g. `<!-- historical wording kept; default amended to batch per D-08/quick-task 260917-2fz -->`.

### IN-02: boot-log `default-applied=` misreports the absent-file first-boot case

**File:** dotfiles `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl:107`
**Issue:** `default-applied=$([ -n "$SAVED" ] && …)` evaluates to `no` when
`.current-profile` is absent/blank — exactly the first-boot case where the
batch default *was* applied. Forensics-only field, but the most common default
event logs as `default-applied=no`.
**Fix:** invert the test to detect whitelist membership, e.g.
`default-applied=$([ "$PROFILE" = "$SAVED" ] && [ -n "$SAVED" ] && echo no || echo yes)`.

### IN-03: unused loop variable in the docker-readiness poll

**File:** dotfiles `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl:59`
**Issue:** `for i in $(seq 1 60)` never uses `$i` (shellcheck SC2034). Cosmetic.
**Fix:** `for _ in $(seq 1 60); do` or `for ((i=0; i<60; i++)); do`.

## Explicitly checked, no issue

- **No secrets / injection:** PROFILE is whitelisted (`single|batch`, default
  `batch`) before reaching `docker compose --profile`; `SAVED` is only compared
  and logged, never executed. `mise` `eval` prelude is byte-identical to the
  existing 04 template.
- **`sed` replacement safety:** `BOOT_LINE` contains no `&`, `\`, or `|` (the
  `|` delimiter), and `#`-delimited cleanup address contains no `#` — safe.
  `\s` BRE idiom matches the sibling template (GNU sed on Ubuntu WSL).
- **Quoted heredoc** (`<< 'WRAPPER_EOF'`) keeps wrapper `$(…)` literal — correct.
- **04 ps1 edit** is comment-only; no behavioral change.
- **qwen-repo commits** contain no `.gsd/` or `.current-profile` leakage
  (consistent with the SUMMARYs' negative scope checks).
