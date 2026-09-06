<!-- refreshed: 2026-09-05 -->
# Architecture

**Analysis Date:** 2026-09-05

## System Overview

This is not a conventional application with internal layers — it is a **serving
configuration and patch-set repository** built around an unmodified, externally
installed `vllm==0.28.0` package. The "architecture" is a pipeline: prepare model
weights on disk → patch the installed vLLM package in `site-packages` → launch
`vllm serve` with a large, carefully tuned set of CLI flags and environment
variables. There is no framework code owned by this repo that vLLM imports at
runtime; everything is either (a) a shell script that constructs a `vllm serve`
command line, (b) a one-time Python data-prep/quantization script, or (c) a
`.patch` file applied directly into vLLM's installed source tree.

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    docker/entrypoint.sh (container CMD)              │
│   selects: prepare | single | batch | verify | passthrough           │
└───────────────┬───────────────────────────┬──────────────────────────┘
                │                           │
                ▼                           ▼
┌───────────────────────────┐   ┌─────────────────────────────────────┐
│  docker/prepare.sh          │   │  single-user/start_qwen.sh          │
│  `docker/prepare.sh`        │   │  batch/start_qwen.sh                │
│  downloads + requantizes    │   │  build env/flags, exec `vllm serve` │
│  the model into ./models    │   │  (the actual long-running process)  │
└───────────────┬─────────────┘   └───────────────┬─────────────────────┘
                │                                  │
                ▼                                  ▼
