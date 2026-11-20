#!/usr/bin/env bash
# lib/hook.sh: the shared start of every hook (contracts §5.2).
# Source it; it only defines functions. It sources the other libs.
#
#   source "$(dirname "${BASH_SOURCE[0]}")/../lib/hook.sh"
#   hook_init            # reads stdin; exits 0 silently when there's nothing to do
#   ... uses PAYLOAD, ROOT, BRANCH, TASK_DIR, STEP, GATE, SESSION_ID
#
# SC2034: the variables set here are used by the hooks that source this file.
# shellcheck disable=SC2034

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=SCRIPTDIR/msg.sh
source "$LIB_DIR/msg.sh"
# shellcheck source=SCRIPTDIR/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=SCRIPTDIR/hash.sh
source "$LIB_DIR/hash.sh"
# shellcheck source=SCRIPTDIR/task.sh
source "$LIB_DIR/task.sh"

# The plugin root, for scripts the hooks call (stack-check.sh).
PLUGIN_ROOT="$(cd "$LIB_DIR/../.." && pwd)"

# hook_init: reads the hook payload from stdin and finds the task it applies to.
# Sets PAYLOAD, ROOT, BRANCH, TASK_DIR (absolute), STEP, GATE and SESSION_ID, and cds to ROOT.
# Exits 0 with no output when the hook has nothing to do: not a git repo, not onboarded,
# detached HEAD, or no task on this branch (contracts §5.2).
# Fails open when jq is missing: the developer is told, nothing is blocked (§5.3).
hook_init() {
  local cwd
  command -v jq >/dev/null 2>&1 || fail_open

  PAYLOAD=$(cat)
  cwd=$(json_get_text "$PAYLOAD" '.cwd // empty' 2>/dev/null) || fail_open
  SESSION_ID=$(json_get_text "$PAYLOAD" '.session_id // empty')

  if [ -n "$cwd" ]; then
    cd "$cwd" 2>/dev/null || exit 0
  fi
  ROOT=$(git_root) || exit 0
  cd "$ROOT" || exit 0
  task_onboarded "$ROOT" || exit 0
  BRANCH=$(git_branch) || exit 0
  TASK_DIR=$(task_for_branch "$ROOT" "$BRANCH") || exit 0

  STEP=$(json_get "$TASK_DIR/state.json" '.step // empty') || fail_open
  GATE=$(json_get "$TASK_DIR/state.json" '.gate // empty') || fail_open
}

# now_utc: the current time, ISO 8601 in UTC (contracts: general rules).
now_utc() {
  date -u +%FT%TZ
}
