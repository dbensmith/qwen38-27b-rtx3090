---
phase: "03"
slug: "boot-autostart"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-18"
---

# Phase 03 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

State B run (no prior SECURITY.md; register built from 03-01-PLAN.md + 03-02-PLAN.md threat models, both authored at plan time). L1 grep-depth audit by orchestrator 2026-09-18 — sufficient per short-circuit rule (threats_open: 0, register at plan time, ASVS L1). All mitigations additionally corroborated by 03-VERIFICATION.md live checks (8/8 passed) and 03-REVIEW.md.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| root [boot] → wrapper → login shell | /etc/wsl.conf [boot] executes as root at VM start, then `su -l` drops to the pengwin login shell; the `.current-profile` token crosses this boundary from a world-readable repo file into a shell command | `.current-profile` token (low sensitivity, integrity matters) |
| .current-profile → compose command | the persisted token (written by switch.sh only after a successful `up -d`) is read by the root wrapper and interpolated into `docker compose --profile <p> up -d` | profile token `single`/`batch` (whitelisted before use) |
| executor doc edits → qwen-repo files → GSD mirrors | the four D-10 doc edits feed STATE.md / .claude/CLAUDE.md mirrors that resync on the next GSD state update; an over-broad edit would propagate a wrong default into the mirror | doc wording (integrity matters) |
| git index → qwen-repo history | the two bookkeeping commits rewrite the repo's documented history; staging a forbidden file would leak runtime state or tooling into the tracked tree | commit file lists (hygiene boundary) |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-03-01 | Tampering | .current-profile → compose command | high | mitigate | Whitelist `case` in wrapper (verbatim switch.sh:96-114): only literal `single`/`batch` reach a compose command; missing/blank/corrupt resolve to `batch`, never interpolated (D-09; ASVS V5) | closed |
| T-03-02 | Elevation of Privilege | [boot] root → su -l | low | accept | Wrapper runs as root only for tee/chmod/wsl.conf (already root-owned); all docker/compose work drops to pengwin login shell via `su -l` (D-05) | closed |
| T-03-03 | Repudiation | boot action has no live feedback | medium | mitigate | D-13: timestamped audit line (profile, default-applied, already-running, compose result) appended to /var/log/local-llm-boot.log | closed |
| T-03-04 | Denial of Service | Docker socket not ready at boot | medium | mitigate | Pitfall-3 control: poll `docker info` 60×2s (≤120s); on exhaustion log + `exit 1` — never silent hang, never partial start | closed |
| T-03-05 | Tampering | /etc/wsl.conf [boot] line clobber | high | mitigate | Prefix-first invariant (paseo segment first, 04's `grep -qF` anchor kept); post-patch self-check of both markers; foreign `command` line never adopted; cleanup deletes whole line + own wrapper only | closed |
| T-03-SC | Tampering | dotfiles-repo commit gate (03-01 scope) | low | accept | Dotfiles lefthook pre-commit + `chezmoi apply --dry-run`; commit stages only the 045 template + ps1 comment | closed |
| T-03-06 | Tampering | D-10 over-edit (do-not-touch items) | medium | mitigate | Exact eight before/after edits + explicit do-not-touch list; executor stops if any before-string missing; negative mirror-diff check | closed |
| T-03-07 | Denial of Service | GSD milestone state left inconsistent | low | mitigate | Phase-2 bookkeeping committed (85fbb99) before any D-10 edit | closed |
| T-03-08 | Tampering | mixed file staged across the two commits | medium | mitigate | Ordering (bookkeeping before D-10) + ROADMAP excluded from Task 1; per-commit scope checks (exactly 3 / exactly 4 files) | closed |
| T-03-SC | Tampering | qwen-repo commit scope (03-02 scope) | low | mitigate | Explicit per-file `git add` + per-commit negative assertion (`! show --stat | grep .gsd/|.current-profile`); never pushed by the plan | closed |

*Status: open · closed · open — below high threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

L1 evidence (2026-09-18, orchestrator grep + live state): whitelist `single|batch` present in installed wrapper; `su -l` ×2; log path + live `OK:` lines in /var/log/local-llm-boot.log; `docker info` poll present; corrected `PASEO_MARKER="command = ..."` block + self-check in committed template; dotfiles `fba1a8a` = exactly 2 files; do-not-touch items intact (`SWITCH-03` line 18, switch.sh inline comment); bookkeeping commits exactly 3 (`85fbb99`) and 4 (`d746902`) files with zero `.gsd/`/`.current-profile` hits. 03-VERIFICATION.md prohibitions table (8/8 NOT VIOLATED) independently corroborates every row.

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| AR-03-01 | T-03-02 | Wrapper runs as root for install/patch only (files already root-owned); all container ops drop via `su -l`. Residual root-at-boot surface accepted: standard WSL `[boot]` semantics, no alternative without systemd (out of scope per D-01..D-03). | plan (D-05), verified 2026-09-18 | 2026-09-18 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-18 | 10 | 10 | 0 | orchestrator (State B, L1 grep-depth, ASVS L1 short-circuit) |

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-18
