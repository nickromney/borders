# borders agent guide

## Verify

- One-time per clone: `lefthook install`. The pre-push hook runs `make check-local`: `make test` (unit tests and strict bundle build), `make complexity` and `git diff --check`.
- `make complexity` runs `lizard` through `uv run --locked`, so `uv` must be installed. It fails above CCN 7 (`COMPLEXITY_THRESHOLD`); split the function rather than raising the number.
- `make mutation-execute` is opt-in and is not part of the gate.
- `make dev` asks the running copy to quit, replaces `~/Applications/Borders.app` and launches it.
- `make keylight-hardware-test ARGS="--host <host>"` drives a real Key Light. Run it only attended.
- `borders status` reports the running app's settings over `/tmp/borders.sock`. A reply does not prove a physical light is lit. A timed-out or empty reply is a typed refusal with a nonzero exit; it does not prove app state.
