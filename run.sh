#!/usr/bin/env bash
# Slate -- one-command run.
#
# Supply your keys in slate.env (copy slate.env.example), then run:  ./run.sh
#
# It is idempotent and re-runnable, and it FAILS CLOSED: any missing required
# key stops the run with a clear message, so Slate never starts half-configured.
# Read docs/configuration.md for what each key is and why. Read docs/quickstart.md
# for the whole walk-through.
#
# By default this runs Slate directly with Node (>= 24). To run it in Docker
# instead, see docs/quickstart.md ("Run it in Docker").
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

say()  { printf "\n==> %s\n" "$*"; }
info() { printf "    %s\n" "$*"; }
warn() { printf "    (note) %s\n" "$*"; }
die()  { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

# ---- 1. load and check slate.env --------------------------------------------
say "Checking your keys"
[ -f slate.env ] || die "slate.env not found. Run: cp slate.env.example slate.env  (then edit it)."

# Export every value so bot.mjs (which reads process.env) can see it.
set -a; . ./slate.env; set +a

# The one hard requirement.
[ -n "${DISCORD_TOKEN:-}" ] || die "slate.env: DISCORD_TOKEN is required but empty -- get it from the Discord Developer Portal (Bot -> Reset Token)."

# The writing brain: Claude path needs its endpoint; otherwise we fall back to Ollama.
if [ -n "${CF_AIG_TOKEN:-}" ]; then
  [ -n "${CF_GATEWAY_ENDPOINT:-}" ] || die "slate.env: CF_AIG_TOKEN is set (Claude path) but CF_GATEWAY_ENDPOINT is empty -- add your AI Gateway compat URL, or clear CF_AIG_TOKEN to use Ollama."
  info "Writing brain: Claude via Cloudflare AI Gateway (model ${DISCORD_MODEL:-claude-sonnet-4-6})."
else
  info "Writing brain: Ollama at ${OLLAMA_BASE_URL:-http://localhost:11434/v1} (model ${DISCORD_MODEL:-qwen3.6:27b-ctx8k}). Set CF_AIG_TOKEN + CF_GATEWAY_ENDPOINT to use Claude."
fi

# Optional features: warn, never fail, so a first run is easy.
[ -n "${VIVIJURE_API_URL:-}" ] || warn "VIVIJURE_API_URL is empty -- Slate will plan films but cannot render them. Point it at your Studio to enable !render."
[ -n "${CF_D1_TOKEN:-}" ]      || warn "CF_D1_TOKEN is empty -- Slate will run without saved memory; projects reset when the process restarts."
[ -n "${SEARCH_WORKER_URL:-}" ] || warn "SEARCH_WORKER_URL is empty -- web search and the knowledge base are off. That is fine to start."

# ---- 2. check the runtime ---------------------------------------------------
say "Checking Node"
command -v node >/dev/null 2>&1 || die "Node is not installed. Install Node 24 or newer (nodejs.org), then run ./run.sh again. Or run Slate in Docker -- see docs/quickstart.md."
NODE_MAJOR="$(node -p "process.versions.node.split(\".\")[0]")"
[ "$NODE_MAJOR" -ge 24 ] || die "Node $NODE_MAJOR is too old. Slate needs Node 24 or newer."
info "Node $(node -v) OK."

# ---- 3. install dependencies (idempotent) -----------------------------------
say "Installing dependencies"
if [ -d node_modules ]; then
  info "node_modules already present; skipping install (delete it to force a fresh install)."
else
  if [ -f package-lock.json ]; then npm ci --no-audit --no-fund; else npm install --no-audit --no-fund; fi
fi

# ---- 4. run -----------------------------------------------------------------
say "Starting Slate"
info "Press Ctrl-C to stop."
exec node bot.mjs
