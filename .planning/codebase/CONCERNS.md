# Codebase Concerns

**Analysis Date:** 2026-09-05

This repo is a heavily-patched vLLM deployment (Qwen3.8-27B on a single RTX 3090). Its
authors already maintain an extensive first-party concerns log — `docs/gotchas.md`
(52 numbered entries, ~880 lines) — which is more detailed than anything a fresh
scan can reconstruct. This document indexes the highest-impact items from that log
plus concerns found by scanning the code directly, so future planning work can
locate them without reading all 880 lines up front.

## Tech Debt

**Silent broad exception handling in the attention backend:**
- Issue: multiple `except Exception:` blocks swallow errors and fall back to a
  module-level cached value, rather than surfacing what failed
- Files: `kvarn/files/vllm/v1/attention/backends/kvarn_attn.py:151`, `:480`, `:496`,
  `:533`, `:1296`, `:1576`, `:1786`
- Impact: a real config/version mismatch (e.g. a future vLLM upgrade changing
  `cfg.cache_config`) degrades silently to a stale cached preset instead of failing
  loudly — the exact failure mode gotcha #1 warns about ("a benchmark cannot tell
  you the output is garbage")
- Fix approach: each is commented as an intentional `port(0.27.1)` compatibility
  shim with a documented fallback; when bumping vLLM versions, re-audit each site
  against the new upstream API rather than trusting the except-and-fallback to
  still be correct

**Unfinished eviction hook in KVarN attention:**
- Issue: explicit `TODO(Stage 4.5.e)` left in production code
- Files: `kvarn/files/vllm/v1/attention/backends/kvarn_attn.py:1215`
- Impact: KV cache is not wired into vLLM's request-completion hook for eviction —
  unclear whether pages are reclaimed promptly on request completion or rely on a
  different mechanism
- Fix approach: trace the current eviction path before touching KVarN internals;
  do not assume the hook exists

**Patch-stack maintenance burden:**
- Issue: the whole project is ~30 hand-maintained patch files against vLLM
  (`patches/*.patch`, `kvarn/*.patch`) rather than upstream contributions or a fork
- Files: `patches/` (30 files), `kvarn/kvarn-0.27.1.patch`, `kvarn/kvarn-0.28.0.patch`,
  `kvarn/kvarn-v2-runner*.patch`
- Impact: every vLLM version bump requires re-deriving/re-testing every patch;
  `patches/check_vllm_series.sh` and `patches/_check_applied.py` exist specifically
  to detect drift, and `verify.sh` (12.7 KB) is the release gate
- Fix approach: when upgrading vLLM, run `verify.sh` and the check scripts first;
  treat any patch that fails to apply as a signal the underlying vLLM internals
  changed, not a trivial fuzz-and-continue

**Version-branch fork in README/behavior:**
- Issue: README explicitly notes the branch pins vLLM 0.28.0 while some
  throughput/quality tables are "retained as reference baselines" from the 0.27.1
  measurements and have not been re-verified end-to-end (README.md:39-40)
- Files: `README.md`
- Impact: numbers quoted for decision-making (which SPEC/CTX mode to pick) may not
  reflect current-branch reality until the "GPU matrix is being re-measured" work
  lands
- Fix approach: re-run `bench/run_benchmarks.sh` before trusting any throughput
  table for a new decision

## Known Bugs (self-documented, with workarounds shipped)

The project keeps a running list of vLLM-side and stack-side bugs it works around.
Full detail: `docs/gotchas.md`. Highest-impact ones for anyone touching this code:

**Cold-start GPU memory profiling races:**
- Symptoms: restarting onto a not-yet-freed GPU silently gives ~40% less KV cache
  pool, with no warning and no crash
- Files: gotcha #2 in `docs/gotchas.md`; mitigated by an `ExecStartPre` gate in the
  systemd unit files (`single-user/qwen-serving.service`)
- Trigger: fast restart cycles, especially in CI/automation
- Workaround: wait for GPU to actually free before starting; the shipped systemd
  units already do this — don't bypass them

**FlashAttention-2 / Triton unified attention don't split KV for multi-query decode:**
- Symptoms: verify-step latency scales badly (57 µs → 1.3 ms per layer) once the
  speculative verify block grows past a handful of tokens, because these paths run
  one thread block per (request, head)
