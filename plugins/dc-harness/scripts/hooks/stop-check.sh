#!/usr/bin/env bash
# stop-check.sh: the Stop hook (contracts §5.5).
#
# Only while the step is `implement`. When the working tree changed since the last passing
# check, runs `stack-check.sh affected <changed files>` and blocks the stop until it passes.
# Every failure counts as caused by the task: there's no loop limit. The developer presses
# Esc to interrupt when the agent can't fix it.
#
# "Changed" is a fingerprint of the working tree as git sees it (lib/git.sh,
# git_worktree_tree): untracked files count, gitignored files (.tasks/ included) don't.
#
# DC_STACK_CHECK: path of the stack-check script to run instead of the plugin's own
# scripts/stack-check.sh. For the tests only.

# SC2016: jq filters use $variables inside single quotes on purpose.
# shellcheck disable=SC2016
set -u

# shellcheck source=SCRIPTDIR/../lib/hook.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/hook.sh"

EVENT=Stop
hook_init
[ "$STEP" = implement ] || exit 0

STOP_FILE="$TASK_DIR/stop-check.json"
OUTPUT_LINES=40

tree=$(git_worktree_tree) || fail_open

# Before the first check, the starting point is the commit-ref's tree.
last=$(json_get "$STOP_FILE" '.lastPassedTree // empty' 2>/dev/null)
if [ -z "$last" ]; then
  commit_ref=$(json_get "$TASK_DIR/state.json" '.commitRef // empty') || fail_open
  last=$(git_tree_of "$commit_ref") || fail_open
fi

# Nothing changed since the last pass: allow the stop.
[ "$tree" = "$last" ] && exit 0

mapfile -t changed < <(git_changed_files "$last" "$tree")

checker=${DC_STACK_CHECK:-"$PLUGIN_ROOT/scripts/stack-check.sh"}
[ -f "$checker" ] || fail_open

if output=$(bash "$checker" affected "${changed[@]}" 2>&1); then
  json_update "$STOP_FILE" '{schemaVersion: 1, lastPassedTree: $t}' --arg t "$tree" || fail_open
  exit 0
fi

emit "$EVENT" block "Checks failed. Fix them before finishing:
$(printf '%s\n' "$output" | tail -n "$OUTPUT_LINES")" "" ""
exit 0
