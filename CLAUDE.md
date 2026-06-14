# CLAUDE.md

**Slate** -- Vivijure Screenwriter's Assistant for Discord. A collaborative film planning bot that maintains a storyboard brief, generates character portraits, searches the web, and submits projects to the Vivijure render pipeline.

## Structure

```
bot.mjs                  Node 24+ Discord bot (main entry point)
package.json             Bot dependencies (@anthropic-ai/sdk, discord.js)
search-worker/           Cloudflare Worker: web search + knowledge base
  src/index.ts           Worker source
  wrangler.toml          Bindings: Browser, AI, Vectorize (slate-knowledge)
stacks/
  dischord.yml           Docker Compose stack for dischord (production)
  .env                   Secrets (never committed; see dischord.yml header)
```

## Running (production: dischord)

```bash
# Initial setup on dischord
ssh root@dischord.internal "
  cd ~/dev && git clone git@github.com:SkyPhusion/skyphusion-slate.git slate
  cp ~/dev/bots/stacks/.env ~/dev/slate/stacks/.env  # copy existing secrets
  cd slate/stacks && docker compose -p slate -f dischord.yml up -d
"

# Redeploy after code changes
rsync -az /home/conrad/dev/slate/ root@dischord.internal:/root/dev/slate/ --exclude node_modules --exclude .git --exclude stacks/.env
ssh root@dischord.internal "docker compose -p slate -f ~/dev/slate/stacks/dischord.yml up -d --force-recreate slate"
```

## search-worker deploy

```bash
cd search-worker && npm ci && npm run deploy
```

**Vectorize index** (one-time setup -- already created):
```bash
npx wrangler vectorize create slate-knowledge --dimensions=1024 --metric=cosine
```

**Secrets** (set once via wrangler):
```bash
npx wrangler secret put BRAVE_API_KEY
npx wrangler secret put TAVILY_API_KEY
npx wrangler secret put SEARCH_SECRET
```

## Key architecture

- **Claude Sonnet via CF AI Gateway** (`/anthropic` path, native SDK). Ollama fallback when `CF_AIG_TOKEN` unset.
- **Tool use loop** (up to 5 rounds): `web_search` (Brave), `research` (Tavily), `fetch_page` (CF Browser Rendering), `search_knowledge` (Vectorize).
- **Vision**: image attachments fetched as base64, passed to Claude as image content blocks (ollama path strips to text).
- **D1 session state**: `sessions` table (channel storyboard + history + briefHistory) + `render_jobs` table (pending render polling).
- **Brief undo**: `briefHistory` array (max 10) in project state; pushed before each extractBrief update.
- **Render polling**: 30s interval checks Vivijure `/api/storyboard/render/:jobId`; notifies channel on completion.
- **Slash commands**: registered globally on startup via `Routes.applicationCommands`.
- **Knowledge base**: Vectorize index `slate-knowledge` (1024-dim, cosine). Embedded via `@cf/baai/bge-large-en-v1.5`.

## Commands

| Command | Slash | Description |
|---------|-------|-------------|
| `!brief` | `/brief` | Show current storyboard |
| `!portrait <A-D> [desc]` | `/portrait` | Generate + sync character portrait |
| `!thumbnail <scene-id>` | `/thumbnail` | Generate scene thumbnail |
| `!model [name]` | `/model` | Show/switch image model |
| `!render [quality]` | `/render` | Submit to Vivijure |
| `!undo` | `/undo` | Roll back last brief extraction |
| `!learn <text\|url>` | `/learn` | Index film reference into knowledge base |
| `!reset` | `/reset` | Clear project |

## Conventions (SkyPhusion house style)

- No em-dashes (U+2014) or en-dashes (U+2013) in source, comments, or docs.
- Minimal dependencies; vanilla Node.js + discord.js + Anthropic SDK only.
- Secrets never committed; all state in D1/R2/Vectorize (cloud-first).
