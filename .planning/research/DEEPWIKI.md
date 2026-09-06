# DeepWiki Research: syv-ai/qwen38-27b-rtx3090

Long-term single-machine deployment notes, extracted from DeepWiki (deepwiki.com auto-generated
docs, so treat as MEDIUM confidence — cross-check against actual repo source before relying on
specifics like exact unit-file directives).

## Compose Profiles

Three `docker-compose` profiles gate the GPU lifecycle so only one workload touches the card at
a time:

| Profile | Entry script | Purpose |
|---|---|---|
| `prepare` | `docker/prepare.sh` | Idempotent model download + CPU-based requantization |
| `single` | `single-user/start_qwen.sh` | Low-latency serving via MTP or DFlash2 speculative decoding |
| `batch` | `batch/start_qwen.sh` | High-throughput serving with INT8 activation quantization |

Usage:
```bash
docker-compose --profile prepare up
docker-compose --profile single up
docker-compose --profile batch up
```

**Volumes:**
- `/app/models` — base W4A16 model + generated artifacts (INT8 `lm_head`, `embed_tokens`, MTP
  modules). Persisting this is what makes `prepare` skip already-done work.
- `/cache` (mapped to HOME) — torch.compile / JIT compilation cache. Persisting cuts warm start
  from ~3 min to ~1 min.

**Entrypoint / healthcheck:** `docker/entrypoint.sh` runs `verify.sh --no-server` before handing
off to the serving command, checking: vLLM patches applied, model requantization complete (looks
for markers like `lm_head.weight_packed`), and KVarN backend registered. `verify.sh` (without
`--no-server`) can also probe the running server's `/health` endpoint.

**Env vars surfaced at the compose level:**
- `GPU_UTIL` — memory-utilization fraction passed to vLLM. Default `0.972` (batch) / `0.93`
  (single-user recommended on WSL2, see below).
- `EXTRA_ARGS` — free-form extra CLI args, notably used to pin `--kv-cache-memory` to an explicit
  byte value instead of a utilization percentage.
- `PYTORCH_CUDA_ALLOC_CONF` — allocator behavior, see WSL2 notes.

## Mode Switching (single ↔ batch)

DeepWiki does **not** document an explicit "switch modes" procedure or script. Inferred from the
profile design: stop the currently-running profile's container, then bring up the other profile.
Since both modes are mutually exclusive consumers of the whole GPU, they are not meant to run
concurrently. The `prepare` volume (`/app/models`) is shared and reused by both, so switching
does not require re-running `prepare`.

Key per-mode env vars (for a `.env` used at switch time):

**Single-user (`single-user/start_qwen.sh`):**
| Var | Default | Purpose |
|---|---|---|
| `SPEC` | `mtp` | Speculative engine: `mtp` or `dflash2` |
| `CTX` | `fast` | Context backend: `fast` (64k), `long` (150k, fp8 KV, ~10% slower), `huge` (200k+, KVarN 4/2-bit, decode-tax scales with context) |
| `LOOKUP` | `1` | Enables Lookup-Augmented Drafting for DFlash2 |
| `DFLASH_TOKENS` | `7` | Verify block size (set `15` for document-reproduction workloads) |
| `GPU_UTIL` | `0.93` | Lower than batch's default to leave scratchpad headroom for MTP |
| `PREFIX_CACHE` | `1` | Hybrid prefix caching |

**Batch (`batch/start_qwen.sh`):**
| Var | Default | Purpose |
|---|---|---|
| `MAX_SEQS` | `64` | Concurrent sequence cap, tuned to fp16 recurrent-state capacity |
| `KV` | `fp8` | KV cache format; `kvarn` for 4/2-bit compression |
| `INT8_ACT` | `int8` | INT8 activations on MLP linears (~35% throughput gain) |
| `PREFIX_CACHE` | `0` | Set `1` for API workloads sharing system prompts |
| `GPU_UTIL` | `0.972` | Lower to `0.93` when using `kvarn` mode |

