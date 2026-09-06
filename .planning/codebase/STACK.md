# Technology Stack

**Analysis Date:** 2026-09-05

## Languages

**Primary:**
- Python 3.12 - vLLM runtime, all launch scripts, benchmarking (`bench/`), model preparation (`prepare/`), drafter training (`drafter/`)

**Secondary:**
- Bash - orchestration scripts: `docker/entrypoint.sh`, `docker/prepare.sh`, `single-user/start_qwen.sh`, `batch/start_qwen.sh`, `verify.sh`, `kvarn/install.sh`
- Patch/diff (unified diffs) - `patches/*.patch` applied on top of the pinned vLLM source tree

## Runtime

**Environment:**
- Python 3.12 (venv at `/app/venv` in the container, or a local venv per README "Setup")
- CUDA 13.0 (base image `nvidia/cuda:13.0.1-base-ubuntu24.04`), requires host NVIDIA driver ≥ 580
- Single NVIDIA GPU target: RTX 3090 (24 GB, sm86); tuned to run at a 250 W host power limit

**Package Manager:**
- pip, inside a Python venv
- Lockfile: `docker/requirements.txt` is a hard pin (not a lockfile format, but fully version-pinned) for the Docker build; the venv "Setup" path in README follows the same pins

## Frameworks

**Core:**
- vLLM 0.28.0 - inference/serving engine, OpenAI-compatible API server (`vllm serve` invoked from `single-user/start_qwen.sh` / `batch/start_qwen.sh`)
- PyTorch 2.13 (pulled in transitively by vLLM 0.28.0) / CUDA 13.0 / Triton 3.7.1 - tensor runtime and JIT kernels
- Transformers 5.15.0, Tokenizers 0.22.2 - model loading/tokenization
- compressed-tensors 0.17.0 - quantized weight format support (W4A16/int4/int8 checkpoints)
- FlashInfer (via `flashinfer-python` / `flashinfer-cubin`) - fp8 KV-cache attention kernels, JIT-compiled with nvcc on first use
- KVarN (`kvarn/`, installed via `kvarn/install.sh`, patches from `kvarn/*.patch`) - custom 4-bit-key/2-bit-value KV cache for long context (200k+ tokens)

**Testing/Verification:**
- `verify.sh` - custom bash verification harness (not a test framework); gates the Docker build (`--install` mode) and every container start (`--no-server` mode), and can hit a live server (full mode) via curl
- `patches/_check_applied.py` + `.github/workflows/patch-integrity.yml` - CI check that every patch in `patches/` still applies cleanly against the pinned vLLM source (checked out at tag `v0.28.0`)
- `bench/test_lookup_kernels.py`, `bench/test_spec_decode_attn.py` - standalone Python scripts exercising custom CUDA kernel patches (no pytest harness detected)

**Build/Dev:**
- Docker (multi-stage-less single `Dockerfile`) + `docker-compose.yml` with profiles (`single`, `batch`, `prepare`)
- GitHub Actions (`.github/workflows/docker-image.yml`, `.github/workflows/patch-integrity.yml`) - CI build/push and patch-integrity gate
- `ninja` 1.13.0 - build accelerator for JIT-compiled kernels (FlashInfer/Triton)

## Key Dependencies

**Critical:**
- `vllm==0.28.0` - the entire serving stack; resolves compatible torch/cu130/Triton/FlashInfer versions
- `transformers==5.15.0`, `tokenizers==0.22.2` - model architecture and tokenization compatible with Qwen3.8-27B
- `huggingface_hub==1.27.0` + `hf_transfer==0.1.9` - model/weights download (`prepare/*.py`, `drafter/collect_prompts.py`); `HF_HUB_ENABLE_HF_TRANSFER=1` set in the image
- `compressed-tensors==0.17.0` - quantized checkpoint loading (W4A16, int4/int8 activation paths)

**Infrastructure:**
- `pandas==3.0.5` - required only so `vllm bench serve`'s dataset loader doesn't hard-fail (see comment in `docker/requirements.txt`); intentionally NOT the full `vllm[bench]` extra to avoid reinstalling vLLM and reverting the patch stack
- `ninja==1.13.0` - JIT kernel compilation support

## Configuration

**Environment:**
- All runtime knobs are environment variables, read by `single-user/start_qwen.sh` / `batch/start_qwen.sh`: `CTX`, `KV`, `MAX_LEN`, `MAX_SEQS`, `GPU_UTIL`, `VISION`, `SPEC` / `SPEC_ATTN`, `DRAFT_TOKENS` / `DFLASH_TOKENS`, `INT8_ACT`, `INT8_LAYERS`, `PREFIX_CACHE`, `EXTRA_ARGS`, `VLLM_API_KEY`, `VLLM_WSL2_ENABLE_PIN_MEMORY`, `VLLM_OFFLOAD_KEEP_SHM`, `PREPARE`, `VERIFY`
- `.env` file at repo root (gitignored) is read directly by `docker-compose.yml` (`env_file:`) and mirrors the same variable names used by the bash scripts
- API key alternative: `api_key.txt` in repo root (`single-user/start_qwen.sh:666`, `batch/start_qwen.sh:178`, `verify.sh:160-173`); if neither is set the server has no auth and warns via `verify.sh`
- `HOME=/cache` in the container - redirects `torch.compile` cache, Triton cache, FlashInfer JIT cache, and the HF hub cache into the persisted `/cache` volume

**Build:**
- `Dockerfile` - defines the frozen stack, applies `patches/*.patch` to the installed vLLM package at build time, runs `kvarn/install.sh` and `verify.sh --install` as build gates
- `docker-compose.yml` - defines `prepare` / `single` / `batch` services, GPU device reservation, healthcheck (`/health`, 900s start period), named volumes (`qwen-cache`, bind-mounted `models/`)
- `.dockerignore`, `.gitattributes`, `.gitignore` - standard repo hygiene; no linter/formatter config files (no `.eslintrc`, `pyproject.toml`, `ruff.toml`, etc. detected)

## Platform Requirements

**Development:**
- Linux or WSL2 host with an NVIDIA GPU (sm86-class, e.g. RTX 3090) and driver supporting CUDA 13
- Docker + NVIDIA Container Toolkit for the containerized path, or a local Python 3.12 venv for the "Setup" path in README
- `docker/gotchas.md` / `docs/wsl2-4090.md` document WSL2-specific caveats (UVA pinning, free-memory gate)

**Production:**
- Single-GPU deployment (24 GB VRAM class card), served on port 18020, OpenAI-compatible HTTP API
- Prebuilt image published to `ghcr.io/syv-ai/qwen38-27b-rtx3090` on every push to `main` (tag `latest`) plus immutable `sha-<7>` tags, rebuilt weekly via cron for base-image security fixes
- No orchestration platform (Kubernetes, etc.) detected — single-container, single-GPU deployment model only

---

*Stack analysis: 2026-09-05*
