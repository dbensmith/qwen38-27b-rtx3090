<!-- GSD:project-start source:PROJECT.md -->

## Project

**Qwen3.8-27B Deployment (Single-3090)**

This repo already builds a patched-vLLM serving stack for Qwen3.8-27B on one
RTX 3090, with two mutually-exclusive serving modes (single-user low-latency
via MTP/DFlash2 speculative decoding, and batch high-throughput) exposed as
Docker Compose profiles (`single`, `batch`). This milestone turns that stack
into something that's actually running day to day on this machine: single-user
mode as the default, batch mode available as a one-command switch, and whichever
mode was last selected comes back up automatically when the WSL2 distro reboots
— following the same `/etc/wsl.conf [boot]` autostart pattern already used for
the Paseo daemon (chezmoi) and the Docker-on-GPU-host boot hook, rather than
systemd units (this WSL distro has no systemd as PID 1).

**Core Value:** The 3090 always comes back serving requests after a reboot, in whichever mode
(single-user or batch) was last selected — with single-user as the safe default
until a mode is explicitly chosen.

### Constraints

- **Platform:** No systemd as PID 1 on this WSL distro — any boot automation must use the `/etc/wsl.conf [boot]` mechanism, not `systemctl enable`.
- **Hardware:** Single RTX 3090 (24GB VRAM) — single and batch profiles are mutually exclusive, never run concurrently.
- **Sandbox:** `sudo service docker start` now has passwordless sudo configured (`/etc/sudoers.d/docker-nopasswd`, scoped to `service docker {start,stop,restart,status}` only). It can still fail on a *fresh* WSL2 session with `ulimit: error setting limit (Invalid argument)` — see docs/docker.md WSL2 notes item 6 for the root cause and fix (a one-time `/etc/security/limits.d/99-docker-nofile.conf` pin that requires a real terminal + session restart; an agent session can apply the sudoers/service fix but not the PAM-limits fix, since that needs unrestricted sudo).

<!-- GSD:project-end -->

<!-- GSD:stack-start source:codebase/STACK.md -->

## Technology Stack

## Languages

- Python 3.12 - vLLM runtime, all launch scripts, benchmarking (`bench/`), model preparation (`prepare/`), drafter training (`drafter/`)
- Bash - orchestration scripts: `docker/entrypoint.sh`, `docker/prepare.sh`, `single-user/start_qwen.sh`, `batch/start_qwen.sh`, `verify.sh`, `kvarn/install.sh`
- Patch/diff (unified diffs) - `patches/*.patch` applied on top of the pinned vLLM source tree

## Runtime

- Python 3.12 (venv at `/app/venv` in the container, or a local venv per README "Setup")
- CUDA 13.0 (base image `nvidia/cuda:13.0.1-base-ubuntu24.04`), requires host NVIDIA driver ≥ 580
- Single NVIDIA GPU target: RTX 3090 (24 GB, sm86); tuned to run at a 250 W host power limit
- pip, inside a Python venv
- Lockfile: `docker/requirements.txt` is a hard pin (not a lockfile format, but fully version-pinned) for the Docker build; the venv "Setup" path in README follows the same pins

## Frameworks

- vLLM 0.28.0 - inference/serving engine, OpenAI-compatible API server (`vllm serve` invoked from `single-user/start_qwen.sh` / `batch/start_qwen.sh`)
- PyTorch 2.13 (pulled in transitively by vLLM 0.28.0) / CUDA 13.0 / Triton 3.7.1 - tensor runtime and JIT kernels
- Transformers 5.15.0, Tokenizers 0.22.2 - model loading/tokenization
- compressed-tensors 0.17.0 - quantized weight format support (W4A16/int4/int8 checkpoints)
- FlashInfer (via `flashinfer-python` / `flashinfer-cubin`) - fp8 KV-cache attention kernels, JIT-compiled with nvcc on first use
- KVarN (`kvarn/`, installed via `kvarn/install.sh`, patches from `kvarn/*.patch`) - custom 4-bit-key/2-bit-value KV cache for long context (200k+ tokens)
- `verify.sh` - custom bash verification harness (not a test framework); gates the Docker build (`--install` mode) and every container start (`--no-server` mode), and can hit a live server (full mode) via curl
- `patches/_check_applied.py` + `.github/workflows/patch-integrity.yml` - CI check that every patch in `patches/` still applies cleanly against the pinned vLLM source (checked out at tag `v0.28.0`)
- `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py` - standalone Python scripts exercising custom CUDA kernel patches (no pytest harness detected)
- Docker (multi-stage-less single `Dockerfile`) + `docker-compose.yml` with profiles (`single`, `batch`, `prepare`)
- GitHub Actions (`.github/workflows/docker-image.yml`, `.github/workflows/patch-integrity.yml`) - CI build/push and patch-integrity gate
- `ninja` 1.13.0 - build accelerator for JIT-compiled kernels (FlashInfer/Triton)