Batch mode overtakes single-user's speculative decoding in aggregate throughput at roughly 8
concurrent requests (C8) and above — a reasonable trigger for deciding which profile to run for a
given workload.

## Systemd / Boot Autostart

There **are** systemd unit files referenced in the wiki — this contradicts a naive "no systemd
support" assumption, but confidence here is MEDIUM/LOW since DeepWiki couldn't produce full unit
contents (likely paraphrased from source comments, not a verbatim dump):

- `single-user/qwen-serving.service` — starts single-user mode via `systemctl start
  qwen-serving`. Includes an `ExecStartPre` GPU-cleanup check that ensures prior VRAM allocations
  are released before vLLM profiles memory.
- A comparable (unnamed in the wiki) systemd service exists for batch mode, with an
  `ExecStartPre` step that runs `nvidia-smi` and refuses to start unless GPU usage is < 1000 MB
  (partial VRAM occupancy otherwise forces a permanently smaller KV pool → ~25% throughput loss).

**Not confirmed by DeepWiki:**
- Exact unit file contents (`ExecStart` command line, `Restart=` policy, `User=`, `WantedBy=`
  target).
- Whether `systemctl enable` (boot autostart) is documented/recommended anywhere.
- Whether the systemd path is meant to replace docker-compose in production, or is an
  alternative/legacy path — the Docker Deployment page itself states plainly that it "does not
  address systemd integration or autostart mechanisms," while the Single-User and Batch mode
  pages independently reference the `.service` files. Treat the two docker-compose and systemd
  deployment paths as parallel/alternative, not composable — the wiki gives no indication they're
  meant to be layered (e.g. systemd unit wrapping `docker-compose up`).

**Action for verification:** read `single-user/qwen-serving.service` and the batch equivalent
directly from the repo source before writing your own unit/timer, since DeepWiki could not
surface exact directives.

## WSL2 Notes

- **Memory profiling failure:** vLLM's free-memory profiling can fail on WSL2 due to `dxgkrnl`
  driver overhead. Mitigation: set `GPU_UTIL=0.93` (down from the Linux-native ~0.972) in `.env`.
- **Allocator crashes during weight repacking:** if you see "device not ready" errors during INT8
  weight repacking, set `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` for certain WSL2
  driver versions. (Note: this is the *opposite* of the general non-WSL2 recommendation below —
  WSL2 is called out as an exception.)
- **Cold-start profiling instability:** WSL2's overhead makes the profiled KV pool size sensitive
  to run-to-run variance. Recommended production pattern: record the specific `--kv-cache-memory`
  byte value from a clean cold start and pin it via `EXTRA_ARGS` rather than relying on
  `gpu-memory-utilization` percentage-based profiling on every restart.

## Pitfalls (long-running / frequent-restart relevant)

**Memory / restart-specific:**
- **Dirty-GPU restart penalty:** restarting before VRAM from the previous process is fully
  released can cause vLLM to profile up to ~40% less available memory than actually free. This is
  exactly what the systemd `ExecStartPre` GPU-cleanup/VRAM checks exist to prevent — worth
  replicating even if not using the provided systemd units.
  - **Correction/nuance in source:** the docker-deployment/gotchas pages give slightly different
    numbers for the mandatory-`expandable_segments` threshold (Docker page implies
    `expandable_segments:False` is the WSL2-only fix for allocation crashes; the general gotchas
    page says `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True` is *mandatory* on non-WSL2 when
    `gpu-memory-utilization` exceeds ~0.975, since GDN prefill kernels need transient workspace).
    Read both settings as: **default to `True`, except flip to `False` specifically on WSL2 if
    you hit "device not ready" errors during weight repacking.**
- **Cold `torch.compile` cache inflates first-run profiling:** the very first start on a cold
  compile cache triggers Inductor autotuning during the memory-profiling pass itself, inflating
  the profiled activation peak and shrinking the resulting KV pool. Standard mitigation: discard/
  ignore the first post-restart run's sizing and let the persistent `/cache` volume warm up;
  consider a throwaway warm-up request after every restart before trusting KV pool sizing.
