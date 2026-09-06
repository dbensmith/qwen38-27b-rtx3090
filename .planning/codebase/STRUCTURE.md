# Codebase Structure

**Analysis Date:** 2026-09-05

## Directory Layout

```
qwen38-27b-rtx3090/
├── batch/              # High-throughput serving mode: launcher, README, systemd unit
├── bench/              # Benchmark, quality, and regression-detection scripts (run against a live server)
├── docker/             # Container entrypoint and model-preparation orchestration
├── docs/               # Design rationale, gotchas, quality tables, hardware reproductions
│   ├── media/          # Demo gif/video assets
│   └── reproductions/  # Community/independent hardware reproduction reports
├── drafter/            # Offline tooling to build/train/requantize speculative drafters (MTP, DFlash2)
├── kvarn/              # KVarN 4/2-bit KV-cache port: install script, vLLM patches, replacement files
│   └── files/vllm/     # Files copied wholesale into installed vLLM's site-packages (not patches)
├── patches/            # `.patch` files applied to the installed vLLM 0.28.0 package, plus patch tooling
├── prepare/            # One-time model download + requantization scripts (run before serving)
├── single-user/        # Low-latency serving mode: launcher(s), README, systemd unit
├── .planning/          # GSD planning artifacts (not part of the served product)
├── Dockerfile          # Freezes venv + patches + KVarN + verify.sh --install into one image
├── docker-compose.yml  # prepare/single/batch service profiles sharing one model volume
├── verify.sh           # Install/runtime correctness gate (venv, vLLM version, patches, model, live server)
└── README.md           # Primary documentation: quick start, benchmarks, setup, knob reference
```

## Directory Purposes

**`batch/`:**
- Purpose: everything specific to the high-throughput serving mode
- Contains: `start_qwen.sh` (launcher), `README.md` (full benchmark tables and env knobs for this mode), `qwen-serving.service` (systemd unit)
- Key files: `batch/start_qwen.sh`, `batch/README.md`

**`single-user/`:**
- Purpose: everything specific to the low-latency, few-user serving mode
- Contains: `start_qwen.sh` (primary launcher — MTP/DFlash2/KVarN, context tiers), `alternative.sh` (experimental int4-per-token-head KV variant), `README.md`, `qwen-serving.service`
- Key files: `single-user/start_qwen.sh` (688 lines — the largest single script in the repo)

**`prepare/`:**
- Purpose: one-time, CPU-only scripts that turn a downloaded checkpoint into the exact quantized shape the patched vLLM expects
- Contains: `fetch_*.py` (HF Hub downloads), `quant_*.py` (in-place weight requantization), `build_draft_vocab.py`, `draft_vocab_ids.json` (data file), `README.md`
- Key files: `prepare/quant_lm_head.py`, `prepare/quant_embed.py`, `prepare/quant_mtp.py`, `prepare/quant_heads_stream.py` (streaming variant for single-shard/asymmetric-AWQ checkpoints)

**`drafter/`:**
- Purpose: research/build tooling behind the speculative-decoding drafters shipped in `prepare/` — training, capture, export, quantization of MTP and DFlash2 heads
- Contains: `capture.py`, `capture_dflash2.py`, `train_mtp.py`, `export_mtp.py`, `gptq_lm_head.py`, `gptq_utils.py`, `quant_dflash2.py`, `requant_mtp_gptq.py`, `gen_data.py`, `collect_prompts.py`, `README.md` (documents what did and did not work)
- Key files: `drafter/README.md`

**`patches/`:**
- Purpose: version-pinned source patches applied to `venv/lib/python3.12/site-packages/vllm` via `patch -p1`, each addressing one bug/feature/optimization against vLLM 0.28.0
- Contains: one `.patch` file per behavior change (attention backends, KV cache dtypes, sampler tweaks, Marlin kernel tuning, spec-decode fixes), plus `_check_applied.py` (programmatic verification) and `check_vllm_series.sh` (version gate)
- Key files: `patches/_check_applied.py`, `patches/check_vllm_series.sh`, `patches/dflash2-backport.patch` (skipped — DFlash2 is native in 0.28.0)