- Files: gotcha #13; worked around in `patches/spec-decode-attn.patch`
  (`VLLM_SPEC_DECODE_ATTN=1`, bf16 KV only)
- Trigger: `DFLASH_TOKENS`/verify block size increases (e.g. `DFLASH_TOKENS=15`)
- Workaround note: the custom kernel used to silently fall back past 10 query
  tokens per block, doubling step time at 25k context before it was fixed to tile
  query rows instead — a regression class to watch for if this kernel is touched again

**torch.compile cache is unaware of custom env-var-driven behavior:**
- Symptoms: switching `INT8_LAYERS` between runs replays a stale compiled graph
  and dies with `KeyError: 'input_global_scale'`
- Files: gotcha #5
- Workaround: the patch stack registers selection env vars into vLLM's cache key;
  any *new* env var this project adds that changes traced graph shape must be
  registered the same way, or set `VLLM_DISABLE_COMPILE_CACHE=1`

**`prompt_logprobs` OOMs / is wrong under several configs:**
- Symptoms: OOMs at `gpu-memory-utilization` 0.972 on long prompts (gotcha #10);
  separately, produces wrong values under `CTX=huge` + `SPEC=mtp` + prefix caching
  (gotcha #51)
- Files: gotcha #10, #51 in `docs/gotchas.md`
- Trigger: quality/eval tooling that requests logprobs against long prompts
- Workaround: run quality checks at `gpu-memory-utilization 0.93`, and be aware
  logprobs are untrustworthy in the #51 configuration combination

**sm80 (GA100) Marlin repack can Xid-31 the whole card under memory pressure:**
- Symptoms: full GPU fault, not just a process crash
- Files: gotcha #41; `patches/marlin-repack-staged-sm80.patch`
- Trigger: Marlin int8/int4 repack path on sm80-class silicon under pressure
- Workaround: staged repack patch; treat any Marlin-repack change as needing a
  memory-pressure soak test before trusting it on sm80

**Xgrammar / tool-calling under a speculator killed requests at certain lengths:**
- Files: gotcha #40; `patches/xgrammar-spec-terminated.patch`
- Trigger: structured output or tool calling combined with speculative decoding
- Workaround: patch applied; re-test this path specifically after any spec-decode
  change

## Security Considerations

**Server binds `0.0.0.0` unauthenticated by default:**
- Risk: anyone who can reach the host on port 18020 gets full inference API access
  with no key, by default
- Files: `README.md:59-65`, `docker-compose.yml:760` (comment: "api key — optional,
  but the server binds 0.0.0.0 and is open without one")
- Current mitigation: documented prominently in the README's Quick Start; reads
  `VLLM_API_KEY` from `.env` or `api_key.txt` if present
- Recommendations: this is a self-hosted single-tenant tool by design, so the
  current "opt-in key" posture is a reasonable tradeoff — but any deployment
  automation built on top of this repo (docker-compose wrappers, CI, cloud
  install scripts) must not skip generating a key, and should fail closed
  (refuse to bind non-loopback without a key) rather than fail open

**`.env` / `api_key.txt` handling:**
- Risk: standard secret-in-file pattern; already gitignored (`.gitignore`)
- Files: `.gitignore`, `docker-compose.yml`
- Current mitigation: `.dockerignore` and `.gitignore` both present — verified
  they exclude env/secret files
- Recommendations: none needed beyond current practice; do not add logging that
  echoes the resolved `VLLM_API_KEY` value

## Performance Bottlenecks

**Benchmarking pitfalls are a first-class documented concern, not incidental:**
- Problem: naive benchmarking on this stack produces meaningless or misleading
  numbers in at least four distinct ways
- Files: `docs/gotchas.md` gotchas #1, #6, #7, #8, #46
- Cause: (1) throughput numbers say nothing about output quality — the int8
  activation path once served nonsense for an hour at "great" tok/s; (2)
  random-token benchmarks are meaningless for speculative decoding since
  acceptance depends on drafter guessability; (3) larger prefill chunks
  (`--max-num-batched-tokens 8192`) inflate profiled activation peak and *shrink*
  the KV cache pool, capping concurrency — counter to intuition; (4) the first
  run after any restart reads 30-50% low due to JIT warmup; (5) `vllm bench serve`
  defaults to `--seed 0`, which combined with prefix caching under-counts real cold
  traffic
- Improvement path: always use `bench/quality_battery.py` alongside throughput
  runs, use `bench/prompts_real.jsonl`-style real prompts (not random tokens),
  keep `--max-num-batched-tokens` at 2048 on this card, and discard the first
  post-restart run

**Recurrent-state page cost scales with verify-block size, not token count:**
- Problem: increasing `DFLASH_TOKENS` (verify block) can more than double the
  recurrent-state memory each resident request holds (1.66 GiB vs 0.88 GiB per
  the "gotcha 33" fit), which is why it costs half the request slots and 8k of
  context in the DFlash2 table in the README
- Files: `docs/gotchas.md` gotcha #33, #38; `README.md:143-148`
- Cause: aligned recurrent-state pages are sized to the verify block, and the
  decode-graph CUDA-graph budget is fixed at 64 query tokens with `MAX_SEQS`
  multiplying into it
- Improvement path: tune `DFLASH_TOKENS`/`DRAFT_TOKENS` per workload as the README
  recommends (7 for chat, 15 for document-reproduction workloads); do not raise it
  globally without re-checking KV pool sizing

## Fragile Areas

**`kvarn_attn.py` (2,743 lines) — the KV-cache-compression attention backend:**
- Files: `kvarn/files/vllm/v1/attention/backends/kvarn_attn.py`
- Why fragile: it is a hand-ported compatibility shim against a specific vLLM
  internal API surface (comments throughout are tagged `port(0.27.1)` referencing
  an internal design doc "plan §2.1.x"); relies on module-level class state
  (`KVarNAttentionImpl._active_cache_dtype`) as a fallback when
  `get_current_vllm_config_or_none()` returns `None`, which is inherently a
  process-global assumption
- Safe modification: never touch this file without first re-reading the adjacent
  `port(0.27.1)` comments explaining *why* each shim exists, and running
  `verify.sh` plus `bench/quality_battery.py` afterward — a change here that looks
  correct can silently corrupt output (gotcha #1's exact failure mode)
- Test coverage: `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`,
  `bench/mq3d_scratch_pool_test.py` exist and should be run before/after any change
  here; there is no CI-gated unit test suite beyond `verify.sh`'s end-to-end checks

**Environment-variable-driven behavior with no schema/validation layer:**
- Files: `README.md`, `docker-compose.yml`, start scripts
  (`single-user/start_qwen.sh`, `single-user/alternative.sh`, `batch/`)
- Why fragile: dozens of env vars (`SPEC`, `CTX`, `DFLASH_TOKENS`, `DRAFT_TOKENS`,
  `INT8_LAYERS`, `INT8_ACT`, `VISION`, `VISION_OFFLOAD`, `PREFIX_CACHE`, `KV_MEM`,
  `MAX_SEQS`, `GPU_UTIL`, ...) combine in ways that are only individually documented
  as gotchas when they interact badly (e.g. gotcha #19: `INT8_LAYERS=.` needs
  `GPU_UTIL=0.95`; gotcha #52: `DFLASH_TOKENS=15` asserts at engine start on the
  int4 path)
- Safe modification: before adding a new env var, check `docs/gotchas.md` for
  existing interaction constraints on the vars it will combine with, and add a
  new numbered gotcha entry if a new interaction constraint is discovered
- Test coverage: no automated matrix test across env-var combinations; reliance is
  on documented tribal knowledge plus manual soak tests mentioned in gotchas
  (e.g. "we soak-tested 0.93 with a 100k-token prompt plus 6k-token generations")

**Hardware-specific numeric constants:**
- Files: `docs/gotchas.md` throughout (e.g. gotcha #33's "0.88 GiB" fit,
  gotcha #9's "0.858 GiB" vision tower size, gotcha #39's "396 MiB" kill zone)
- Why fragile: many thresholds are empirically fitted to a specific RTX 3090 at a
  250 W power limit and may not transfer to other GPUs, power limits, or even a
  different 3090 with different host RAM contention
- Safe modification: treat any hardcoded byte/token threshold in code or scripts
  as card-specific; re-derive rather than copy when porting to different hardware
  (see `docs/wsl2-4090.md`, `docs/ubuntu-3090.md`, `docs/reproductions/native-3090.md`
  for existing cross-hardware reproduction notes and their caveats)

## Scaling Limits

**Single-GPU, single-tenant-at-a-time design:**
- Current capacity: one RTX 3090 (24 GB) serves one mode (single-user or batch) at
  a time; "More than one GPU" is covered only briefly in the README (`README.md:479`)
- Limit: multi-GPU / tensor-parallel is explicitly a secondary, less-tested path
  compared to the single-3090 configuration the whole gotchas log is built around
- Scaling path: `README.md` "More than one GPU" section; treat as less-verified
  than the primary single-card path documented in `docs/gotchas.md`

**Request-slot vs. context-length tradeoff is hard, not soft:**
- Current capacity: e.g. `SPEC=dflash2 DFLASH_TOKENS=15` mode: 4 slots / 56k context
  vs. the default 8 slots / 64k context (`README.md:117`)
- Limit: recurrent-state page sizing (gotcha #33) and decode-graph budget (gotcha
  #38) mean this isn't tunable smoothly — verify-block size changes hit fixed
  CUDA-graph capture boundaries
- Scaling path: pick `DFLASH_TOKENS`/`CTX` mode based on workload shape per the
  README guidance; there is no dynamic/adaptive slot allocation

## Dependencies at Risk

**vLLM itself (pinned, heavily patched):**
- Risk: the entire repo's value proposition depends on ~30 patches applying
  cleanly against a specific vLLM version (currently 0.28.0, per README); upstream
  vLLM changes to attention backend internals, model runner internals, or
  torch.compile caching can break any patch silently
- Impact: a vLLM upgrade without full patch re-validation risks the exact failure
  mode gotcha #1 describes — the server runs and benchmarks look fine, but output
  quality is silently wrong
- Migration plan: `patches/check_vllm_series.sh` and `patches/_check_applied.py`
  exist for this; `verify.sh` is the full gate; always run both before trusting a
  vLLM version bump

**Third-party DFlash2 / draft model artifacts:**
- Risk: `prepare/fetch_dflash2.py` downloads a 1.2 GB third-party artifact; the
  `drafter/` directory's training/export scripts
  (`drafter/train_mtp.py`, `drafter/export_mtp.py`, `drafter/quant_dflash2.py`)
  imply these artifacts are periodically regenerated and their quality is coupled
  to the specific model checkpoint (`Qwen3.8-27B-W4A16-AutoRound`)
- Impact: a model checkpoint update likely requires re-deriving the draft
  vocabulary and re-training/re-quantizing the drafter (see gotcha #12: "the draft
  vocabulary is the single-user ceiling," coverage must be measured over the
  model's own outputs, not generic web text)
- Migration plan: re-run the `drafter/` pipeline (`gen_data.py` →
  `build_draft_vocab.py` (in `prepare/`) → `train_mtp.py`/`quant_dflash2.py`) after
  any base-model swap; do not assume an old drafter transfers

## Test Coverage Gaps

**No CI-gated unit test suite beyond `verify.sh` and ad hoc scripts:**
- What's not tested: there is no `pytest`/CI config found; the only test-shaped
  files are `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`,
  `bench/mq3d_scratch_pool_test.py`, and `bench/mq3d_capacity_property.py`, run
  manually rather than via a discovered CI test runner
- Files: `bench/*.py`, `verify.sh`
- Risk: correctness regressions in the attention/quantization kernels (the most
  fragile code in the repo, see Fragile Areas above) rely on `verify.sh` plus
  manual benchmark/quality runs rather than fast, isolated unit tests
- Priority: High for `kvarn_attn.py` and the Triton kernels in
  `kvarn/files/vllm/v1/attention/ops/`; changes there should never be trusted on
  `verify.sh` output alone given how many gotchas describe silent correctness
  failures at good throughput

**Env-var interaction matrix untested:**
- What's not tested: the many documented env-var interaction gotchas (#5, #19,
  #48, #52, etc.) were each discovered by hitting them in practice, not by a test
  that enumerates valid/invalid combinations
- Files: none — this is an absence
- Risk: a new contributor combining two previously-untested env vars can hit an
  already-known-class failure (silent bad output, assert-at-startup, or OOM) with
  no test catching it before a real deploy
- Priority: Medium — mitigated in practice by `docs/gotchas.md` being unusually
  thorough, but that log is discovered by reading, not enforced by tooling

---

*Concerns audit: 2026-09-05*
