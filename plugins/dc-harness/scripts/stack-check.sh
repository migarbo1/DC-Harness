#!/usr/bin/env bash
# stack-check.sh: runs the project's checks for every stack in .harness/config.json
# (contracts §1.2).
#
# Usage: stack-check.sh affected <file>...    (stop-check.sh, after each agent turn)
#        stack-check.sh full                  (/dc:implement, before writing a checkpoint's notes)
#   <file>  changed files, relative to the repo root (new, modified and deleted)
#
# Stacks run in the order of `stack`. Each stack's stacks/<name>/stack-check.sh gets the
# mode and the full file list, picks its own files and runs its commands from the repo root.
#
# Exit codes:
#   0  every stack passed
#   1  at least one stack failed (its output says which check)
#   2  can't run: not a git repo, not onboarded, unknown stack, bad usage

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=SCRIPTDIR/lib/msg.sh
source "$SCRIPT_DIR/lib/msg.sh"
# shellcheck source=SCRIPTDIR/lib/git.sh
source "$SCRIPT_DIR/lib/git.sh"
# shellcheck source=SCRIPTDIR/lib/task.sh
source "$SCRIPT_DIR/lib/task.sh"

USAGE="usage: stack-check.sh affected <file>... | stack-check.sh full"

MODE=${1:-}
case "$MODE" in
  affected) shift ;;
  full)     shift; [ $# -eq 0 ] || internal "$USAGE" ;;
  *)        internal "$USAGE" ;;
esac

command -v jq >/dev/null 2>&1 || internal "jq not found. Run doctor.sh."
ROOT=$(git_root) || internal "not a git repository."
cd "$ROOT" || internal "can't enter $ROOT"
task_onboarded "$ROOT" || internal "this repo isn't onboarded (no .harness/config.json)."

mapfile -t STACKS < <(config_get "$ROOT" '.stack[]?')
[ "${#STACKS[@]}" -gt 0 ] || internal "no stack in .harness/config.json."

# Unknown stacks are an error before anything runs.
for stack in "${STACKS[@]}"; do
  [ -f "$PLUGIN_ROOT/stacks/$stack/stack-check.sh" ] ||
    internal "unknown stack '$stack': the plugin has no stacks/$stack/stack-check.sh."
done

FAILED=0
for stack in "${STACKS[@]}"; do
  bash "$PLUGIN_ROOT/stacks/$stack/stack-check.sh" "$MODE" "$@" || FAILED=1
done
exit "$FAILED"
