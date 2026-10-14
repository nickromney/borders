#!/usr/bin/env bash
# shellcheck disable=SC2034 # VK_* settings are read by the sourced verify-lib.sh
set -euo pipefail

VK_SCRIPT="$0"
VK_APP="borders"
VK_DESCRIPTION="Build Borders in isolated state, launch its real menu-bar process, and drive its local CLI."
VK_DEFAULT_BASE_DIR="${TMPDIR:-/tmp}/verify-borders"
VK_DEFAULT_EVIDENCE_ROOT="$VK_DEFAULT_BASE_DIR/evidence"
# shellcheck source=verify-lib.sh disable=SC1091
. "$(cd "$(dirname "$0")" && pwd)/verify-lib.sh"

vk_commands_help() {
  cat <<'HELP'
  launch                 build and launch Borders with a private socket and HOME
  doctor                 read-only: confirm this run's app process and socket respond
  cleanup                stop this run's app; keep evidence
HELP
}
vk_sample_commands() { printf '%s\n' verify launch doctor cleanup; }
vk_paths() {
  STATE="$VK_BASE_DIR/$VK_RUN_ID/state"
  EVIDENCE="$VK_EVIDENCE_ROOT/$VK_RUN_ID"
  APP="$STATE/build/debug/borders"
  SOCKET="$STATE/borders.sock"
  PIDFILE="$STATE/app.pid"
  LOG="$EVIDENCE/app.log"
}

vk_plan() {
  case "$1" in
    verify) vk_plan_line "build with at most 2 jobs; launch the real app in isolated HOME/socket; drive status and off through CLI; verify state; stop owned process; retain evidence at $EVIDENCE" ;;
    launch) vk_plan_line "build .build/debug/borders under $STATE/build and launch with BORDERS_SOCKET_PATH=$SOCKET and HOME=$STATE/home" ;;
    doctor) vk_plan_line "query this run's private socket with borders status (read-only)" ;;
    cleanup) vk_plan_line "stop only process group recorded in $PIDFILE; remove state and retain $EVIDENCE" ;;
    *) vk_unknown_command ;;
  esac
}

app_env() { env HOME="$STATE/home" TMPDIR="$STATE/tmp" BORDERS_SOCKET_PATH="$SOCKET" "$@"; }
cmd_launch() {
  mkdir -p "$STATE/home/.config/borders" "$STATE/tmp" "$EVIDENCE"
  printf 'mode=off\n' > "$STATE/home/.config/borders/borders.conf"
  vk_mark_current
  vk_record_revision "$EVIDENCE/revision.txt"
  swift build --jobs 2 --build-path "$STATE/build" > "$EVIDENCE/build.log" 2>&1 || { cat "$EVIDENCE/build.log" >&2; vk_fail "Swift build failed; see $EVIDENCE/build.log"; return 1; }
  vk_expect_file "$APP"
  vk_spawn_group "$PIDFILE" "$LOG" env HOME="$STATE/home" TMPDIR="$STATE/tmp" BORDERS_SOCKET_PATH="$SOCKET" "$APP"
  vk_wait_for_alive "$PIDFILE" 20 env HOME="$STATE/home" TMPDIR="$STATE/tmp" BORDERS_SOCKET_PATH="$SOCKET" "$APP" status || { vk_fail "Borders did not answer on its private socket; see $LOG"; return 1; }
  app_env "$APP" status > "$EVIDENCE/status-initial.txt"
  vk_say "launched private Borders process; evidence=$EVIDENCE"
}
cmd_doctor() {
  if [ ! -f "$PIDFILE" ] || ! vk_group_alive "$PIDFILE"; then
    vk_fail "this run's app process is not alive"
    return 1
  fi
  app_env "$APP" status > "$EVIDENCE/status-doctor.txt" || { vk_fail "private status command failed"; return 1; }
  vk_expect_contains "$EVIDENCE/status-doctor.txt" "mode=off"
}
cmd_cleanup() {
  if [ -f "$PIDFILE" ]; then
    app_env "$APP" quit > "$EVIDENCE/quit.txt" 2>&1 || true
    vk_stop_group "$PIDFILE"
  fi
  rm -rf "${STATE:?}"
  rmdir "$VK_BASE_DIR/$VK_RUN_ID" 2>/dev/null || true
  vk_clear_current
  vk_say "stopped this run's app and removed state; evidence kept at $EVIDENCE"
}
vk_verify_recipes() {
  app_env "$APP" status > "$EVIDENCE/status-cli.txt"
  vk_expect_contains "$EVIDENCE/status-cli.txt" "mode=off"
  app_env "$APP" off > "$EVIDENCE/off-cli.txt"
  vk_expect_contains "$EVIDENCE/off-cli.txt" "mode=off"
  cmd_doctor
}
vk_dispatch() {
  local cmd="$1"; shift
  case "$cmd" in
    launch) cmd_launch ;;
    doctor) cmd_doctor ;;
    cleanup) cmd_cleanup ;;
    *) vk_unknown_command ;;
  esac
}
vk_main "$@"