## Key Dependencies

- `vllm==0.28.0` - the entire serving stack; resolves compatible torch/cu130/Triton/FlashInfer versions
- `transformers==5.15.0`, `tokenizers==0.22.2` - model architecture and tokenization compatible with Qwen3.8-27B
- `huggingface_hub==1.27.0` + `hf_transfer==0.1.9` - model/weights download (`prepare/*.py`, `drafter/collect_prompts.py`); `HF_HUB_ENABLE_HF_TRANSFER=1` set in the image
- `compressed-tensors==0.17.0` - quantized checkpoint loading (W4A16, int4/int8 activation paths)
- `pandas==3.0.5` - required only so `vllm bench serve`'s dataset loader doesn't hard-fail (see comment in `docker/requirements.txt`); intentionally NOT the full `vllm[bench]` extra to avoid reinstalling vLLM and reverting the patch stack
- `ninja==1.13.0` - JIT kernel compilation support

## Configuration

- All runtime knobs are environment variables, read by `single-user/start_qwen.sh` / `batch/start_qwen.sh`: `CTX`, `KV`, `MAX_LEN`, `MAX_SEQS`, `GPU_UTIL`, `VISION`, `SPEC` / `SPEC_ATTN`, `DRAFT_TOKENS` / `DFLASH_TOKENS`, `INT8_ACT`, `INT8_LAYERS`, `PREFIX_CACHE`, `EXTRA_ARGS`, `VLLM_API_KEY`, `VLLM_WSL2_ENABLE_PIN_MEMORY`, `VLLM_OFFLOAD_KEEP_SHM`, `PREPARE`, `VERIFY`
- `.env` file at repo root (gitignored) is read directly by `docker-compose.yml` (`env_file:`) and mirrors the same variable names used by the bash scripts
- API key alternative: `api_key.txt` in repo root (`single-user/start_qwen.sh:666`, `batch/start_qwen.sh:178`, `verify.sh:160-173`); if neither is set the server has no auth and warns via `verify.sh`
- `HOME=/cache` in the container - redirects `torch.compile` cache, Triton cache, FlashInfer JIT cache, and the HF hub cache into the persisted `/cache` volume
- `Dockerfile` - defines the frozen stack, applies `patches/*.patch` to the installed vLLM package at build time, runs `kvarn/install.sh` and `verify.sh --install` as build gates
- `docker-compose.yml` - defines `prepare` / `single` / `batch` services, GPU device reservation, healthcheck (`/health`, 900s start period), named volumes (`qwen-cache`, bind-mounted `models/`)
- `.dockerignore`, `.gitattributes`, `.gitignore` - standard repo hygiene; no linter/formatter config files (no `.eslintrc`, `pyproject.toml`, `ruff.toml`, etc. detected)

## Platform Requirements

- Linux or WSL2 host with an NVIDIA GPU (sm86-class, e.g. RTX 3090) and driver supporting CUDA 13
- Docker + NVIDIA Container Toolkit for the containerized path, or a local Python 3.12 venv for the "Setup" path in README
- `docker/gotchas.md` / `docs/wsl2-4090.md` document WSL2-specific caveats (UVA pinning, free-memory gate)
- Single-GPU deployment (24 GB VRAM class card), served on port 18020, OpenAI-compatible HTTP API
- Prebuilt image published to `ghcr.io/syv-ai/qwen38-27b-rtx3090` on every push to `main` (tag `latest`) plus immutable `sha-<7>` tags, rebuilt weekly via cron for base-image security fixes
- No orchestration platform (Kubernetes, etc.) detected — single-container, single-GPU deployment model only

