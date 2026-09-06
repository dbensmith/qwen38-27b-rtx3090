# Testing Patterns

**Analysis Date:** 2026-09-05

## Test Framework

**Runner:**
- None. No pytest, unittest, or any test framework is used anywhere in the repo.
- No `pytest.ini`, `setup.cfg`, `pyproject.toml`, or `conftest.py` exists.
- Tests are standalone Python scripts under `bench/` that are run directly with the vLLM venv's interpreter and communicate pass/fail via `print()` output and process exit codes (or a bare `assert`).

**Assertion Library:**
- Plain Python `assert` statements (see `bench/mq3d_scratch_pool_test.py`). A failing assert raises `AssertionError` and the script crashes non-zero.
- Some scripts instead accumulate a `fails` counter, print per-case `OK`/`FAIL` lines, and `sys.exit(1 if fails else 0)` at the end (see `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`).

**Run Commands:**
```bash
# GPU-required correctness tests, run inside the vLLM venv:
venv/bin/python bench/test_lookup_kernels.py        # ~200MB free GPU needed
venv/bin/python bench/test_spec_decode_attn.py      # correctness + microbench vs FlashAttention-2

# CPU-only, no GPU, runs inside the built image:
/app/venv/bin/python bench/mq3d_scratch_pool_test.py
python bench/mq3d_capacity_property.py              # pure arithmetic, no torch/engine

# Full install/environment verification (bash, not Python):
bash verify.sh                 # everything: venv, vLLM version, patches, model requant, running server
bash verify.sh --no-server     # skip live-server checks
bash verify.sh --install       # only install-time checks (what the Docker build runs), no GPU/model/server

# Live-server probes (require a running vLLM server, see single-user/start_qwen.sh):
python bench/needle_test.py [target_tokens] [depth]   # needle-in-haystack retrieval
python bench/quality_battery.py                       # GSM8K-style quality lane
python bench/api_smoke.py
```

There is no single "run all tests" command. Each script is invoked individually depending on what changed (kernel patch, scratch-pool patch, install, or live-serving behavior).

## Test File Organization

**Location:**
- All test-like scripts live flat in `bench/`, alongside benchmarking, calibration, and demo-capture scripts (`bench/labd_bench.py`, `bench/act_calib.py`, `bench/demo_render.py`, etc.). There is no separate `tests/` directory.

**Naming:**
- No single fixed convention. Observed patterns:
  - `test_<subject>.py` — `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`
  - `<subject>_test.py` — `bench/needle_test.py`, `bench/mq3d_scratch_pool_test.py`
  - `<subject>_property.py` — `bench/mq3d_capacity_property.py` (property-based / invariant check, no framework)
  - `<subject>_oracle.py`, `<subject>_verdicts.jsonl` — `bench/mq3d_layer2_oracle.py` produces verdict logs rather than pass/fail
- New correctness scripts for a patch/kernel should follow the `test_<subject>.py` or `<subject>_test.py` pattern and live in `bench/`.

**Structure:**
```
bench/
├── test_lookup_kernels.py       # GPU kernel correctness vs. pure-Python reference
├── test_spec_decode_attn.py     # GPU kernel correctness + timing vs. FlashAttention-2
├── mq3d_scratch_pool_test.py    # CPU-only unit test of a pooling/allocator data structure
├── mq3d_capacity_property.py    # Pure-Python property/invariant check, no GPU or torch
├── needle_test.py               # Live HTTP probe against a running server
├── quality_battery.py           # Live HTTP quality/accuracy battery
├── api_smoke.py                 # Live HTTP smoke test
└── ...                          # benchmarking/calibration/demo scripts (not tests)
verify.sh                        # bash: environment/install/patch/server verification harness
```

## Test Structure

**Suite Organization:**
Each script is a flat `main()` (or top-level script body) that runs a sequence of hand-picked cases, not a class/method hierarchy. Example from `bench/test_lookup_kernels.py`:

```python
def main():
    torch.manual_seed(0)
    fails = 0
    cases = [...]  # hand-built + randomized inputs
    for k, nmin, nmax in ((7, 4, 32), (15, 4, 32), ...):
        for ci, seq in enumerate(cases):
            got = run_case(seq, k, nmin, nmax)
            want = ref_lookup(seq, k, nmin, nmax)
            ok = got[1] == want[1] and got[2] == want[2] and got[0][:v] == want[0][:v]
            if not ok:
                fails += 1
                print(f"MISMATCH k={k} nmin={nmin} nmax={nmax} case={ci} len={len(seq)}")
    print(f"suffix_lookup: {'OK' if not fails else str(fails) + ' FAILURES'}")
    ...
    return 1 if fails else 0

if __name__ == "__main__":
    sys.exit(main())
```

**Patterns:**
- Setup: `torch.manual_seed(0)` for reproducible randomized cases; GPU tensors are built directly in the test with `device="cuda"`.
- No teardown/fixtures — each script is a single process, GPU memory is freed on exit.
- Assertion style is either (a) accumulate a `fails` counter and print `MISMATCH`/`FAIL` lines with full diagnostic context (expected vs. got), or (b) hard `assert` with a descriptive message as the second argument, e.g. `assert a.origin == "model load" and a.adopters == 0 and len(pool) == 1, "load allocates, pooled"` (`bench/mq3d_scratch_pool_test.py:22`).
- Exit code convention: `sys.exit(1 if fails else 0)` when using the counter style; a bare `assert` crash is itself the failure signal for the assert style.

## Mocking

**Framework:** None. No `unittest.mock`, no mocking library.

**Patterns:**
Rather than mocking, tests build minimal real GPU/CPU tensors and compare against a plain-Python or plain-PyTorch reference implementation computed independently in the same script:

```python
# bench/test_lookup_kernels.py
def ref_lookup(seq, k, nmin, nmax):
    """(tokens, match_len, valid) computed in pure Python, no CUDA kernel involved."""
    ...

def run_case(seq, k, nmin, nmax, device="cuda"):
    # calls the actual CUDA-backed suffix_lookup / fuse_draft kernels
    ...
```

```python
# bench/test_spec_decode_attn.py
def ref(q, kc, vc, bt, kv_lens, q_len):
    # float32 einsum reference attention, compared against both the custom
    # kernel under test AND vLLM's own flash_attn_varlen_func
    ...
```

**What to Mock:** Nothing — external dependencies (`vllm`, `torch`, CUDA) are exercised for real. Live-server tests (`needle_test.py`, `api_smoke.py`, `quality_battery.py`) hit an actual running vLLM server over HTTP rather than mocking the API.

**What NOT to Mock:** GPU kernels, the vLLM engine, and the HTTP server are always run for real — correctness is established by comparing the real code path's output against an independently-computed reference value or an existing trusted implementation (e.g. FlashAttention-2), never by mocking the subject under test.

## Fixtures and Factories

**Test Data:**
Inline generator functions build synthetic input tensors per test file rather than shared fixtures:

```python
# bench/test_spec_decode_attn.py
def make(kv_lens, q_len, num_blocks=None):
    B = len(kv_lens)
    kc = torch.randn(num_blocks, BS, Hkv, D, device=dev, dtype=torch.bfloat16)
    ...
    return q, kc, vc, bt, cu, seqused
```

```python
# bench/mq3d_scratch_pool_test.py
def plan(cap, heads=4, hd=64):
    row = 4 * (heads * m.NUM_PAR_SOFTMAX_SEGMENTS * hd + 2 * heads * m.NUM_PAR_SOFTMAX_SEGMENTS)
    return P(num_heads_q=heads, num_heads_kv=2, headdim_padded=hd, seq_threshold_3D=32,
             max_query_len_3d=16, capacity=cap, row_bytes=row, max_num_batched_tokens=2048, max_num_seqs=4)
```

**Location:** No shared fixtures directory. Each test script owns its own data-generation helpers at module scope. `bench/prompts_real.jsonl` is a shared corpus of real prompts used by multiple live-server probes (e.g. `quality_battery.py`).

## Coverage

**Requirements:** None enforced. No coverage tool (`coverage.py`, `pytest-cov`) is configured or referenced anywhere.

**View Coverage:**
```bash
# Not applicable — no coverage tooling in this repo.
```

## Test Types

**Unit Tests:**
- Narrow, deterministic checks of a single data structure or pure function against a hand-computed or algebraic reference: `bench/mq3d_scratch_pool_test.py` (scratch-pool sharing/eviction logic), `bench/mq3d_capacity_property.py` (capacity-derivation arithmetic invariant, includes a documented negative control at `bench/mq3d_scratch_pool_test.py:41-45`).

**Integration Tests:**
- GPU kernel correctness against a reference implementation or against another trusted library implementation, run inside the actual vLLM venv against the actual patched vLLM source tree: `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py` (also includes co-located microbenchmark timing via `bench.bench()`).

**E2E Tests:**
- Live HTTP probes against a running vLLM server (started via `single-user/start_qwen.sh`), asserting on model output content/behavior rather than internal state: `bench/needle_test.py` (needle-in-haystack long-context retrieval), `bench/quality_battery.py` (accuracy battery), `bench/api_smoke.py` (basic request smoke test), `bench/conc_ladder.py` (concurrency ladder probe).
- `verify.sh` is a bash-based environment/installation E2E check (venv, vLLM version, patch application, model requantization, GPU visibility, optional live-server reachability) — treat it as the closest thing this repo has to a CI gate; run it after any environment or patch change.

## Common Patterns

**Async Testing:**
- Not used. Live-server scripts use synchronous `urllib.request` calls with an explicit `timeout` (e.g. `bench/needle_test.py:48` `post(payload, timeout=1800)`); concurrency in `bench/conc_ladder.py` is done with `threading`, not asyncio.

**Error Testing:**
- No `pytest.raises`-style negative-path testing framework. Negative/edge cases are expressed as additional hand-picked cases in the same case list with an explicit expected outcome, e.g. `bench/test_lookup_kernels.py:118-137` iterates `(match_len, valid_n, block, prev, want)` tuples including a "match too short" case expected to yield `False`. `bench/mq3d_scratch_pool_test.py:40-45` documents a deliberate "negative control" section: the guard is turned off and the script prints whether the (undesired) sharing behavior reappears, confirming the guard is actually load-bearing rather than dead code.

## Adding a New Test

- Kernel/CUDA correctness change → new or extended `bench/test_<subject>.py`, following the reference-implementation-comparison pattern in `bench/test_lookup_kernels.py` or `bench/test_spec_decode_attn.py`; run with `venv/bin/python bench/test_<subject>.py` inside the vLLM venv on a GPU.
- Pure Python/CPU data-structure or arithmetic invariant → `bench/<subject>_test.py` or `bench/<subject>_property.py`, following `bench/mq3d_scratch_pool_test.py` / `bench/mq3d_capacity_property.py`; no GPU needed, runs with the plain interpreter.
- Behavior only observable through the live server (model quality, context length, latency) → `bench/<subject>.py` live-HTTP probe following `bench/needle_test.py` / `bench/api_smoke.py` conventions (read `VLLM_API_KEY`/`api_key.txt`, default `VLLM_API=http://127.0.0.1:18020/v1`).
- Environment/install/patch-application concern → extend `verify.sh` rather than writing a Python script.

---

*Testing analysis: 2026-09-05*
