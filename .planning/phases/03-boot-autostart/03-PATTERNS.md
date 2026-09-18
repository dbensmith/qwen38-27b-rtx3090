# Phase 3: Boot Autostart - Pattern Map

**Mapped:** 2026-09-18
**Files analyzed:** 8 (2 new, 5 modified, 1 optional)
**Analogs found:** 7 / 8 (1 live-system file has no codebase analog — it is managed by template convention)

> **Tracked-source note (#3645):** Every analog below is git-tracked in its repo: the dotfiles
> repo (`/home/pengwin/.local/share/chezmoi`, verified via `git ls-files`) and the qwen repo
> (`/home/pengwin/repos/qwen38-27b-rtx3090`, verified via `git ls-files`). The two live system
> artifacts — `/usr/local/bin/paseo-boot-start` and `/etc/wsl.conf` — are **not** git-tracked;
> they are referenced only as runtime twins of their tracked source (the 04 template heredoc),
> never as analogs of record.

## File Classification

| New/Modified File | Repo | Role | Data Flow | Closest Analog (tracked) | Match Quality |
|-------------------|------|------|-----------|--------------------------|---------------|
| `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl` (NEW) | dotfiles | chezmoi template (installer script) | batch — writes wrapper file + patches `/etc/wsl.conf` | `/home/pengwin/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl` | exact |
| `/usr/local/bin/local-llm-start` (NEW, rendered by the 045 template) | dotfiles (rendered artifact) | boot-hook wrapper (bash) | event-driven (WSL `[boot]` trigger) → state-file read → fire-and-forget spawn | 04 template heredoc, lines 26–56 (renders to `/usr/local/bin/paseo-boot-start`) | role-match |
| `/etc/wsl.conf` lines 16–17 (MODIFIED, template-managed) | live system (untracked) | OS config | n/a — parsed by WSL init at VM start | **none** — managed by the 04/045 templates' grep/sed convention | no analog |
| `switch.sh` line 12 (MODIFIED, comment-only, D-10 extra) | qwen | CLI script / state writer | request-response + state write | self — in-file comment convention | self |
| `.planning/REQUIREMENTS.md` line 24 (MODIFIED, D-10); line 4 (optional extra) | qwen | planning doc | n/a (text) | self — in-file list/table convention | self |
| `.planning/ROADMAP.md` lines 39, 45 (MODIFIED, D-10) | qwen | planning doc | n/a (text) | self — in-file success-criteria convention | self |
| `.planning/PROJECT.md` line 64 (MODIFIED, D-10) | qwen | planning doc | n/a (text) | self — Key Decisions table convention | self |
| `.chezmoiscripts/run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl` lines 13–15 (OPTIONAL, comment-only, RESEARCH Open Q3) | dotfiles | chezmoi template (Windows side) | n/a (comment) | self — in-file comment convention | self |

**Not touched (context only):** `docker-compose.yml` (unchanged; read-only dependency), `.current-profile`
(unchanged, gitignored; read at boot), `run_onchange_after_04-wsl-boot-paseo.sh.tmpl` (byte-identical by
design — mutual no-op invariant, RESEARCH Pattern 1).

## Pattern Assignments

---

### `.chezmoiscripts/run_onchange_after_045-wsl-boot-llm.sh.tmpl` (NEW) — chezmoi template, batch

**Analog:** `/home/pengwin/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl`
(tracked, 107 lines). The 045 template is a *modified clone*: same outer gate, inner gate, shebang,
voice, and section structure — different `WRAPPER` path, two marker variables, a combined `BOOT_LINE`,
and a 4-branch self-healing patch (vs. the 04 template's 3-branch) plus a matching cleanup branch.

**Outer gate + preamble** (04 template lines 1–3):
```bash
{{- if and (eq .chezmoi.os "linux") .is_wsl -}}
#!/bin/bash
set -euo pipefail
```

**Variable block** (04 template lines 5–6; 045 adds the second marker + combined line per RESEARCH
`Code Examples` — the combined line MUST keep the paseo prefix first, that is the 04 template's
`grep -qF` anchor at line 60):
```bash
WRAPPER=/usr/local/bin/paseo-boot-start
BOOT_LINE="command = \"${WRAPPER}\""
```
045 version (from RESEARCH skeleton):
```bash
WRAPPER=/usr/local/bin/local-llm-start
PASEO_MARKER='command = "/usr/local/bin/paseo-boot-start"'
LLM_MARKER="/usr/local/bin/local-llm-start"
BOOT_LINE="command = \"${PASEO_MARKER#command = }\" ; ${LLM_MARKER}"
```

**Inner gate** (04 template line 8 — identical in 045; gate vars defined at
`/home/pengwin/.local/share/chezmoi/.chezmoi.toml.tmpl` lines 193–199: `is_wsl`, `profile`,
`has_nvidia_gpu` under `[data]`):
```bash
{{- if and (eq .profile "personal") .has_nvidia_gpu }}
```

**Unconditional wrapper write** (04 template lines 25–27, 56–57 — the exact heredoc idiom to copy;
045 replaces the heredoc body with the `local-llm-start` payload):
```bash
# ── 1. Write the boot wrapper ─────────────────────────────────────────────
sudo tee "$WRAPPER" > /dev/null << 'WRAPPER_EOF'
#!/bin/bash
…
WRAPPER_EOF
sudo chmod 755 "$WRAPPER"
```

**Idempotency check + 3-branch `wsl.conf` patch** (04 template lines 59–74 — 045 extends the
`else` branch to the 4-branch self-healing logic in RESEARCH `Pattern 1` / `Code Examples`;
note the "already set — no change" message wording at line 61 is the D-11 idempotency proof,
and the "Run 'wsl --shutdown'" closing line at line 73):
```bash
# ── 2. Patch /etc/wsl.conf ────────────────────────────────────────────────
if grep -qF "$BOOT_LINE" /etc/wsl.conf 2>/dev/null; then
    echo "/etc/wsl.conf [boot] command already set — no change."
else
    echo "Patching /etc/wsl.conf with [boot] command..."
    if grep -q '^\[boot\]' /etc/wsl.conf 2>/dev/null; then
        if grep -q '^command\s*=' /etc/wsl.conf 2>/dev/null; then
            sudo sed -i "s|^command\s*=.*|${BOOT_LINE}|" /etc/wsl.conf
        else
            sudo sed -i "s|^\(\[boot\]\)|\1\n${BOOT_LINE}|" /etc/wsl.conf
        fi
    else
        printf '\n[boot]\n%s\n' "$BOOT_LINE" | sudo tee -a /etc/wsl.conf > /dev/null
    fi
    echo "Done. Run 'wsl --shutdown' from Windows then reopen WSL to activate."
fi
```

**Cleanup branch** (04 template lines 75–88 — 045 mirrors this; it must delete the *whole* combined
line, since both markers share one line, and remove its own wrapper):
```bash
{{- else }}
# WSL should neither autorun on boot nor remain online indefinitely …
if [ -f "$WRAPPER" ]; then
    echo "Removing $WRAPPER (no NVIDIA GPU or not personal profile)..."
    sudo rm -f "$WRAPPER"
fi
if grep -qF "$BOOT_LINE" /etc/wsl.conf 2>/dev/null; then
    echo "Removing boot command from /etc/wsl.conf..."
    sudo sed -i "\#${BOOT_LINE}#d" /etc/wsl.conf
    echo "Done cleaning /etc/wsl.conf."
fi
{{- end }}
{{- end -}}
```
(Note: the 04 template's cleanup also stops the paseo daemon, lines 90–105 — that is paseo-specific;
the 045 cleanup has no daemon to stop, only wrapper + line removal.)

**Filename rationale (RESEARCH Pattern 1):** `045` sorts in ASCII between `04-` (`'-'`=0x2D <
`'5'`=0x35) and `05` (`'4'` < `'5'`), so the template runs *after* the paseo template and *before*
`run_onchange_after_05-install-mise-tools.*` (both verified present in `.chezmoiscripts/`).
Self-healing makes run-order non-critical, but the slot documents intent.

**Dotfiles-repo constraints that bind this file** (`/home/pengwin/.local/share/chezmoi/AGENTS.md`):
- MUST run `chezmoi apply --dry-run --verbose` before the plan step is complete (lines 13–19).
- Pre-commit validation: `mise run format`, `mise run lint`, `mise run benchmark` +
  `chezmoi apply --dry-run --verbose` (lines 134–167); lefthook `pre-commit`/`commit-msg` hooks active.
- BCP 14 keywords uppercase when normative (line 99); **no bare `op://` in template comments**
  (line 114) — the 045 template contains no `op://` references, so this is satisfied by omission.
- Stage **only** the new template file — the dotfiles working tree has unrelated local edits
  (`M apm.yml`, `?? .mcp.json`, `?? opencode.json`, RESEARCH Runtime State Inventory) that must not be committed (RESEARCH Pitfall 8).

---

### `/usr/local/bin/local-llm-start` (NEW, rendered) — boot-hook wrapper, event-driven

**Analog:** the heredoc payload of the 04 template (`/home/pengwin/.local/share/chezmoi/.chezmoiscripts/
run_onchange_after_04-wsl-boot-paseo.sh.tmpl` lines 26–56), which renders verbatim to the live
`/usr/local/bin/paseo-boot-start` (29 lines, read this session; untracked — runtime twin only).
Structure to copy: header comment block → Docker-daemon block → `exec su -l` login-shell handoff.
Payload differences: docker-readiness poll (new; no analog — see below), tolerant state read
(verbatim from `switch.sh`), whitelist, fire-and-forget `compose up -d`, log file (new).

**Docker-daemon block** (live `paseo-boot-start` lines 8–10; the LLM wrapper runs *after* this in the
same `[boot]` chain, so the daemon is already started — but the LLM wrapper must additionally poll
for socket readiness, RESEARCH Pitfall 3):
```bash
if [ -x /etc/init.d/docker ]; then
  service docker status >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
fi
```

**`su -l` login-shell handoff with mise prelude** (live `paseo-boot-start` lines 12–17 — the exact
D-05 pattern to mirror; note `{{ .chezmoi.username | quote }}` at 04 template line 38 renders to the
quoted `"pengwin"` literal in the live file):
```bash
exec su -l "pengwin" -c '
  if [ -x "$HOME/.local/bin/mise" ]; then
    eval "$("$HOME/.local/bin/mise" activate bash)"
  elif command -v mise >/dev/null 2>&1; then
    eval "$(mise activate bash)"
  fi
  …
'
```
The 045 wrapper's `su -l` payload is not `exec`-to-daemon but a one-shot: `cd $REPO && docker compose
--profile "$PROFILE" up -d` (RESEARCH Code Examples step 5).

**Repo-path resolution** — `switch.sh` lines 22–24 is the in-repo convention (self-locating):
```bash
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
STATE_FILE="$HERE/.current-profile"
```
Agent discretion (RESEARCH "the agent's Discretion"): the wrapper is *not* self-locating (it lives in
`/usr/local/bin`, not the repo), so a fixed path `REPO="/home/pengwin/repos/qwen38-27b-rtx3090"` with
an existence guard (RESEARCH Code Examples step 2) is the recommended form.

**Tolerant state read — copy VERBATIM** (D-09: "same as switch.sh"; `switch.sh` lines 101–110 — note
the live default at line 109 is already `batch`, which is what D-08 locks):
```bash
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
```
The wrapper version drops the `RESOLVED_FROM` bookkeeping and uses `PROFILE` (RESEARCH Code Examples
step 3). **Security invariant (RESEARCH Security Domain / Pitfall 6):** only the literal `single|batch`
tokens are ever used; the raw value is never interpolated unvalidated. The RESEARCH Code Examples log
line (step 5) already implements the refinement: log the *classified* result
(`from .current-profile=${SAVED:-<absent>}` is acceptable because it is emitted only after the
whitelist decision; if a non-whitelisted value is ever logged, emit `<corrupt>` instead of raw bytes).

**Fire-and-forget start** (D-07; `switch.sh` lines 189–192 is the in-repo precedent for
"no health-wait — the compose healthcheck owns that"):
```bash
if ! docker compose --profile "$TARGET" up -d; then
  echo "[switch] error: compose up of profile '$TARGET' failed" >&2
  exit 1
fi
```
`docker-compose.yml` (unchanged) provides the rest of the lifecycle: `restart: unless-stopped`
(line 57), `stop_grace_period: 30s` (line 58), healthcheck with `start_period: 900s` (lines 59–64),
profiles `single`/`batch` (lines 71–79). The wrapper must NOT add a health wait (RESEARCH Pattern 4,
Pitfall 4) and must NOT reuse `switch.sh`'s 60×2s VRAM gate (D-06 — that gate is switch-time only;
`switch.sh` lines 154–173 are reference, not to be copied).

**Docker-socket readiness poll** — NO analog in the codebase (new construct, RESEARCH Code Examples
step 1 / Pitfall 3): `for i in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 2; done`
then hard log-and-exit if still down. Rationale: the paseo wrapper's `service docker start` is
fire-and-forget and returns before `/var/run/docker.sock` accepts.

**Log (D-13)** — no analog in the codebase (both existing writers log to stdout only). RESEARCH
Code Examples defines the idiom:
```bash
LOG="/var/log/local-llm-boot-boot.log"
log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" >> "$LOG"; }
```
⚠️ **Inconsistency to resolve in the plan (agent discretion, "exact log file path"):** the RESEARCH
wrapper's header comment (Code Examples line: `# Log: /var/log/local-llm-boot.log (D-13)`) and the
`LOG=` variable (`local-llm-boot-boot.log`) disagree. The plan must pick ONE name (recommend
`/var/log/local-llm-boot.log` — shorter, matches the header comment) and use it consistently in the
wrapper, its comment, and the D-12 verification checklist.

---

### `/etc/wsl.conf` lines 16–17 (MODIFIED) — OS config, template-managed

**No analog in either codebase** — `/etc/wsl.conf` is a live system file owned by the WSL init
process; its only writers are the 04/045 templates. It is classified here for completeness because
the plan must reference its target state:

Current state (live, read this session, lines 16–17):
```ini
[boot]
command = "/usr/local/bin/paseo-boot-start"
```
Target state after the 045 template (RESEARCH `Code Examples`; note the `;` is *inside* the quotes —
the whole value is one `sh -c` string, WSL source `config.cpp:1012`):
```ini
[boot]
command = "/usr/local/bin/paseo-boot-start" ; /usr/local/bin/local-llm-start"
```
**Load-bearing invariant (RESEARCH Pattern 1, Pitfall 1):** the line MUST begin with the exact
substring `command = "/usr/local/bin/paseo-boot-start"` — the 04 template's `grep -qF` anchor
(04 template line 6). Losing that prefix lets the 04 template's whole-line `sed`
(line 66: `s|^command\s*=.*|${BOOT_LINE}|`) silently delete the LLM half. `;` (never `&&`) for
independent failure isolation (D-02). Never a second `command =` line. The 045 template's
post-patch self-check (grep for *both* markers) is the verification control.

---

### `switch.sh` line 12 (MODIFIED, comment-only) — D-10 recommended extra

**Analog:** self. The file's own line 109 (live default `batch`) is the source of truth; the header
comment is the stale claim. Current text (line 12):
```
#                         # .current-profile token; absent/blank/corrupt -> single
```
Target (wording is agent discretion; keep the comment's column alignment):
```
#                         # .current-profile token; absent/blank/corrupt -> batch
```
No other line of `switch.sh` changes in this phase (out of scope per CONTEXT "Phase Boundary").
The comment-only edit keeps the file's GSD commit surface minimal and avoids touching executable logic
verified in Phase 2.

---

### `.planning/REQUIREMENTS.md` line 24 (MODIFIED, D-10 target 1); line 4 (optional extra)

**Analog:** self — in-file requirement-list convention (`- [ ] **ID**: …` with backticked tokens).
Exact current text (verified against RESEARCH's "before" lines — diff applies cleanly):

Line 24 (named D-10 target):
```
- [ ] **BOOT-02**: If no profile was ever selected, the boot hook starts `single` by default
```
→
```
- [ ] **BOOT-02**: If no profile was ever selected, the boot hook starts `batch` by default
```

Line 4 (Open-Q1 recommended extra — same stale claim, zero risk):
```
**Core Value:** The 3090 always comes back serving requests after a reboot, in whichever mode (single-user or batch) was last selected — with single-user as the safe default until a mode is explicitly chosen.
```
→ (wording is agent discretion)
```
**Core Value:** The 3090 always comes back serving requests after a reboot, in whichever mode (single-user or batch) was last selected — with batch as the safe default until a mode is explicitly chosen.
```

⚠️ **Do NOT edit line 18** (`SWITCH-03`: "… defaults to `single`"): it is a `[x]`-completed Phase 2
requirement record; D-10 and RESEARCH Open Q1 do not name it. Changing it would rewrite Phase 2's
historical record (the default *was* `single` when Phase 2 shipped; quick task 260917-2fz changed the
behavior afterwards). Flag it in the plan as "stale by design, left as historical record."

---

### `.planning/ROADMAP.md` lines 39, 45 (MODIFIED, D-10 target 2)

**Analog:** self — in-file goal + success-criteria convention. Exact current text (verified):

Line 39 (goal; RESEARCH names both line 39 and line 45):
```
**Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `single` if nothing was ever chosen.
```
→
```
**Goal:** Whichever profile was last selected comes back up automatically after a WSL2 reboot, defaulting to `batch` if nothing was ever chosen.
```

Line 45 (success criterion 3):
```
3. On a machine with no persisted state yet, the boot hook starts `single`
```
→
```
3. On a machine with no persisted state yet, the boot hook starts `batch`
```

---

### `.planning/PROJECT.md` line 64 (MODIFIED, D-10 target 3)

**Analog:** self — Key Decisions table convention (`| Decision | Rationale | Outcome |`; rows use
backticked tokens and `✓ Good` / `— Pending` outcome markers). Exact current text (verified):
```
| Default profile is `single` on first run | Matches "single user fast mode as default" | — Pending |
```
→ (RESEARCH's exact proposed row):
```
| Default profile is `batch` on first run | Quick task 260917-2fz (2026-09-17) made batch the current default; boot follows the same fallback (switch.sh:109) | ✓ Good |
```

**Auto-mirror note (RESEARCH Open Q1):** `STATE.md:25` and `.claude/CLAUDE.md` mirror PROJECT.md's
Core Value and re-sync automatically on the next GSD state update — the plan should state "do not
hand-edit these; GSD re-sync covers them."

---

### `.chezmoiscripts/run_onchange_after_04-start-wsl2-on-boot.ps1.tmpl` lines 13–15 (OPTIONAL, comment-only)

**Analog:** self. RESEARCH Open Q3: the comment names only the paseo template as the `[boot]`
manager. Optional one-line update in the same 045 task, e.g.:
```
# Booting the distro triggers /etc/wsl.conf [boot] command (managed by
# run_onchange_after_04-wsl-boot-paseo.sh.tmpl and run_onchange_after_045-wsl-boot-llm.sh.tmpl),
# which starts the Paseo daemon and the LLM model stack. In combination with …
```
Caveat (RESEARCH Open Q3): the agent cannot render/test the `.ps1` in WSL (no `pwsh`); the comment
remains factually correct if left unchanged. Agent discretion — recommend including only if the
045 task already stages the dotfiles repo (same commit, no extra review cost).

## Shared Patterns

### 1. chezmoi gate idiom (applies to 045 template)
**Source:** `/home/pengwin/.local/share/chezmoi/.chezmoiscripts/run_onchange_after_04-wsl-boot-paseo.sh.tmpl` lines 1, 8, 75, 106; gate vars at `/home/pengwin/.local/share/chezmoi/.chezmoi.toml.tmpl` lines 193–199
```bash
{{- if and (eq .chezmoi.os "linux") .is_wsl -}}
…
{{- if and (eq .profile "personal") .has_nvidia_gpu }}
…
{{- else }}
…cleanup…
{{- end }}
{{- end -}}
```
The 045 template MUST use the identical double gate so both cleanup branches fire or never fire
together (RESEARCH Pattern 1: "both cleanup branches always fire or never fire together").

### 2. `#!/bin/bash` + `set -euo pipefail` preamble (applies to 045 template)
**Source:** 04 template lines 2–3. Note `switch.sh` uses only `set -e` (line 21) — the *template*
(prep shell) uses the stricter idiom; the *rendered wrapper* (`paseo-boot-start`) uses neither
(renders with bare `#!/bin/bash`). The new `local-llm-start` wrapper should keep the live paseo
wrapper's minimal style (no `set -e` — the wrapper's error paths are explicit log-and-exit branches,
and a mid-script abort under `set -e` would skip the D-13 log line).

### 3. Unconditional `sudo tee` heredoc + `chmod 755` (applies to 045 template)
**Source:** 04 template lines 25–27, 56–57 (quoted in the 045 section above). The rendered wrapper is
rewritten on every apply with stable content; idempotency lives on the `wsl.conf` line, not the file
(D-11; RESEARCH `Don't Hand-Roll`).

### 4. `grep -qF` anchor + 3-branch `sed` config patching (applies to 045 template)
**Source:** 04 template lines 60–74 (quoted above). RESEARCH `Don't Hand-Roll` table: do NOT build a
new ini/toml/awk `[boot]` parser — this convention "encodes the exact edge cases (no `[boot]`,
`[boot]` without `command`, existing `command`) and is byte-stable under re-runs."

### 5. `su -l pengwin` + mise-activate login handoff (applies to `local-llm-start`)
**Source:** live `/usr/local/bin/paseo-boot-start` lines 12–17; tracked origin 04 template line 38
(`{{ .chezmoi.username | quote }}`). RESEARCH `Don't Hand-Roll`: do not hand-build a `PATH`/`env`
export block — PAM + profile sourcing is the source of truth; `runuser` is rejected (skips the login
shell the mise-activated PATH depends on).

### 6. Verbatim tolerant state read (applies to `local-llm-start`)
**Source:** `/home/pengwin/repos/qwen38-27b-rtx3090/switch.sh` lines 101–110 (quoted in the wrapper
section above). RESEARCH Pattern 2: copy word-for-word so "corrupt" means the same thing in both
places; a drifted predicate (trim-only-spaces, different default) would let `switch.sh` and the boot
hook disagree.

### 7. Fire-and-forget `compose up -d` (applies to `local-llm-start`)
**Source:** `switch.sh` lines 185–192 (no health-wait; healthcheck owns "healthy") + `docker-compose.yml`
lines 57–64 (`restart: unless-stopped`, 900s `start_period`). D-06: the 60×2s VRAM gate
(`switch.sh` lines 154–173) is explicitly NOT copied to boot.

### 8. Dotfiles-repo commit hygiene (applies to any dotfiles-repo commit in this phase)
**Source:** `/home/pengwin/.local/share/chezmoi/AGENTS.md` lines 13–19, 134–167; RESEARCH Pitfall 8.
Before the dotfiles commit: `mise run format`, `mise run lint`, `mise run benchmark`,
`chezmoi apply --dry-run --verbose`; `git add` **only** the 045 template; real (passwordful)
`chezmoi apply` + `wsl --shutdown` are human checkpoints (RESEARCH A3 — structural: the sandbox has
no interop and scoped NOPASSWD sudo only).

## No Analog Found

| File | Role | Data Flow | Reason |
|------|------|-----------|--------|
| `/etc/wsl.conf` `[boot]` line (MODIFIED) | OS config | n/a | Live system file, untracked in both repos; its only "pattern" is the 04/045 templates' grep/sed management convention (Shared Patterns 4). Target state is fixed by RESEARCH `Code Examples`. |
| Docker-socket readiness poll (inside `local-llm-start`) | boot-hook sub-step | event-driven | No existing code on this machine polls for docker readiness (the paseo wrapper doesn't need to — it's not a docker client). New construct specified in RESEARCH Code Examples step 1 / Pitfall 3 (`60 × 2s`, then hard log-and-exit). |
| Boot log file + `log()` helper (inside `local-llm-start`) | boot-hook sub-step | file I/O | Neither existing wrapper writes a log file (both log to the invisible `[boot]` stdout only — RESEARCH Pitfall 7). RESEARCH Code Examples step 5 gives the idiom; log path is agent discretion (see the naming-inconsistency warning in the wrapper section). |

## Non-Edits (flagged so the planner doesn't "fix" them)

| Item | Location | Why not edited |
|------|----------|----------------|
| `SWITCH-03` "defaults to `single`" | `REQUIREMENTS.md:18` | `[x]`-completed Phase 2 record; historical. D-10 names only line 24. |
| Core Value / decision mirrors | `STATE.md:25`, `.claude/CLAUDE.md` | Auto-mirror PROJECT.md on next GSD state update; hand-editing desyncs them. |
| `paseo-boot-start` qwen-block append | `/usr/local/bin/paseo-boot-start` | D-01 explicit rejection: the 04 template rewrites that file unconditionally and would clobber it. |
| `docker-compose.yml`, `.current-profile` | qwen repo root | Unchanged by design (read-only boot dependencies; RESEARCH Runtime State Inventory "None"). |

## Metadata

**Analog search scope:** `/home/pengwin/repos/qwen38-27b-rtx3090` (repo root, `.planning/`); `/home/pengwin/.local/share/chezmoi/.chezmoiscripts/` (+ `.chezmoi.toml.tmpl`, `AGENTS.md`); live system artifacts read for reference only: `/usr/local/bin/paseo-boot-start`, `/etc/wsl.conf`
**Files scanned:** 12 (5 qwen-repo tracked, 4 dotfiles-repo tracked, 3 live/untracked)
**Git-tracked verification:** all analog paths confirmed via `git ls-files` in their respective repos
**Pattern extraction date:** 2026-09-18
