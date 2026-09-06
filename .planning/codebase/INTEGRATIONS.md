# External Integrations

**Analysis Date:** 2026-09-05

## APIs & External Services

**Model/Weights Distribution:**
- Hugging Face Hub - source of the base model (`Qwen/Qwen3.8-27B`) and community quantized checkpoints (e.g. `leminkozey/Qwen3.8-27B-Uncensored-W4A16-AutoRound`, `philbert440/Qwen3.8-27B-Uncensored-Aggressive-W4A16-AWQ`) referenced in `README.md`
  - Client: `huggingface_hub==1.27.0` + `hf_transfer==0.1.9` (`docker/requirements.txt`)
  - Used by: `prepare/fetch_dflash2.py`, `prepare/fetch_fast_variant.py`, `prepare/fetch_thirdparty.py`, `drafter/collect_prompts.py`
  - Auth: none required for public repos; no `HF_TOKEN` handling found in scripts — gated/private models would need one added
  - Speed: `HF_HUB_ENABLE_HF_TRANSFER=1` set in the Docker image for accelerated downloads

**Container Registry:**
- GitHub Container Registry (ghcr.io) - hosts the prebuilt serving image `ghcr.io/syv-ai/qwen38-27b-rtx3090`
  - Referenced in `docker-compose.yml:30`, `README.md:74`
  - Auth: `docker/login-action@v3` in CI using `${{ secrets.GITHUB_TOKEN }}` (`.github/workflows/docker-image.yml`) — no external PAT needed, GitHub's built-in token has `packages: write` permission scoped in the workflow

**Upstream Source Dependency:**
- `vllm-project/vllm` GitHub repo, pinned at tag `v0.28.0` - checked out in CI to validate that `patches/*.patch` still apply cleanly (`.github/workflows/patch-integrity.yml`, `patches/check_vllm_series.sh`, `patches/_check_applied.py`)
  - This is a build-time/CI-time integration only, not a runtime dependency once the image is built

## Data Storage

**Databases:**
- None. No SQL/NoSQL database client, ORM, or connection string found anywhere in the repo.

**File Storage:**
- Local filesystem only:
  - `models/` directory (bind-mounted into the container per `docker-compose.yml`) holds downloaded model weights
  - `qwen-cache` named Docker volume, mounted at `/cache` (container `HOME`), holds `torch.compile` cache, Triton JIT cache, FlashInfer JIT cache, and the Hugging Face hub cache
  - No S3/GCS/Azure Blob or other cloud object storage integration found

**Caching:**
- No external cache service (Redis/Memcached). All caching is local disk (`/cache` volume) and vLLM's in-process prefix cache (`PREFIX_CACHE` env var).

## Authentication & Identity

**Auth Provider:**
- None — this is a self-hosted inference server, not a multi-tenant app with user accounts.

**API Authentication:**
- vLLM's built-in bearer-token auth for its OpenAI-compatible HTTP API
  - Token source, in priority order: `VLLM_API_KEY` env var, else `api_key.txt` in repo root (read by `single-user/start_qwen.sh:666`, `batch/start_qwen.sh:178-179`, `single-user/alternative.sh:23`)
  - If neither is set, the server runs with no auth; `verify.sh:160-173` detects this and prints a warning
  - Clients authenticate with `Authorization: Bearer <token>` (`README.md:776-777`)

## Monitoring & Observability

**Error Tracking:**
- None (no Sentry/Rollbar/Bugsnag or similar SDK found).

**Logs:**
- Container stdout/stderr only, captured via `docker compose logs` / `docker logs`; no log shipping or aggregation service configured. `docker/entrypoint.sh` and the start scripts write plain-text status/progress messages.

**Health Checks:**
- vLLM's built-in `/health` HTTP endpoint, polled by `docker-compose.yml:60` (`curl -sf http://127.0.0.1:${PORT:-18020}/health`) with a 900s start period to accommodate model load + JIT kernel compilation.

## CI/CD & Deployment

**Hosting:**
- Self-hosted / bring-your-own-GPU-box deployment (bare-metal, WSL2, or any Docker host with an NVIDIA GPU + NVIDIA Container Toolkit). No managed cloud hosting platform (AWS/GCP/Azure/Fly/Render) is integrated.

**CI Pipeline:**
- GitHub Actions, two workflows:
  - `.github/workflows/docker-image.yml` - builds and pushes the Docker image to ghcr.io on every push to `main` (path-filtered to exclude docs-only changes) and weekly via cron (`17 4 * * 1`) to pick up base-image security fixes; also supports `workflow_dispatch`
  - `.github/workflows/patch-integrity.yml` - runs on PRs and pushes to `main`; checks out the pinned vLLM source (`vllm-project/vllm@v0.28.0`) and verifies every patch in `patches/` still applies (`patches/_check_applied.py`)
- No separate test-runner CI job; the Docker build itself is the quality gate (`verify.sh --install` runs inside the `Dockerfile`)

## Environment Configuration

**Required env vars (runtime, all optional with defaults in the start scripts):**
- `VLLM_API_KEY` - API bearer token (auth)
- `CTX`, `KV`, `MAX_LEN`, `MAX_SEQS`, `GPU_UTIL`, `VISION`, `SPEC`/`SPEC_ATTN`, `DRAFT_TOKENS`/`DFLASH_TOKENS`, `INT8_ACT`, `INT8_LAYERS`, `PREFIX_CACHE`, `EXTRA_ARGS` - model/serving configuration, no external service ties
- `VLLM_WSL2_ENABLE_PIN_MEMORY`, `VLLM_OFFLOAD_KEEP_SHM` - WSL2-specific memory tuning
- `PREPARE`, `VERIFY` - control flags for `docker/entrypoint.sh`
- `HF_HUB_ENABLE_HF_TRANSFER=1` - baked into the image for faster Hugging Face downloads

**Secrets location:**
- `.env` file at repo root (gitignored, read via `env_file:` in `docker-compose.yml`) — holds `VLLM_API_KEY=...` and other knobs
- `api_key.txt` at repo root (gitignored) — plain-text alternative to `VLLM_API_KEY`
- CI secret: `GITHUB_TOKEN` (auto-provided by GitHub Actions, used only for ghcr.io push)
- No Hugging Face token, cloud credentials, or other secret material found in the repo or its scripts

## Webhooks & Callbacks

**Incoming:**
- None. The only exposed endpoint is vLLM's own OpenAI-compatible API (`/v1/chat/completions`, `/health`, etc.) on port 18020 — a synchronous request/response API, not a webhook receiver.

**Outgoing:**
- None. No outbound webhook, notification, or callback integration (e.g. Slack, Discord, email) found in any script or workflow.

---

*Integration audit: 2026-09-05*
