---
phase: "02"
slug: "02-explicit-mode-switching"
status: verified
# threats_open = count of OPEN threats at or above workflow.security_block_on severity (the blocking gate)
threats_open: 0
asvs_level: 1
created: "2026-09-17"
---

# Phase 02 — Security

> Per-phase security contract: threat register, accepted risks, and audit trail.

---

## Trust Boundaries

| Boundary | Description | Data Crossing |
|----------|-------------|---------------|
| CLI arg / `.current-profile` token → switch.sh resolution | Untrusted-ish strings that influence which privileged compose command runs — the argument-injection surface of this phase | profile token (`single`/`batch` or attacker-controlled garbage) |
| switch.sh → Docker daemon | The script drives privileged container lifecycle (GPU-attached containers) with the invoking user's docker access | compose stop/up commands, container state |
| `.current-profile` → Phase 3 boot hook | Persisted state crosses a session boundary; boot-time automation will trust this token blindly at next phase | one-token profile name |
| Host env / `.env` → container env | KV_MEM and GPU-sizing knobs cross into the vLLM startup (compose `env_file` + start-script defaults) | env vars incl. secrets (VLLM_API_KEY) — never touched by switch.sh |

---

## Threat Register

| Threat ID | Category | Component | Severity | Disposition | Mitigation | Status |
|-----------|----------|-----------|----------|-------------|------------|--------|
| T-02-01 | Tampering | switch.sh arg/state-token handling (feeds `docker compose --profile <token>`) | high | mitigate | Strict case-whitelist: only literal `single`/`batch` reach compose; other CLI args → usage exit 2, other state content → default `single` | closed |
| T-02-02 | Denial of Service | GPU VRAM — target started while outgoing still releasing | medium | mitigate | Verbatim D-05 gate (60×2s, <1000 MiB) before `up -d`; timeout → exit 1, target NOT started, state NOT written | closed |
| T-02-03 | Repudiation | switch operations | low | accept | `[switch]`-prefixed terminal lines; no persistent audit trail (single-user local tool) | closed |
| T-02-04 | Information Disclosure | `.env` secrets adjacent to switch.sh | low | mitigate | switch.sh never reads or prints `.env`; compose alone consumes it via `env_file` | closed |
| T-02-05 | Elevation of Privilege | docker compose invocations | low | accept | Runs as invoking user, no sudo, no daemon/config changes; docker access pre-existing | closed |
| T-02-06 | Spoofing | shadowed `nvidia-smi` stub on PATH (Task 3 test harness) | low | accept | Test-only /tmp/fakegpu artifact, one PATH-prefixed invocation, removed unconditionally | closed |
| T-02-SC | Tampering | Supply chain — package installs (npm/pip/cargo) | low | accept | Phase installs NOTHING — pure bash + existing compose stack + prebuilt image | closed |

*Status: open · closed · open — below {block_on} threshold (non-blocking)*
*Severity: critical > high > medium > low — only open threats at or above workflow.security_block_on count toward threats_open*
*Disposition: mitigate (implementation required) · accept (documented risk) · transfer (third-party)*

---

## Accepted Risks Log

| Risk ID | Threat Ref | Rationale | Accepted By | Date |
|---------|------------|-----------|-------------|------|
| R-02-03 | T-02-03 | Single-user local tool; no source artifact mandates persistent logging. `[switch]`-prefixed terminal output is the audit surface. | secure-phase audit | 2026-09-17 |
| R-02-05 | T-02-05 | Docker-group access is already root-equivalent on this host; switch.sh adds no sudo and changes no daemon config — pre-existing surface, not widened. | secure-phase audit | 2026-09-17 |
| R-02-06 | T-02-06 | /tmp/fakegpu stub existed only for one PATH-prefixed Task 3 invocation and was removed unconditionally in the same command (SUMMARY GPU_FREE_RESTORED `test ! -e`). A persistent PATH shadow requires prior host compromise — outside this phase's trust model. | secure-phase audit | 2026-09-17 |
| R-02-SC | T-02-SC | No package-manager installs in this phase (switch.sh is pure bash; image is the prebuilt `ghcr.io/syv-ai/qwen38-27b-rtx3090:latest` per docker-compose.yml:30). Package-legitimacy gate does not fire. | secure-phase audit | 2026-09-17 |

