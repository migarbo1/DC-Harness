#!/usr/bin/env bash
# pr-text-length.sh: checks pr-text.md of the current branch's task against prTextMaxChars
# (contracts §4.5). /dc:pr-text runs it after writing the file: the agent can't count
# characters reliably itself.
#
# Usage: pr-text-length.sh
#
# Characters, not bytes, are counted (a UTF-8 locale makes `ñ` one character), after removing
# `\r`: a browser turns CRLF into one line break when the text is pasted into the PR.
#
# Exit codes:
#   0  within the limit: one line on stdout, `chars=<n> max=<m>`
#   1  over the limit: one line on stdout naming both numbers
#   2  can't run: not a git repo, not onboarded, no task, no pr-text.md, bad usage

set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=SCRIPTDIR/lib/msg.sh
source "$LIB_DIR/msg.sh"
# shellcheck source=SCRIPTDIR/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=SCRIPTDIR/lib/task.sh
source "$LIB_DIR/task.sh"

[ $# -eq 0 ] || internal "usage: pr-text-length.sh"

command -v jq >/dev/null 2>&1 || internal "jq not found. Run doctor.sh."
ROOT=$(git_root) || internal "not a git repository."
task_onboarded "$ROOT" || internal "this repo isn't onboarded (no .harness/config.json)."
BRANCH=$(git_branch) || internal "HEAD is detached."
TASK_DIR=$(task_for_branch "$ROOT" "$BRANCH") || internal "no task on branch $BRANCH."
FILE="$TASK_DIR/pr-text.md"
[ -f "$FILE" ] || internal "no $(task_rel_dir "$BRANCH")/pr-text.md yet."

MAX=$(config_get "$ROOT" '.prTextMaxChars')
[[ "$MAX" =~ ^[0-9]+$ ]] || internal "prTextMaxChars is not a whole number: '$MAX'."

CHARS=$(tr -d '\r' < "$FILE" | LC_ALL=C.UTF-8 wc -m)
CHARS=$((CHARS + 0))   # wc pads the number with spaces on some platforms

if [ "$CHARS" -gt "$MAX" ]; then
  echo "pr-text.md has $CHARS characters; the limit is $MAX. Shorten it by $((CHARS - MAX)) or more."
  exit 1
fi
echo "chars=$CHARS max=$MAX"