**`kvarn/`:**
- Purpose: ports the KVarN 4/2-bit KV-cache implementation into vLLM, including the V2 model-runner integration needed to combine it with DFlash2 and prefix caching
- Contains: `install.sh` (copies `files/vllm/**` into site-packages then applies patches), `kvarn-0.27.1.patch`/`kvarn-0.28.0.patch` (base port per vLLM version), `kvarn-v2-runner.patch`/`kvarn-v2-runner-0.28.0.patch` (V2 runner integration, applied last), `files/vllm/` (whole replacement/new files, not diffs), `README.md`
- Key files: `kvarn/install.sh`

**`docker/`:**
- Purpose: container-specific orchestration glue not needed by the manual venv install
- Contains: `entrypoint.sh` (CMD router), `prepare.sh` (idempotent prepare-on-first-boot), `requirements.txt` (pip deps for the image)
- Key files: `docker/entrypoint.sh`

**`bench/`:**
- Purpose: reproduce every performance/quality number in the README and docs against a live server; also doubles as regression detection for known vLLM bugs (residue corruption, capture-mode correctness, KV geometry edge cases)
- Contains: `run_benchmarks.sh` (top-level driver), per-topic scripts (`conc_ladder.py`, `labd_bench.py`, `needle_test.py`, `quality_battery.py`, `residue_sweep.py`, `verbatim.py`, `test_lookup_kernels.py`, `test_spec_decode_attn.py`, ...), fixed prompt/data files (`prompts_real.jsonl`, `mq3d_layer2_verdicts*.jsonl`)
- Key files: `bench/run_benchmarks.sh`

**`docs/`:**
- Purpose: prose documentation too detailed for the README — optimization rationale, gotchas, quality tables, hardware-specific reproductions
- Contains: `optimizations.md`, `gotchas.md`, `quality.md`, `docker.md`, `long-context.md`, `python-314.md`, hardware-specific notes (`wsl2-4090.md`, `ubuntu-3090.md`), `reproductions/` (community reproduction reports), `media/` (demo assets)
- Key files: `docs/gotchas.md` (18 numbered issues, referenced by number elsewhere in the repo), `docs/optimizations.md`