<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->

## Conventions

## Project Nature

- `bench/` — GPU benchmark and correctness scripts (`bench/labd_bench.py`, `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`)
- `drafter/` — MTP/DFlash2 draft-model training and export (`drafter/train_mtp.py`, `drafter/capture.py`)
- `prepare/` — one-shot quantization/vocab preparation scripts (`prepare/quant_lm_head.py`, `prepare/build_draft_vocab.py`)
- `patches/` — unified diffs against vLLM's installed site-packages, plus `patches/_check_applied.py` to verify they landed
- `single-user/`, `batch/` — deployment scripts and systemd units
- `verify.sh` — the closest thing to a test suite; a bash script that PASS/WARN/FAILs the whole install

## Naming Patterns

- `snake_case.py` throughout, named after what they do: `residue_sweep.py`, `spec_attn_ctx_scan.py`, `mq3d_layer2_oracle.py`
- Prefixes group related tooling: `mq3d_*` (Layer-2 oracle/capacity tests), `labd_*` (long-context lookup-augmented drafting), `spec_*` (speculative decoding)
- Patch files are named `<feature>-<detail>.patch` (e.g. `patches/dflash2-lookup-drafting.patch`, `patches/marlin-int8-negative-scales.patch`) — filename doubles as a changelog entry
- `snake_case`, short and verb-first: `ref_lookup`, `run_case`, `superseded_by` (in `verify.sh`'s bash equivalent)
- `main()` is the standard entrypoint function in scripts meant to be run directly (`bench/demo_render.py:317`, `bench/test_lookup_kernels.py:48`, `bench/mq3d_capacity_property.py:43`)
- Short, often uppercase for script-level "constants" derived from argv or env: `KEY`, `BASE`, `TAG`, `CORPUS`, `CTX`, `MAXTOK` (`bench/labd_bench.py:20-27`)
- Domain abbreviations are used consistently without redefinition inline (`kv_lens`, `q_len`, `nb`, `bt` for block table) — familiarity with vLLM internals is assumed
- No custom classes in most scripts; PyTorch tensors and plain dicts/lists are the primary data structures. Type hints are rare and only appear as inline string-quoted hints in a few files (e.g. `patches/_check_applied.py:16` — `per_file: "dict[str, list[str]]" = {}`)

## Code Style

- No formatter config found (no `.prettierrc`, no `pyproject.toml`/`black`/`ruff` config). Style is manually consistent: 4-space indents, double-quoted strings mixed with single-quoted, lines commonly 90-110 chars (denser than PEP8's 79).
- Dense one-liners are common and intentional, including multiple statements on one line separated by `;` (`bench/tune_gdn.py:41`: `except Exception as e: print(f"BV={BV} warps={W}: FAIL {str(e)[:80]}")`)
- No linter config present (no `.eslintrc`, `ruff.toml`, `.flake8`). `# noqa` comments appear ad hoc to suppress warnings the author is aware of (`bench/api_smoke.py:41`, import lines with runtime `sys.path` mutation in `bench/test_lookup_kernels.py`)

## Module-Level Documentation

## Argument Parsing

## Error Handling

- Bare `except OSError:` guards file/corpus-loading code where a missing file means "generate it fresh" rather than "crash" (`bench/labd_bench.py`, `bench/quality_battery.py:33`, `bench/conc_ladder.py:60`, `bench/needle_test.py:25`, `bench/make_long_corpus.py:42`, `bench/seat_ttft.py:28`) — this is the dominant except pattern in the repo.
- Bare `except Exception as e:` (or bare `except Exception:`) appears inside per-iteration sweep loops so one bad config doesn't kill the whole sweep, with the exception message truncated and printed inline: `except Exception as e: print(f"BV={BV} warps={W}: FAIL {str(e)[:80]}")` (`bench/tune_gdn.py:41`)
- `raise SystemExit("<message>")` is the idiom for a hard, user-facing precondition failure in a bench script (`bench/labd_accept.py:193`), not `raise RuntimeError` or custom exceptions. Use this for "the server isn't configured the way this benchmark needs" type failures.
- No custom exception classes anywhere in the repo — stick to stdlib exceptions and `SystemExit`.
- `verify.sh` uses a three-state result vocabulary (`PASS`/`WARN`/`FAIL`) with a running `FAILS` counter and explicit exit code, rather than Python tracebacks — this is the pattern for anything that checks "is the install correct."

## Logging

- Structured status lines use short tags: `ok()`, `warn()`, `fail()` shell functions in `verify.sh` printing `"  PASS  %s\n"` / `"  WARN  %s\n"` / `"  FAIL  %s\n"`.
- Python scripts print progress and results directly to stdout with f-strings; results destined for later analysis are written as JSONL (`bench/mq3d_layer2_verdicts.jsonl`) rather than logged.
- Comments embedded in code explain *why*, extensively — e.g. `patches/_check_applied.py` and `verify.sh` both carry paragraph-length comments justifying a specific check's existence, referencing GitHub issue numbers (`#35`, `#43`, `#67`) as historical context. Follow this: when a check exists because of a subtle prior failure, say so and cite the issue.

## Comments

## Function Design

## Module Design

<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->

## Architecture

## System Overview

```text

```

## Component Responsibilities

| Component | Responsibility | File |
|-----------|----------------|------|
| Entrypoint router | Dispatches container CMD to prepare/serve/verify | `docker/entrypoint.sh` |
| Model prep orchestrator | Idempotent download + requantize on first boot | `docker/prepare.sh` |
| Single-user launcher | Builds `vllm serve` invocation for MTP/DFlash2/KVarN low-latency mode | `single-user/start_qwen.sh` |
| Batch launcher | Builds `vllm serve` invocation for high-throughput batch mode | `batch/start_qwen.sh` |
| Alternative launcher | int4-per-token-head KV variant of single-user mode | `single-user/alternative.sh` |
| Install/patch verifier | Confirms venv, vLLM version, patches applied, model requantized, live server health | `verify.sh` |
| Patch application checker | Programmatically inspects vLLM source for patch markers | `patches/_check_applied.py` |
| vLLM version gate | Confirms vLLM series matches what patches target | `patches/check_vllm_series.sh` |
| Quantization scripts | One-time CPU-only rewrites of model weights (lm_head, embeddings, MTP head, draft vocab) | `prepare/quant_lm_head.py`, `prepare/quant_embed.py`, `prepare/quant_mtp.py`, `prepare/quant_heads_stream.py`, `prepare/build_draft_vocab.py` |
| Model fetchers | Download base/fast-variant/DFlash2/third-party checkpoints from HF Hub | `prepare/fetch_fast_variant.py`, `prepare/fetch_dflash2.py`, `prepare/fetch_thirdparty.py` |
| Drafter training/export tooling | Builds and requantizes the MTP/DFlash2 speculative drafters (offline research code) | `drafter/*.py` |
| vLLM source patches | Behavioral changes applied directly to the installed vLLM package (`patch -p1`) | `patches/*.patch` |
| KVarN KV-cache port | Copies new vLLM modules + patches to add the 4/2-bit KVarN cache and its V2-runner integration | `kvarn/install.sh`, `kvarn/files/vllm/**`, `kvarn/*.patch` |
| Benchmark/quality harness | Reproduces throughput, quality (GSM8K/perplexity/IFBench), concurrency, and regression numbers against a running server | `bench/*.py`, `bench/*.sh` |
| Container build | Freezes the above pipeline into an image (Python 3.12 venv, patches, KVarN, `verify.sh --install`) | `Dockerfile` |
| Container orchestration | Compose profiles for `prepare` / `single` / `batch` services sharing one model volume | `docker-compose.yml` |

## Pattern Overview

- No custom web/API layer — all HTTP surface (`/v1/chat/completions`, `/health`)
- Behavior changes are made by patching vLLM's source tree in
- Two independent "modes" (single-user, batch) share one codebase and one
- Heavy use of environment variables as the primary configuration surface
- Offline/one-time steps (model download, quantization, drafter training) are

## Layers

- Purpose: turn a published checkpoint into the exact on-disk shape the
- Location: `prepare/`, `drafter/`
- Contains: standalone Python scripts, CPU-only, run once per model
- Depends on: HF Hub, local torch/compressed-tensors/GPTQ tooling
- Used by: `docker/prepare.sh`, manual Setup steps in `README.md`
- Purpose: change vLLM's runtime behavior (attention backends, spec-decode
- Location: `patches/*.patch` (applied with `patch -p1` against
- Depends on: an exact vLLM version (0.28.0) — patches are version-pinned and
- Used by: `Dockerfile` build step, README manual setup, `kvarn/install.sh`
- Purpose: translate high-level env-var knobs into a single, long `vllm serve`
- Location: `single-user/start_qwen.sh`, `single-user/alternative.sh`,
- Depends on: the patched vLLM install, prepared model directory
- Used by: `docker/entrypoint.sh`, systemd units (`single-user/qwen-serving.service`,
- Purpose: gate that a build/install is correct before serving, and confirm a
- Location: `verify.sh`, `patches/_check_applied.py`
- Depends on: venv, installed vLLM, `patches/`, prepared model files
- Used by: `Dockerfile` (build-time `--install` mode), `docker/entrypoint.sh`
- Purpose: reproduce every performance/quality number quoted in the docs
- Location: `bench/*.py`, `bench/*.sh`
- Depends on: a running server (HTTP client only — no import of vLLM
- Used by: developers reproducing README numbers, CI is not evident for these

## Data Flow

### Primary Request Path (online serving)

### Preparation Flow (offline, one-time per model)

- No application state. All persistent state is either (a) files on disk

## Key Abstractions

- Purpose: represent a served configuration (mode × context tier × spec-decode
- Examples: `single-user/start_qwen.sh` (688 lines, dominant abstraction in the
- Pattern: env-var-driven branching (`CTX=fast|long|huge`, `SPEC=mtp|dflash2`)
- Purpose: each `.patch` in `patches/` is a self-contained, independently
- Examples: `patches/spec-decode-attn.patch`, `patches/int4-kv-per-token-head.patch`,
- Pattern: `patch -p1 -d <site-packages>/vllm < patch-file`; applied
- Purpose: `verify.sh` encodes "what a correct install looks like" as
- Examples: `verify.sh` (venv, vLLM version, patches, model requant, live

## Entry Points

- Location: `docker/entrypoint.sh`
- Triggers: `docker run` / `docker compose up` CMD argument (`single`,
- Responsibilities: run `docker/prepare.sh` and `verify.sh` gates, then `exec`
- Location: `single-user/start_qwen.sh` (also `single-user/alternative.sh` for
- Triggers: `bash single-user/start_qwen.sh`, `docker compose --profile single
- Responsibilities: resolve model/spec/context/env knobs into a `vllm serve`
- Location: `batch/start_qwen.sh`
- Triggers: `bash batch/start_qwen.sh`, `docker compose --profile batch up`,
- Responsibilities: same role as single-user launcher, tuned for high
- Location: `verify.sh`
- Triggers: run manually by a developer, or automatically at Docker build

## Architectural Constraints

- **Threading/process model:** Not owned by this repo — the serving process
- **Version pinning is load-bearing:** every file in `patches/` and
- **Global state:** the installed vLLM package under
- **One GPU serves one mode at a time:** `single` and `batch` are mutually
- **Idempotency by convention, not enforcement:** `docker/prepare.sh` and

## Anti-Patterns

### Patch application failure can be silent

### Environment variables as the sole configuration interface

## Error Handling

- `set -e` in shell entry scripts (`docker/entrypoint.sh`, `kvarn/install.sh`)
- Guard-and-abort checks in launchers for known-fatal misconfigurations

## Cross-Cutting Concerns

<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->

## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->

## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:

- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->

<!-- GSD:profile-start -->

## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
