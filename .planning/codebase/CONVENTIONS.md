# Coding Conventions

**Analysis Date:** 2026-09-05

## Project Nature

This is not an application codebase — it is an operations/tuning repo for running Qwen3.8-27B on a single RTX 3090 via a patched vLLM install. Code is organized as standalone scripts, not an importable package:

- `bench/` — GPU benchmark and correctness scripts (`bench/labd_bench.py`, `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py`)
- `drafter/` — MTP/DFlash2 draft-model training and export (`drafter/train_mtp.py`, `drafter/capture.py`)
- `prepare/` — one-shot quantization/vocab preparation scripts (`prepare/quant_lm_head.py`, `prepare/build_draft_vocab.py`)
- `patches/` — unified diffs against vLLM's installed site-packages, plus `patches/_check_applied.py` to verify they landed
- `single-user/`, `batch/` — deployment scripts and systemd units
- `verify.sh` — the closest thing to a test suite; a bash script that PASS/WARN/FAILs the whole install

There is no `src/` layer, no shared internal library, and no package `__init__.py` structure. Each script is self-contained and invoked directly with `venv/bin/python <script>.py`.

## Naming Patterns

**Files:**
- `snake_case.py` throughout, named after what they do: `residue_sweep.py`, `spec_attn_ctx_scan.py`, `mq3d_layer2_oracle.py`
- Prefixes group related tooling: `mq3d_*` (Layer-2 oracle/capacity tests), `labd_*` (long-context lookup-augmented drafting), `spec_*` (speculative decoding)
- Patch files are named `<feature>-<detail>.patch` (e.g. `patches/dflash2-lookup-drafting.patch`, `patches/marlin-int8-negative-scales.patch`) — filename doubles as a changelog entry

