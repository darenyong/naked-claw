# naked-claw

Personal AI chatbot with memory on Telegram. 260 lines of Common Lisp, 13 MB binary.

## Common Lisp — learned the hard way

The AI's training data is JS/TS-dominated. These are the CL-specific gotchas we've already hit. Don't repeat them.

### SBCL image model
- `defvar` with init forms bakes values at compile time in `save-lisp-and-die`. Always init to `nil`, read env vars at runtime in `load-config`.
- `save-lisp-and-die` captures the entire Lisp image. Anything evaluated at top level is frozen into the binary.

### Yason (JSON parsing)
- Yason parses JSON arrays as CL lists by default. We set `yason:*parse-json-arrays-as-vectors*` to `t` globally in `primitives.lisp`.
- This means `aref` and `loop across` work on parsed arrays, but list operations (`append`, `last`, `dolist`) need `coerce` first.

### Drakma (HTTP)
- Drakma defaults to Latin-1 encoding (library from 2004). Always pass `:external-format-out :utf-8 :external-format-in :utf-8` to `drakma:http-request`.
- Drakma does not support `:read-timeout`. Use `:connection-timeout` only.
- Response body may come back as `(vector (unsigned-byte 8))`. Use `flexi-streams:octets-to-string` to decode.

### CL style
- `;;;` for file-level comments, `;;` for code comments.
- Use our primitives (`json-obj`, `$`, `post-json`, `to-json`) instead of verbose hash-table construction or raw Drakma calls. They exist in `src/primitives.lisp`.
- CL is not JS with more parentheses. Don't write 10 lines of `alexandria:alist-hash-table` when `(json-obj "key" value)` does it in one.

### General CL pattern
- Old libraries, stable interfaces, occasional fossil defaults. Patch once and move on.
- The CL Hyperspec and library source code are the debugging tools, not Stack Overflow.
- Type entanglement across library boundaries is common. Every library has its own conventions for representing data — check what types you're getting back.

## Architecture

- 8 files in `src/`, each under 60 lines, loaded sequentially via ASDF (`:serial t`).
- Config vars are `nil` until `load-config` is called from `main`.
- Buffer is a JSON file, digest is a markdown file. No database.
- LLM calls go through `post-json` → provider detection (Gemini vs Ollama) → response parsing.
- Compaction triggers inline at 20 messages, not on a timer.

## Build

- `build.lisp` loads Quicklisp deps, loads the ASDF system, compiles via `save-lisp-and-die`.
- Multi-stage Containerfile: SBCL + Quicklisp in build stage, 13 MB binary in minimal Debian runtime.
- Deploy to cave: `scp` files, `podman build`, `podman run` with `--env-file`.
