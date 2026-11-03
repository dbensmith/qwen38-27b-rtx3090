# HyperQwen shortcuts. Every target delegates to docker compose or a
# checked-in script — no hidden flags. `make help` lists them.
# Native (venv) launchers remain: bash single-user/start_qwen.sh etc.

.PHONY: help up-single up-batch down logs ps verify verify-install warmup shell keygen doctor

help: ## show this list
	@grep -E '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'

up-single: ## serve one/few users (stops batch, persists choice)
	@docker compose --profile batch stop >/dev/null 2>&1 || true
	docker compose --profile single up -d
	@printf 'single\n' > .current-profile
	@echo "first boot compiles (~2-15 min); follow with: make logs"

up-batch: ## serve API backend / many concurrent (stops single, persists choice)
	@docker compose --profile single stop >/dev/null 2>&1 || true
	docker compose --profile batch up -d
	@printf 'batch\n' > .current-profile
	@echo "first boot compiles (~2-15 min); follow with: make logs"

down: ## stop server
	docker compose down

logs: ## follow server logs (Ctrl-C anytime)
	docker compose logs -f --tail 30

ps: ## container state + /health from inside WSL/network namespace
	docker ps --filter name=hyperqwen --format "{{.Names}} {{.Status}}"
	@curl -s -o /dev/null -w "health: HTTP %{http_code}\n" http://127.0.0.1:$${PORT:-18020}/health || true

verify: ## verify.sh inside the running single/batch container (live checks included), else in a fresh one (no live server)
	@svc=$$(docker compose ps --status running --services 2>/dev/null | grep -xE 'single|batch' | head -n1); \
	if [ -n "$$svc" ]; then echo "verify: running inside the running '$$svc' service"; docker compose exec $$svc bash verify.sh; \
	else echo "verify: no single/batch service running; live-server checks will be skipped"; docker compose run --rm single verify; fi

verify-install: ## install-only checks (venv, vLLM, patches, KVarN): no GPU/model/server
	bash verify.sh --install

warmup: ## run the post-health serving warmup inside the running single/batch
	@svc=$$(docker compose ps --status running --services 2>/dev/null | grep -xE 'single|batch' | head -n1); \
	if [ -z "$$svc" ]; then echo "warmup: no running single/batch service"; exit 1; fi; \
	docker compose exec "$$svc" bash bench/warmup.sh

shell: ## throwaway shell in the server image (patches + venv, no GPU boot)
	docker compose run --rm single bash

keygen: ## append a fresh VLLM_API_KEY to .env without clobbering it (safe to re-run: skips if set)
	@if grep -q '^VLLM_API_KEY=.\+' .env 2>/dev/null; then echo ".env already has VLLM_API_KEY (presence-only check, value not shown)"; else KEY=$$(openssl rand -hex 24); printf 'VLLM_API_KEY=%s\n' "$$KEY" >> .env; echo "appended VLLM_API_KEY to .env"; fi

doctor: ## read-only status: config + GPU + port + /health + last log error (no secrets printed)
	bash scripts/hq-doctor.sh