*Accepted risks do not resurface in future audit runs.*

---

## Security Audit Trail

| Audit Date | Threats Total | Closed | Open | Run By |
|------------|---------------|--------|------|--------|
| 2026-09-17 | 7 | 7 | 0 | secure-phase (State B, inline audit — orchestrator-owned write, no subagents) |

---

## Audit Evidence (2026-09-17)

Input state: **B** — no prior SECURITY.md; threat model from `02-01-PLAN.md` `<threat_model>` (T-02-01..T-02-06, T-02-SC); `02-01-SUMMARY.md` contains **no `## Threat Flags` section** → unregistered flags: none. ASVS L1 (grep-depth presence + placement), `block_on: high` (default).

| Threat | Evidence (file:line) | Finding |
|--------|----------------------|---------|
| T-02-01 | `switch.sh:57-61` (`case "$1" in single\|batch) TARGET=$1 ;; … *) … exit 2`) | CLI whitelist present; unknown token → usage + exit 2, touches nothing |
| T-02-01 | `switch.sh:46-50` (`[ $# -gt 1 ] … exit 2`) | Extra positional args rejected before any compose/state touch |
| T-02-01 | `switch.sh:107-110` (`case "$SAVED" in single\|batch) … *) TARGET=single`) | State-file token whitelisted; absent/blank/corrupt → default `single` |
| T-02-01 | `switch.sh:145` (`docker compose --profile "$OTHER" stop`), `switch.sh:189` (`docker compose --profile "$TARGET" up -d`) | Only validated `$TARGET`/`$OTHER` (both whitelist-derived) reach compose — no raw interpolation of untrusted strings |
| T-02-02 | `switch.sh:160-167` (`seq 1 60`, `nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits`, `-lt 1000`, `sleep 2`) | Gate literals byte-match `single-user/qwen-serving.service:10` |
| T-02-02 | `switch.sh:145` → `:159-173` → `:189` → `:197` | Ordering verified: stop → gate → `up -d` → write-after-success persist |
| T-02-02 | `switch.sh:169-173` (exhaustion → error + `exit 1` before any `up`) | Abort precedes start; state untouched on failure |
| T-02-02 | `02-01-SUMMARY.md:113` (GATE_EXIT=1, GATE_ABORT_OK: batch never started, state still `single`) | Behavioral proof under shadowed nvidia-smi (always 20000 MiB) |
| T-02-03 | `switch.sh` passim (`[switch]` prefix on resolve/stop/start/persist/error lines, e.g. `:116,:129,:144,:188,:197`) | Terminal logging present; accept disposition documented in Accepted Risks Log |
| T-02-04 | `switch.sh` full 198-line read: zero `.env` references, zero secret reads/prints | Script never touches secrets; `docker-compose.yml:34-36` (`env_file: .env`) is the sole consumer. No `.env` contents read during audit |
| T-02-05 | `switch.sh` full read: zero `sudo`, zero daemon/config mutations | Accept disposition documented in Accepted Risks Log |
| T-02-06 | `02-01-SUMMARY.md:113` (stub removed, real GPU confirmed free) | Accept disposition documented in Accepted Risks Log |
| T-02-SC | `switch.sh` (pure bash) + `docker-compose.yml:30` (prebuilt image, no install step) | Nothing installed via any package manager; accept disposition documented |

D-06 escape-hatch negative gate also confirmed: `switch.sh:181` uses plus-form `${KV_MEM+x}` (set-if-unset, empty-value hatch intact); no `KV_MEM:-` on any non-comment line (full-file read). Corroborated by container-side default `single-user/start_qwen.sh:369` (`KV_MEM=${KV_MEM-5583457484}`) mapped at `:433`.

---

## Sign-Off

- [x] All threats have a disposition (mitigate / accept / transfer)
- [x] Accepted risks documented in Accepted Risks Log
- [x] `threats_open: 0` confirmed
- [x] `status: verified` set in frontmatter

**Approval:** verified 2026-09-17