┌────────────────────────────┐    ┌────────────────────────────────────┐
│  prepare/*.py                │    │  installed `vllm` package          │
│  quant_lm_head.py             │    │  venv/lib/python3.12/site-packages/│
│  quant_embed.py               │    │  vllm — patched in place by:        │
│  quant_mtp.py                 │    │   - patches/*.patch (patch -p1)     │
│  build_draft_vocab.py         │    │   - kvarn/install.sh (file copy +   │
│  fetch_fast_variant.py        │    │     patch, for KVarN KV cache)      │
│  fetch_dflash2.py             │    └────────────────────────────────────┘
│  fetch_thirdparty.py          │
│  quant_heads_stream.py        │
└────────────────────────────┘
                │
                ▼
┌────────────────────────────────────────────────────────────────────┐
│  ./models/<checkpoint-dir>  (compressed-tensors / GPTQ shards)       │
│  bind-mounted or volume-mounted into the container as /app/models   │
└────────────────────────────────────────────────────────────────────┘
```

`verify.sh` sits alongside this pipeline as a gate, not a layer: it asserts the
venv/vLLM version, that every applicable patch in `patches/` landed, that the
model was requantized, and (optionally) that a running server answers with the
expected attention backend / KV pool. It runs at Docker build time
(`--install`), at container start (inside `docker/entrypoint.sh`), and can be
run manually against a live server.

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

**Overall:** Configuration-and-patch pipeline around a vendored, unmodified
third-party server (vLLM). There is no in-repo request-handling code; the
running server *is* `vllm serve`, an OpenAI-compatible HTTP API implemented
entirely inside the patched `vllm` package. This repo's code exists to (1)
prepare model artifacts, (2) mutate the installed vLLM package via patch files,
and (3) launch vLLM with the right flags for a chosen tradeoff (latency vs.
throughput vs. context length).

**Key Characteristics:**
- No custom web/API layer — all HTTP surface (`/v1/chat/completions`, `/health`)
  is vLLM's own OpenAI-compatible server, started via `vllm serve` inside the
  `start_qwen.sh` scripts.
- Behavior changes are made by patching vLLM's source tree in
  `site-packages`, not by monkeypatching or wrapping it in-process.
- Two independent "modes" (single-user, batch) share one codebase and one
  Docker image; the mode selected is purely which shell script/CLI arg is
  invoked.
- Heavy use of environment variables as the primary configuration surface
  (`CTX`, `SPEC`, `MODEL`, `KV_MEM`, `MAX_SEQS`, `DFLASH_TOKENS`, `INT8_ACT`,
  `EXTRA_ARGS`, etc.) — read directly in the bash launchers.
- Offline/one-time steps (model download, quantization, drafter training) are
  fully separated from the online serving path.

## Layers

**Preparation layer:**
- Purpose: turn a published checkpoint into the exact on-disk shape the
  patched vLLM expects (quantized lm_head/embeddings/MTP head, draft
  vocabulary, DFlash2 drafter weights).
- Location: `prepare/`, `drafter/`
- Contains: standalone Python scripts, CPU-only, run once per model
- Depends on: HF Hub, local torch/compressed-tensors/GPTQ tooling
- Used by: `docker/prepare.sh`, manual Setup steps in `README.md`

**Patch layer:**
- Purpose: change vLLM's runtime behavior (attention backends, spec-decode
  scratch buffers, Marlin kernel tuning, KV cache dtypes, sampler behavior)
  without forking the whole project.
- Location: `patches/*.patch` (applied with `patch -p1` against
  `site-packages/vllm`), `kvarn/*.patch` + `kvarn/files/vllm/**` (file
  copy + patch for the KVarN KV cache and V2 runner)
- Depends on: an exact vLLM version (0.28.0) — patches are version-pinned and
  gated by `patches/check_vllm_series.sh`
- Used by: `Dockerfile` build step, README manual setup, `kvarn/install.sh`

**Launch layer:**
- Purpose: translate high-level env-var knobs into a single, long `vllm serve`
  command line, including model path resolution (fast variant vs base vs
  third-party), speculative-decoding config (MTP vs DFlash2 vs none), context
  length tier (`fast`/`long`/`huge`), and safety checks (stale shared-memory
  cleanup, WSL2 pinned-memory requirement, KV_MEM sizing for TP>1).
- Location: `single-user/start_qwen.sh`, `single-user/alternative.sh`,
  `batch/start_qwen.sh`
- Depends on: the patched vLLM install, prepared model directory
- Used by: `docker/entrypoint.sh`, systemd units (`single-user/qwen-serving.service`,
  `batch/qwen-serving.service`), manual invocation

**Verification layer:**
- Purpose: gate that a build/install is correct before serving, and confirm a
  running server's live configuration (backend, KV pool size) matches
  expectations.
- Location: `verify.sh`, `patches/_check_applied.py`
- Depends on: venv, installed vLLM, `patches/`, prepared model files
- Used by: `Dockerfile` (build-time `--install` mode), `docker/entrypoint.sh`
  (start-time, unless `VERIFY=0`), manual runs

**Benchmark/measurement layer:**
- Purpose: reproduce every performance/quality number quoted in the docs
  against a live server; also used as regression detectors for known vLLM
  bugs (e.g. residue corruption, capture-mode correctness).
- Location: `bench/*.py`, `bench/*.sh`
- Depends on: a running server (HTTP client only — no import of vLLM
  internals except where a script directly probes kernels, e.g.
  `bench/test_lookup_kernels.py`)
- Used by: developers reproducing README numbers, CI is not evident for these

## Data Flow

### Primary Request Path (online serving)

1. Container starts with CMD `single` or `batch` (`docker/entrypoint.sh:1`)
2. `docker/prepare.sh` runs if the model isn't already prepared (idempotent
   check + download + requantize) (`docker/entrypoint.sh` invokes
   `docker/prepare.sh`)
3. `verify.sh --no-server` gates the boot — aborts on FAIL unless `VERIFY=0`
4. `single-user/start_qwen.sh` or `batch/start_qwen.sh` resolves the model
   path, speculative-decoding mode, context tier, and KV cache settings from
   env vars, then `exec`s `vllm serve ...` with the assembled flags
5. vLLM's own OpenAI-compatible server (inside the patched package) handles
   all subsequent HTTP traffic (`/v1/chat/completions`, `/health`) — no
   request ever passes through repo-owned Python code at runtime
6. Speculative decoding, KV cache management, and attention are all inside
   vLLM, modified by the patches applied in step 0 (build time) rather than
   by any code invoked per-request

### Preparation Flow (offline, one-time per model)

1. `prepare/fetch_fast_variant.py` / `fetch_dflash2.py` / `fetch_thirdparty.py`
   download checkpoint shards from Hugging Face Hub into `./models`
2. `prepare/quant_lm_head.py`, `quant_embed.py`, `quant_mtp.py` (or
   `quant_heads_stream.py` for single-shard/asymmetric-AWQ checkpoints)
   requantize specific weight tensors in place (CPU-only)
3. `prepare/build_draft_vocab.py` builds a reduced draft vocabulary from
   `prepare/draft_vocab_ids.json` or a corpus of the model's own outputs
4. Resulting artifacts live under `models/<checkpoint-name>[-fast]/` and are
   read directly by vLLM at serve time — no intermediate database or service

**State Management:**
- No application state. All persistent state is either (a) files on disk
  under `./models` (weights) and `/cache` (torch.compile/Triton/FlashInfer JIT
  caches, HF hub cache — `HOME=/cache` in `Dockerfile`), or (b) in-process
  state owned entirely by the vLLM engine (KV cache, recurrent/mamba state,
  request scheduler) at runtime.

## Key Abstractions

**Launcher scripts as the "config layer":**
- Purpose: represent a served configuration (mode × context tier × spec-decode
  algorithm × quantization) as a single shell invocation, rather than as a
  structured config object.
- Examples: `single-user/start_qwen.sh` (688 lines, dominant abstraction in the
  repo), `batch/start_qwen.sh`
- Pattern: env-var-driven branching (`CTX=fast|long|huge`, `SPEC=mtp|dflash2`)
  that builds up a bash array of `vllm serve` CLI flags before `exec`ing it.

**Patch files as behavior modules:**
- Purpose: each `.patch` in `patches/` is a self-contained, independently
  applicable unit of behavior change against one pinned vLLM version, with a
  header explaining the bug/feature and its measurement.
- Examples: `patches/spec-decode-attn.patch`, `patches/int4-kv-per-token-head.patch`,
  `patches/mamba-align-checkpoint-order.patch`
- Pattern: `patch -p1 -d <site-packages>/vllm < patch-file`; applied
  idempotently at build time and checked programmatically by
  `patches/_check_applied.py`.

**Verification as executable spec:**
- Purpose: `verify.sh` encodes "what a correct install looks like" as
  PASS/WARN/FAIL checks rather than as documentation alone.
- Examples: `verify.sh` (venv, vLLM version, patches, model requant, live
  server probe)

## Entry Points

**Container entrypoint:**
- Location: `docker/entrypoint.sh`
- Triggers: `docker run` / `docker compose up` CMD argument (`single`,
  `batch`, `prepare`, `verify`, or arbitrary passthrough command)
- Responsibilities: run `docker/prepare.sh` and `verify.sh` gates, then `exec`
  into the chosen launcher script

**Single-user launcher:**
- Location: `single-user/start_qwen.sh` (also `single-user/alternative.sh` for
  the experimental int4-per-token-head KV variant)
- Triggers: `bash single-user/start_qwen.sh`, `docker compose --profile single
  up`, systemd unit `single-user/qwen-serving.service`
- Responsibilities: resolve model/spec/context/env knobs into a `vllm serve`
  command for low-latency, few-concurrent-user serving

**Batch launcher:**
- Location: `batch/start_qwen.sh`
- Triggers: `bash batch/start_qwen.sh`, `docker compose --profile batch up`,
  systemd unit `batch/qwen-serving.service`
- Responsibilities: same role as single-user launcher, tuned for high
  concurrency/throughput instead of latency

**Manual verification:**
- Location: `verify.sh`
- Triggers: run manually by a developer, or automatically at Docker build
  time (`--install`) and container start (inside `docker/entrypoint.sh`)

## Architectural Constraints

- **Threading/process model:** Not owned by this repo — the serving process
  is vLLM's own async engine and worker processes. This repo only controls
  process launch (CLI flags/env vars) and cannot alter vLLM's internal
  concurrency model except via source patches.
- **Version pinning is load-bearing:** every file in `patches/` and
  `kvarn/*.patch` is written against exactly `vllm==0.28.0`; `verify.sh` and
  `patches/check_vllm_series.sh` exist specifically because these patches do
  not survive a vLLM upgrade unmodified.
- **Global state:** the installed vLLM package under
  `venv/lib/python3.12/site-packages/vllm` (or the container's `/app/venv`) is
  mutated in place by both `patches/*.patch` and `kvarn/install.sh` — it is
  shared, mutable, and order-dependent (`kvarn-v2-runner-0.28.0.patch` must
  apply after both `patches/*.patch` and `kvarn-0.28.0.patch`).
- **One GPU serves one mode at a time:** `single` and `batch` are mutually
  exclusive on a single 24 GB card (`docker-compose.yml` comment: "One GPU:
  run either 'single' or 'batch', not both").
- **Idempotency by convention, not enforcement:** `docker/prepare.sh` and
  `kvarn/install.sh` are designed to be safely re-run, but `patch --forward`
  cannot distinguish "already applied" from "does not apply" — both exit
  non-zero, so failures on a mismatched vLLM tree can be silent unless caught
  by the explicit hunk-marker count check in `kvarn/install.sh`.

## Anti-Patterns

### Patch application failure can be silent

**What happens:** `kvarn/install.sh` applies patches with `... || true` because
`patch --forward` cannot distinguish an already-applied hunk from one that
simply does not match the tree.
**Why it's wrong:** A vLLM tree that doesn't match the patch's assumptions
fails to apply the same way a no-op rerun does — both exit non-zero — so a
silent partial port is possible with no error surfaced to the caller.
**Do this instead:** The script mitigates this by counting per-file "marker"
strings the patch is expected to introduce and failing loudly if the count is
short (see the Python block at the end of `kvarn/install.sh`); any new patch
added to this repo should follow that same explicit-marker verification
pattern rather than trusting `patch`'s exit code alone.

### Environment variables as the sole configuration interface

**What happens:** All serving configuration (`CTX`, `SPEC`, `MODEL`, `KV_MEM`,
`MAX_SEQS`, `DFLASH_TOKENS`, `INT8_ACT`, `EXTRA_ARGS`, ...) is read as loose
shell environment variables inside `single-user/start_qwen.sh` and
`batch/start_qwen.sh`, with no schema, validation library, or single source of
truth for valid combinations.
**Why it's wrong:** Invalid combinations (e.g. `DFLASH_TOKENS=15 MAX_SEQS=8`,
called out explicitly in `README.md`) are caught only by ad-hoc guards inside
the bash scripts or, historically, by OOM crashes at request time.
**Do this instead:** When adding a new knob, add both a bash-level guard in
the launcher (matching the existing style, e.g. the `MAX_SEQS` cap already in
`single-user/start_qwen.sh`) and a corresponding `verify.sh` check if the
knob affects install correctness rather than only runtime behavior.

## Error Handling

**Strategy:** Fail loudly and early at boot/build time (`verify.sh`,
`patches/check_vllm_series.sh`); at runtime, error handling is vLLM's own
(HTTP 500s from the OpenAI-compatible server) since no repo-owned code
intercepts requests.

**Patterns:**
- `set -e` in shell entry scripts (`docker/entrypoint.sh`, `kvarn/install.sh`)
  so any failed step aborts the container/install rather than continuing in a
  half-applied state.
- Guard-and-abort checks in launchers for known-fatal misconfigurations
  (e.g. stale `/dev/shm/vllm_offload_*.mmap` regions cleaned up before boot in
  `single-user/start_qwen.sh`; WSL2 pinned-memory requirement checked before
  `SPEC=dflash2` boots).

## Cross-Cutting Concerns

**Logging:** No custom logging framework; relies on vLLM's own stdout/stderr
logging plus bash `echo` statements for setup/verification steps
(`verify.sh`, `docker/prepare.sh`).

**Validation:** `verify.sh` is the central validation point (venv, vLLM
version, patches, model requantization, live server checks). Launcher scripts
add narrower validation (env var sanity, stale-file cleanup) inline.

**Authentication:** `VLLM_API_KEY` env var (or `api_key.txt`), read by vLLM's
own server; unauthenticated by default per `README.md` ("server listens on
`0.0.0.0` and is unauthenticated unless you give it a key").

---

*Architecture analysis: 2026-09-05*