**`.planning/`:**
- Purpose: GSD workflow planning artifacts (this document's own home); not part of the served product or the Docker image
- Contains: `.planning/codebase/*.md` (this analysis)

## Key File Locations

**Entry Points:**
- `docker/entrypoint.sh`: container CMD router (prepare/single/batch/verify/passthrough)
- `single-user/start_qwen.sh`: primary low-latency launcher
- `batch/start_qwen.sh`: high-throughput launcher
- `single-user/alternative.sh`: experimental int4-KV launcher

**Configuration:**
- `docker-compose.yml`: service profiles, volumes, `.env` wiring
- `.env` (not committed; created by the user per README): `VLLM_API_KEY`, `SPEC`, `CTX`, etc.
- `api_key.txt` (not committed): alternative API key source
- `docker/requirements.txt`: container pip dependencies

**Core Logic (in the sense of "what this repo actually builds"):**
- `patches/*.patch`: the behavior changes to vLLM itself
- `kvarn/install.sh` + `kvarn/files/vllm/**`: the KVarN KV-cache port
- `prepare/*.py`: model artifact preparation
- `drafter/*.py`: drafter training/export (upstream of what `prepare/` consumes)

**Verification/Testing:**
- `verify.sh`: install + runtime correctness gate
- `patches/_check_applied.py`: patch-application checker
- `bench/*.py`, `bench/*.sh`: benchmark and regression scripts (run against a live server, not unit tests)

## Naming Conventions

**Files:**
- Shell launchers: `start_qwen.sh`, `alternative.sh` — verb-first or descriptive, one per serving mode/variant
- Patch files: `<area>-<specific-change>.patch`, kebab-case, describing the fix/feature (e.g.
  `spec-decode-attn.patch`, `mamba-align-checkpoint-order.patch`, `int4-kv-per-token-head.patch`)
- Prepare scripts: `<verb>_<target>.py`, snake_case (`quant_lm_head.py`, `fetch_dflash2.py`, `build_draft_vocab.py`)
- Bench scripts: `<topic>_<kind>.py` or `<topic>.sh`, snake_case (`conc_ladder.py`, `residue_sweep.py`, `run_benchmarks.sh`)
- Docs: `UPPERCASE.md` only for top-level meta docs generated by tooling (`MR-DRAFT.md`); otherwise lowercase kebab (`long-context.md`, `wsl2-4090.md`)

**Directories:**
- One directory per serving mode (`single-user/`, `batch/`) mirroring each other's internal file layout (`start_qwen.sh`, `README.md`, `qwen-serving.service`)
- One directory per cross-cutting concern (`patches/`, `kvarn/`, `bench/`, `prepare/`, `drafter/`, `docs/`, `docker/`)
- `kvarn/files/vllm/` mirrors the internal package layout of vLLM itself (`v1/attention/`, `model_executor/layers/`) so it can be `cp -r`'d straight into `site-packages/vllm/`

## Where to Add New Code

**New serving mode or variant:**
- Add a new launcher script alongside `single-user/start_qwen.sh` / `batch/start_qwen.sh` (or a new top-level directory if it's a third distinct mode), following the existing pattern: env-var-driven flag assembly ending in `exec vllm serve ...`. Add a matching `README.md` in that directory and wire it into `docker/entrypoint.sh`'s case statement and `docker-compose.yml`'s service list if it should be containerized.

**New vLLM behavior patch:**
- Add a new `.patch` file to `patches/`, named `<area>-<change>.patch`, written against `vllm==0.28.0`. Update the loop in `Dockerfile` and the manual `for p in patches/*.patch` loop in `README.md`'s Setup section only if the patch needs a special case (like the DFlash2-backport skip). Add corresponding assertions to `patches/_check_applied.py` and, if install-affecting, to `verify.sh`.

**New model preparation step:**
- Add a script to `prepare/` (CPU-only, idempotent, operating on a `models/<checkpoint>` directory in place). Reference it from `docker/prepare.sh`'s orchestration logic and from the manual Setup steps in `README.md`.

**New benchmark/quality check:**
- Add a script to `bench/`, following the existing pattern of a standalone Python/bash script that talks HTTP to a running server (port 18020) and prints/reproduces one specific table from the docs. Wire it into `bench/run_benchmarks.sh` if it should run as part of the standard suite.

**New drafter research code:**
- Add to `drafter/`; document outcomes (including negative results) in `drafter/README.md`, matching the existing convention there.

**New documentation:**
- Deep-dive prose goes in `docs/` as a new `.md` file, linked from the "The rest" table at the bottom of `README.md`. Hardware-specific reproduction reports go in `docs/reproductions/` or as a dedicated `docs/<hardware>.md` (see `docs/wsl2-4090.md`, `docs/ubuntu-3090.md`).

## Special Directories

**`models/`** (not present in the repo tree, created at runtime):
- Purpose: holds downloaded and requantized model checkpoints
- Generated: Yes (by `prepare/*.py` / `docker/prepare.sh`)
- Committed: No (gitignored; mounted as a Docker volume or bind mount)

**`venv/`** (not present in the repo tree, created by manual Setup):
- Purpose: Python 3.12 virtualenv containing the installed and patched `vllm` package
- Generated: Yes
- Committed: No

**`kvarn/files/vllm/`:**
- Purpose: whole-file replacements/additions copied directly into `site-packages/vllm` by `kvarn/install.sh` (as opposed to `.patch` diffs)
- Generated: No — hand-maintained source, committed as-is
- Committed: Yes

**`.planning/`:**
- Purpose: GSD workflow state and generated codebase analysis (this file's directory)
- Generated: Yes (by GSD tooling)
- Committed: Per project convention — currently untracked (`?? .planning/` in git status)

---

*Structure analysis: 2026-09-05*