**Functions:**
- `snake_case`, short and verb-first: `ref_lookup`, `run_case`, `superseded_by` (in `verify.sh`'s bash equivalent)
- `main()` is the standard entrypoint function in scripts meant to be run directly (`bench/demo_render.py:317`, `bench/test_lookup_kernels.py:48`, `bench/mq3d_capacity_property.py:43`)

**Variables:**
- Short, often uppercase for script-level "constants" derived from argv or env: `KEY`, `BASE`, `TAG`, `CORPUS`, `CTX`, `MAXTOK` (`bench/labd_bench.py:20-27`)
- Domain abbreviations are used consistently without redefinition inline (`kv_lens`, `q_len`, `nb`, `bt` for block table) — familiarity with vLLM internals is assumed

**Types:**
- No custom classes in most scripts; PyTorch tensors and plain dicts/lists are the primary data structures. Type hints are rare and only appear as inline string-quoted hints in a few files (e.g. `patches/_check_applied.py:16` — `per_file: "dict[str, list[str]]" = {}`)

## Code Style

**Formatting:**
- No formatter config found (no `.prettierrc`, no `pyproject.toml`/`black`/`ruff` config). Style is manually consistent: 4-space indents, double-quoted strings mixed with single-quoted, lines commonly 90-110 chars (denser than PEP8's 79).
- Dense one-liners are common and intentional, including multiple statements on one line separated by `;` (`bench/tune_gdn.py:41`: `except Exception as e: print(f"BV={BV} warps={W}: FAIL {str(e)[:80]}")`)

**Linting:**
- No linter config present (no `.eslintrc`, `ruff.toml`, `.flake8`). `# noqa` comments appear ad hoc to suppress warnings the author is aware of (`bench/api_smoke.py:41`, import lines with runtime `sys.path` mutation in `bench/test_lookup_kernels.py`)

## Module-Level Documentation

Every script opens with a triple-quoted module docstring that explains **why** the script exists, not just what it does — including caveats, gotchas, and exact invocation commands. This is the single most consistent convention in the repo. Example structure (`bench/labd_bench.py:1-19`):

```python
"""What lookup-augmented drafting is for: <problem statement>.

<methodology / what's measured>

<gotcha: e.g. corpus freezing behavior, so numbers stay comparable>

  venv/bin/python bench/labd_bench.py <tag> [--ctx 20000] [--max-tokens 512]
                                      [--tasks copy,code,edit,quote,summary,qa]
"""
```

When adding a new script, follow this pattern:
1. First line: one-sentence purpose statement
2. One or two paragraphs of context/rationale, including any known sharp edges
3. Exact copy-pasteable run command(s), indented, showing all flags

## Argument Parsing

Two parsing styles coexist, chosen by script complexity:

**Ad hoc positional/flag parsing** (most bench scripts) — a small `arg(name, default)` helper that scans `sys.argv` directly, no `argparse`:
```python
def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default

CORPUS = os.path.expanduser(arg("--corpus", "~/bench/labd_corpus.txt"))
CTX = int(arg("--ctx", 20000))
```
(`bench/labd_bench.py:23-27`)

**`argparse`** — used only in the more complex training/tuning scripts with many flags and `--help` value (`drafter/train_mtp.py`, `bench/mq3d_capacity_property.py`). Prefer this once a script has more than ~5 flags or needs `--help` text; otherwise use the `arg()` helper pattern for consistency with the rest of `bench/`.

## Error Handling

**Pattern:** fail loud for setup/environment problems, fail soft (catch-and-continue or catch-and-log) inside sweeps/loops that shouldn't abort a whole run.

- Bare `except OSError:` guards file/corpus-loading code where a missing file means "generate it fresh" rather than "crash" (`bench/labd_bench.py`, `bench/quality_battery.py:33`, `bench/conc_ladder.py:60`, `bench/needle_test.py:25`, `bench/make_long_corpus.py:42`, `bench/seat_ttft.py:28`) — this is the dominant except pattern in the repo.
- Bare `except Exception as e:` (or bare `except Exception:`) appears inside per-iteration sweep loops so one bad config doesn't kill the whole sweep, with the exception message truncated and printed inline: `except Exception as e: print(f"BV={BV} warps={W}: FAIL {str(e)[:80]}")` (`bench/tune_gdn.py:41`)
- `raise SystemExit("<message>")` is the idiom for a hard, user-facing precondition failure in a bench script (`bench/labd_accept.py:193`), not `raise RuntimeError` or custom exceptions. Use this for "the server isn't configured the way this benchmark needs" type failures.
- No custom exception classes anywhere in the repo — stick to stdlib exceptions and `SystemExit`.
- `verify.sh` uses a three-state result vocabulary (`PASS`/`WARN`/`FAIL`) with a running `FAILS` counter and explicit exit code, rather than Python tracebacks — this is the pattern for anything that checks "is the install correct."

## Logging

**Framework:** `print()` — no `logging` module usage found anywhere in `bench/`, `drafter/`, or `prepare/` (`grep -rln "^import logging\|logger ="` returns nothing outside vLLM's own patched files).

**Patterns:**
- Structured status lines use short tags: `ok()`, `warn()`, `fail()` shell functions in `verify.sh` printing `"  PASS  %s\n"` / `"  WARN  %s\n"` / `"  FAIL  %s\n"`.
- Python scripts print progress and results directly to stdout with f-strings; results destined for later analysis are written as JSONL (`bench/mq3d_layer2_verdicts.jsonl`) rather than logged.
- Comments embedded in code explain *why*, extensively — e.g. `patches/_check_applied.py` and `verify.sh` both carry paragraph-length comments justifying a specific check's existence, referencing GitHub issue numbers (`#35`, `#43`, `#67`) as historical context. Follow this: when a check exists because of a subtle prior failure, say so and cite the issue.

## Comments

**When to comment:** liberally, and prescriptively — explaining edge cases, prior bugs, and why a check is shaped the way it is (not just what the next line does). Comments frequently reference issue numbers for traceability, e.g. `verify.sh`: "PR #43: a patch that failed every hunk still cleared an 80% tree-wide threshold."

**Docstrings:** module-level docstrings are mandatory (see above); function-level docstrings are used sparingly, only on non-obvious functions (`patches/_check_applied.py:1-13` has the module docstring; individual helper functions mostly rely on their name + a one-line comment instead of a full docstring).

## Function Design

**Size:** functions are kept small and single-purpose (parse args, build tensors, run one comparison), typically 10-40 lines. `main()` at the bottom orchestrates by calling these.

**Parameters:** positional args for required values, explicit defaults for tunables (e.g. `run_case(seq, k, nmin, nmax, device="cuda")` in `bench/test_lookup_kernels.py:32`).

**Return values:** plain tuples/lists rather than dataclasses or named tuples — e.g. `(tokens, match_len, valid)` returned directly as a 3-tuple (`bench/test_lookup_kernels.py:17`).

## Module Design

**Exports:** none — nothing in this repo is imported as a library by another first-party module. Every file is a standalone entrypoint or a patch. When adding new tooling, keep this pattern: a self-contained script over a shared importable module, unless three or more scripts would otherwise duplicate the same non-trivial logic.

**Shared code:** the closest thing to shared library code is vLLM itself (patched in place) and small copy-pasted helpers (like the `arg()` parser) repeated per-script rather than factored into a shared module — this is a deliberate simplicity trade-off in a repo where every script is meant to be run in isolation, possibly copied elsewhere.

---

*Convention analysis: 2026-09-05*
