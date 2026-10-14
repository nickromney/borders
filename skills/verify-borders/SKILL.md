# Verify Borders

Run `make verify-dry-run` to preview and `make verify` to build and launch the real Borders process with a private HOME, preferences, config and Unix socket. The harness exercises the `status`, `off` and `quit` CLI paths; it does not exercise physical Key Light hardware.

Run `make verify-test` for shellcheck and the shared BATS contract suite. The live run requires Swift and macOS AppKit in an active user session. Evidence remains at the path printed by `VERIFY PASS` after the owned process and temporary state are cleaned up.

The harness only terminates the process group it starts. It keeps build logs, CLI replies and the run revision in the evidence directory.
