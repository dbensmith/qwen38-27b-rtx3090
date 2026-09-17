# Phase 3: Boot Autostart - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-09-17
**Phase:** 3-Boot Autostart
**Areas discussed:** Hook placement, Boot mechanics, Default conflict, Installer & verify

---

## Hook placement

| Option | Description | Selected |
|--------|-------------|----------|
| Separate qwen-boot-start, chained | Survives chezmoi rewrites of paseo-boot-start; each wrapper owned independently | ✓ (renamed) |
| Append qwen block into paseo-boot-start | Single place — but chezmoi rewrites would clobber qwen lines | |
| You decide | You decide placement and wsl.conf wiring | |

**User's choice:** Separate wrapper, "but named agnostic to the vendor and model" (free text) → `local-llm-start`
**Notes:** Follow-ups locked: wsl.conf chains both wrappers; chezmoi template owns both (not a repo installer).

## Boot mechanics

| Option | Description | Selected |
|--------|-------------|----------|
| Read state file, compose up persisted profile | Reads .current-profile, compose up that profile, fallback to default | ✓ |
| Delegate to switch.sh | Boot calls switch.sh so VRAM gate + KV pin apply | |
| You decide | You decide the boot command | |

**User's choice:** Read state file, compose up persisted profile; su -l pengwin login shell; skip VRAM gate at boot; fire-and-forget compose up
**Notes:** Boot runs as root with no login env — su -l mirrors paseo-boot-start so docker/compose resolve identically. Fresh boot = free VRAM, no gate. No /health block (900s start period owned by compose healthcheck).

## Default conflict

| Option | Description | Selected |
|--------|-------------|----------|
| Batch is the default | Matches current switch.sh:109 + quick task 260917-2fz; update ROADMAP/REQUIREMENTS | ✓ |
| Single is the default | Original milestone intent; revert switch.sh:109 and .current-profile | |
| You decide | You decide the default | |

**User's choice:** Batch is the default; same tolerant fallback on corrupt state; yes, align docs to batch
**Notes:** Surfaced conflict: ROADMAP/BOOT-02/PROJECT.md say single, code says batch. User locked batch + doc-alignment task (D-10).

## Installer & verify

| Option | Description | Selected |
|--------|-------------|----------|
| Chezmoi apply only, no repo script | chezmoi apply is the installer; repo holds no installer script | ✓ |
| Repo installer + chezmoi mirror | Thin repo installer plus chezmoi mirror | |
| You decide | You decide installer shape | |

**User's choice:** Chezmoi apply only; idempotent via already-set check; real wsl --shutdown + reopen; log to a file
**Notes:** BOOT-03 proven via template's grep idempotency check. Real reboot despite time cost. Wrapper logs profile + compose result for post-reboot evidence.

---

## the agent's Discretion

None — user decided every question; no "You decide" selections. the agent's-discretion items in CONTEXT.md are agent-noted implementation details (chaining syntax, log path, repo-path resolution, doc wording), not user deferrals.

## Deferred Ideas

None — discussion stayed within phase scope.