- **V2 model runner CUDA graph accounting gap:** the V2 runner doesn't account for its own ~1.2
  GiB of CUDA graphs when sizing the KV pool from a utilization percentage. Prefer
  `--kv-cache-memory <explicit bytes>` over `--gpu-memory-utilization <fraction>` for a stable,
  reproducible KV pool size across restarts — directly relevant to a long-lived, repeatedly
  restarted single-machine deployment.
- **Compile-cache/env-var mismatch:** changing `INT8_LAYERS` between runs without clearing the
  torch.compile cache can produce `KeyError: 'input_global_scale'` crashes — the compile cache
  keys don't invalidate on this env var change. If you ever change `INT8_LAYERS`, manually clear
  the `/cache` volume's compile artifacts first.
- **Scratchpad headroom by mode:** MTP speculative decoding in single-user mode needs
  `gpu-memory-utilization` ≤ 0.93 (not higher) to leave scratchpad room; INT8-activation batch
  mode needs ≤ 0.95 for Marlin kernel scratchpads. These aren't just "more is better" — set the
  fraction lower deliberately per mode rather than maximizing it.

**Startup timing:**
- First-ever launch (post-`prepare`) needs up to 15 minutes for `torch.compile`, CUDA graph
  capture, and FlashInfer JIT compilation. This is a one-time cost as long as the `/cache` volume
  persists across restarts — do not treat a 15-minute-silent boot as a hang if `/cache` was wiped
  or is new.

**Prepare/idempotency:**
- The `prepare` profile/`docker/prepare.sh` is explicitly documented as idempotent — safe to
  re-run; it downloads + requantizes into `/app/models` and `verify.sh` checks for completion
  markers (e.g. `lm_head.weight_packed`) to decide what to skip. DeepWiki could **not** produce
  the underlying per-script idempotency mechanism (no confirmation of lock files / checkpoints in
  the six sub-scripts: `quant_lm_head.py`, `quant_embed.py`, `quant_mtp.py`,
  `build_draft_vocab.py`, `fetch_fast_variant.py`, `fetch_dflash2.py`). If you need to know
  precisely what happens on a partial/interrupted prepare run, read those scripts directly rather
  than trusting this summary.

**Path-based footguns (relevant if you ever rename/move the model directory during long-term
maintenance):**
- vLLM infers the speculative method from the model *path string*. If "dflash" appears anywhere
  in the directory path, vLLM tries to load an `EAGLEConfig` regardless of what's actually there —
  can crash if the model is actually MTP-based. Keep model directory names stable/deliberate.

**Other operational quick hits (from the gotchas quick-reference table):**
| Issue | Mitigation |
|---|---|
| JIT warm-up reads low (first run after restart) | Discard first run's profiling result |
| Large prefill chunks shrink KV pool | Keep `--max-num-batched-tokens` at 2048 |
| `prompt_logprobs` OOM | Reduce `GPU_UTIL` to 0.93 during quality-check runs |
| Unused vision weights (2.7 GB wasted) | Use `--language-model-only` flag |

**Long-context speculative decoding caveat:** DFlash2's drafter only attends to a 2,048-token
window; on very long contexts (36k+ tokens) MTP outperforms it due to lower acceptance rate and
extra prefill overhead. If you run `CTX=huge` for long-lived long-context workloads, prefer
`SPEC=mtp` over `dflash2`.

## Sources

- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/1.1-getting-started:-installation-and-setup
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/1.2-docker-deployment
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/2-model-preparation-pipeline
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/3.1-batch-mode
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/3.2-single-user-mode
- https://deepwiki.com/syv-ai/qwen38-27b-rtx3090/9-gotchas-and-operational-notes
- https://deepwiki.com/search?q=systemd+qwen-serving+repo:syv-ai/qwen38-27b-rtx3090 (no useful
  results — DeepWiki's search endpoint returned an empty results page)
