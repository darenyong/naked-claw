# naked-claw

A personal AI chatbot with memory on Telegram. 260 lines of Common Lisp, 13 MB binary, two env vars.

Built by studying how [OpenClaw](https://github.com/open-claw/open-claw) (239k stars) implements memory and compaction to create a chatbot that remembers you — then stripping it down to the essential loop.

## What it does

1. You send a message on Telegram
2. The bot loads your conversation history and a digest of older conversations
3. It sends everything to an LLM and replies
4. When the buffer hits 20 messages, it compacts the oldest into a running digest

That's the entire architecture. No framework, no plugin system, no database. A JSON file for the buffer, a markdown file for the digest, and direct HTTP calls to whatever LLM you point it at.

## Quick start

You need two things: a [Telegram bot token](https://t.me/BotFather) (free — message @BotFather on Telegram, follow the prompts) and a [Gemini API key](https://aistudio.google.com/apikey) (free with any Google account — open the link, click "Get API key," copy. No billing, no credit card, takes 30 seconds).

```sh
docker run \
  -e TELEGRAM_TOKEN=your-bot-token \
  -e CHAT_API_URL=https://generativelanguage.googleapis.com \
  -e CHAT_MODEL=gemini-2.5-flash \
  -e API_KEY=your-gemini-key \
  -v naked-claw-data:/data \
  ghcr.io/darenyong/naked-claw
```

Send your bot a message. It remembers you.

## The 8 files

| File | Lines | Purpose |
|---|---|---|
| `package.lisp` | 5 | Package definition |
| `primitives.lisp` | 39 | JSON and HTTP helpers — what Node.js gives you for free |
| `config.lisp` | 27 | Environment variables, loaded at runtime |
| `buffer.lisp` | 24 | Message buffer — read, write, append to a JSON file |
| `compact.lisp` | 42 | Digest old messages to stay within context window |
| `llm.lisp` | 56 | Prompt building, API calls (Gemini + Ollama) |
| `telegram.lisp` | 48 | Long-polling, message dispatch |
| `main.lisp` | 19 | Entry point |

Every file is under 60 lines. You can read the entire codebase in one sitting.

## Configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `TELEGRAM_TOKEN` | Yes | — | Bot token from BotFather |
| `CHAT_API_URL` | No | mlvoca (demo) | LLM API endpoint |
| `CHAT_MODEL` | No | deepseek-r1:1.5b | Model name |
| `API_KEY` | No | — | API key for the LLM provider |
| `COMPACTION_API_URL` | No | same as chat | Separate endpoint for compaction |
| `COMPACTION_MODEL` | No | same as chat | Separate model for compaction |
| `DATA_DIR` | No | /data | Where buffer and digest are stored |
| `MAX_COMPACT` | No | 20 | Messages before compaction triggers |

## What this is not

**This is not a consumer product.** There's no multi-platform support, no plugin system, no skill marketplace. naked-claw does one thing — the memory loop — and lets you read exactly how.

**This is not a framework.** Want to add Claude API support? It's ~15 lines of adapter code in `llm.lisp`. Want Discord instead of Telegram? Replace `telegram.lisp`. The code is small enough to change by hand.

**This only works with API keys, not subscriptions.** Claude Max, ChatGPT Plus, Gemini Advanced — none of these give you programmatic API access. That's a provider limitation, not ours. Gemini's free API tier is the easiest on-ramp: same Google account, no billing, one click to generate a key.

## Why Common Lisp

The same bot exists in Node.js at 208 lines of business logic. The Common Lisp version is 208 lines of business logic plus 39 lines of primitives that replace what Node ships for free (JSON construction, HTTP helpers). The trade: you write 39 extra lines once, and get a 13 MB standalone binary with zero runtime dependencies.

## Build from source

```sh
# Requires: podman or docker
podman build -t naked-claw .
```

The Containerfile uses a multi-stage build: SBCL + Quicklisp compile a standalone binary in the first stage, then copy just the 13 MB binary into a minimal Debian runtime.

The author runs this on a NixOS machine where the entire system — including the bot as a systemd service — is declared in a single `configuration.nix`.

## License

MIT. Do whatever you want with it.
