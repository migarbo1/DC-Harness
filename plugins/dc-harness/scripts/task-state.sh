#!/usr/bin/env bash
# task-state.sh: the gatekeeper every /dc: skill calls first (contracts §4).
#
# Usage: task-state.sh <skill> <session-id> [<checkpoint>]
#   <skill>       start-task | plan | implement | assessment | pr-text
#   <session-id>  "${CLAUDE_SESSION_ID}", always passed (spike S8)
#   <checkpoint>  implement only, optional: CP2, cp2 or 2
#
# It checks the skill's preconditions in order (contracts §4.3) and refuses at the first one
# that fails. When every check passes it writes state.json, the only script that does.
#
# Exit codes and output (contracts §4.2):
#   0  allowed: key=value lines on stdout (task-dir=, plus commit-ref=, approval-phrase=,
#      checkpoint=, questions=)
#   1  refused: one line on stdout; the skill prints it exactly and stops
#   2  can't run: one line on stderr starting with "dc: internal:"

# SC2329: the check_* functions are called by name from the check lists below.
# SC2016: jq filters use $variables inside single quotes on purpose.
# shellcheck disable=SC2329,SC2016
set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
# shellcheck source=SCRIPTDIR/lib/msg.sh
source "$LIB_DIR/msg.sh"
# shellcheck source=SCRIPTDIR/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=SCRIPTDIR/lib/hash.sh
source "$LIB_DIR/hash.sh"
# shellcheck source=SCRIPTDIR/lib/task.sh
source "$LIB_DIR/task.sh"

USAGE="usage: task-state.sh <start-task|plan|implement|assessment|pr-text> <session-id> [<checkpoint>]"

# ---------------------------------------------------------------------------
# Arguments, and the checks per skill in order (contracts §4.3)
# ---------------------------------------------------------------------------

SKILL=${1:-}
SESSION=${2:-}
CHECKPOINT_ARG=${3:-}

case "$SKILL" in
  start-task) CHECKS=(G1 G2 S1 S2 S3 S4) ;;
  plan)       CHECKS=(G1 G2 G3 G4 P1 P2 P3) ;;
  implement)  CHECKS=(G1 G2 G3 G4 I1 I2 I3 I4 I5 I6 I7) ;;
  assessment) CHECKS=(G1 G2 G3 G4 A1 A2) ;;
  pr-text)    CHECKS=(G1 G2 G3 R1 R2) ;;
  "") internal "$USAGE" ;;
  *)  internal "unknown skill '$SKILL'. $USAGE" ;;
esac

[ $# -le 3 ] || internal "$USAGE"

# The literal text means Claude Code didn't replace the variable in the SKILL.md.
# shellcheck disable=SC2016
if [ -z "$SESSION" ] || [ "$SESSION" = '${CLAUDE_SESSION_ID}' ]; then
  internal 'no session ID: ${CLAUDE_SESSION_ID} was not replaced in the skill. Update Claude Code.'
fi

# CP2, cp2 and 2 all mean CP2. Leading zeros are dropped (CP02 is CP2).
CHECKPOINT=""
if [ -n "$CHECKPOINT_ARG" ]; then
  [ "$SKILL" = implement ] || internal "only implement takes a checkpoint. $USAGE"
  if [[ "$CHECKPOINT_ARG" =~ ^([Cc][Pp])?([0-9]+)$ ]]; then
    CHECKPOINT="CP$((10#${BASH_REMATCH[2]}))"
  else
    internal "bad checkpoint '$CHECKPOINT_ARG': use CP<n>, for example CP2"
  fi
fi

command -v jq >/dev/null 2>&1 || internal "jq not found. Run doctor.sh."
ROOT=$(git_root) || internal "not a git repository."
cd "$ROOT" || internal "can't enter $ROOT"

# Set by the checks as they go.
BRANCH=""      # G2
TASK_DIR=""    # G3, absolute
NEXT_CP=""     # I6

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

spec_phrase() { config_get "$ROOT" '.specApprovalPhrase[0] // "Specification agreed"'; }
plan_phrase() { config_get "$ROOT" '.planApprovalPhrase[0] // "Plan agreed"'; }

# approved_hash KEY: the sha256 recorded for the spec or plan approval, or nothing.
approved_hash() {
  json_get "$TASK_DIR/approvals.json" ".$1.sha256 // empty" 2>/dev/null
}

# plan_checkpoints: prints the checkpoint numbers of plan.md headings, in file order
# (contracts §6.1: `## CP<n>: <title>`).
plan_checkpoints() {
  tr -d '\r' < "$TASK_DIR/plan.md" | sed -nE 's/^## CP([0-9]+): .+$/\1/p'
}

# cp_done N: the notes have a `## CP<N>` entry (contracts §6.2).
cp_done() {
  [ -f "$TASK_DIR/implementation-notes.md" ] &&
    tr -d '\r' < "$TASK_DIR/implementation-notes.md" | grep -qE "^## CP$1(:|$)"
}

# ---------------------------------------------------------------------------
# Shared checks
# ---------------------------------------------------------------------------

check_G1() {
  task_onboarded "$ROOT" ||
    refuse "This repo isn't onboarded for DC-Harness (no .harness/config.json)."
}

check_G2() {
  BRANCH=$(git_branch) || refuse "HEAD is detached. Check out a branch first."
}

check_G3() {
  local open
  if TASK_DIR=$(task_for_branch "$ROOT" "$BRANCH"); then
    return 0
  fi
  if open=$(task_open_branch "$ROOT"); then
    refuse "The open task is on $open. Switch back to it."
  fi
  refuse "No task on this branch. Start one with /dc:start-task <description>."
}

check_G4() {
  if task_is_finished "$TASK_DIR"; then
    refuse "Task finished (pr-text.md exists). Start a new task on a new branch."
  fi
}

# ---------------------------------------------------------------------------
# start-task
# ---------------------------------------------------------------------------

check_S1() {
  local open
  if open=$(task_open_branch "$ROOT"); then
    refuse "Task open on branch $open. Finish it with /dc:pr-text first."
  fi
}

check_S2() {
  local pattern
  while IFS= read -r pattern; do
    [ -n "$pattern" ] || continue
    # Unquoted on purpose: entries are glob patterns (contracts §1.1), so release/* works.
    # shellcheck disable=SC2053
    if [[ "$BRANCH" == $pattern ]]; then
      refuse "Branch $BRANCH is protected. Create a task branch first."
    fi
  done < <(config_get "$ROOT" '.protectedBranches[]?')
}

check_S3() {
  local rel
  rel=$(task_rel_dir "$BRANCH")
  if [ -e "$ROOT/$rel" ]; then
    refuse "$rel/ already holds a finished task. Delete it to start a new task here."
  fi
}

check_S4() {
  git_is_clean ||
    refuse "Working tree not clean. Commit or stash your changes, and discard or gitignore untracked files."
}

# ---------------------------------------------------------------------------
# plan
# ---------------------------------------------------------------------------

check_P1() {
  [ -f "$TASK_DIR/spec.md" ] || refuse "No spec.md. Run /dc:start-task first."
}

check_P2() {
  [ -n "$(approved_hash spec)" ] || refuse "Spec not approved: type '$(spec_phrase)'."
}

check_P3() {
  [ "$(approved_hash spec)" = "$(sha256_file "$TASK_DIR/spec.md")" ] ||
    refuse "spec.md changed since approval: review it and type '$(spec_phrase)' again."
}

# ---------------------------------------------------------------------------
# implement
# ---------------------------------------------------------------------------

check_I1() {
  [ -f "$TASK_DIR/plan.md" ] || refuse "No plan.md. Run /dc:plan first."
}

check_I2() {
  [ -n "$(approved_hash plan)" ] || refuse "Plan not approved: type '$(plan_phrase)'."
}

check_I3() {
  [ "$(approved_hash plan)" = "$(sha256_file "$TASK_DIR/plan.md")" ] ||
    refuse "plan.md changed since approval: review it and type '$(plan_phrase)' again."
}

check_I4() {
  local plan_session
  plan_session=$(json_get "$TASK_DIR/state.json" '.planSession // empty')
  if [ "$SESSION" = "$plan_session" ]; then
    refuse "This session wrote the plan. Run /clear, then /dc:implement."
  fi
}

check_I5() {
  local n expected=1
  local -a numbers
  mapfile -t numbers < <(plan_checkpoints)
  if [ "${#numbers[@]}" -eq 0 ]; then
    refuse "plan.md has no checkpoints (## CP<n>: <title>). Run /dc:plan again."
  fi
  for n in "${numbers[@]}"; do
    # 10# reads CP08 as 8, not as a bad octal number. CP08 still fails: it isn't written CP8.
    if [ "$n" != "$expected" ]; then
      refuse "plan.md checkpoints must be numbered CP1, CP2, … in order. Run /dc:plan again."
    fi
    expected=$((expected + 1))
  done
}

check_I6() {
  local n
  for n in $(plan_checkpoints); do
    if ! cp_done "$n"; then
      NEXT_CP="CP$n"
      return 0
    fi
  done
  refuse "All checkpoints done. Run /dc:assessment."
}

check_I7() {
  if [ -n "$CHECKPOINT" ] && [ "$CHECKPOINT" != "$NEXT_CP" ]; then
    refuse "The next checkpoint is $NEXT_CP. Run /dc:implement or /dc:implement $NEXT_CP."
  fi
}

# ---------------------------------------------------------------------------
# assessment
# ---------------------------------------------------------------------------

check_A1() {
  if [ ! -f "$TASK_DIR/plan.md" ] || [ ! -f "$TASK_DIR/implementation-notes.md" ]; then
    refuse "No implementation-notes.md. Run /dc:implement first."
  fi
}

check_A2() {
  local n missing=""
  for n in $(plan_checkpoints); do
    cp_done "$n" || missing="${missing:+$missing, }CP$n"
  done
  if [ -n "$missing" ]; then
    refuse "Checkpoints not done: $missing. Run /dc:implement."
  fi
}

# ---------------------------------------------------------------------------
# pr-text
# ---------------------------------------------------------------------------

check_R1() {
  [ -f "$TASK_DIR/spec.md" ] || refuse "No spec.md. Run /dc:start-task first."
}

check_R2() {
  if [ ! -f "$TASK_DIR/assessment.md" ] ||
     ! tr -d '\r' < "$TASK_DIR/assessment.md" |
         grep -qE '^Score: [0-9]+/[0-9]+ \((passed|not passed)\)$'; then
    refuse "Assessment not finished. Run /dc:assessment."
  fi
}

# ---------------------------------------------------------------------------
# Run the checks, then write state.json
# ---------------------------------------------------------------------------

for check in "${CHECKS[@]}"; do
  "check_$check"
done

# set_state FILTER [JQ_ARGS...]: updates state.json, or stops with exit 2.
set_state() {
  json_update "$TASK_DIR/state.json" "$@" ||
    internal "can't write $TASK_DIR/state.json"
}

case "$SKILL" in
  start-task)
    TASK_DIR="$ROOT/$(task_rel_dir "$BRANCH")"
    mkdir -p "$TASK_DIR" || internal "can't create $TASK_DIR"
    commit_ref=$(git_head_sha) || internal "the branch has no commit yet. Commit once first."
    set_state '{schemaVersion: 1, branch: $b, commitRef: $c, startedAt: $t,
                step: "start-task", gate: "spec", planSession: null}' \
      --arg b "$BRANCH" --arg c "$commit_ref" --arg t "$(date -u +%FT%TZ)"
    ;;
  plan)
    set_state '.step = "plan" | .gate = "plan" | .planSession = $s' --arg s "$SESSION"
    ;;
  implement)
    set_state '.step = "implement" | .gate = null'
    ;;
  assessment)
    set_state '.step = "assessment" | .gate = "assessment"'
    ;;
  pr-text)
    set_state '.step = "pr-text" | .gate = null'
    ;;
esac

echo "task-dir=$(task_rel_dir "$BRANCH")"
case "$SKILL" in
  start-task)
    echo "commit-ref=$commit_ref"
    echo "approval-phrase=$(spec_phrase)"
    ;;
  plan)
    echo "approval-phrase=$(plan_phrase)"
    ;;
  implement)
    echo "checkpoint=$NEXT_CP"
    ;;
  assessment)
    echo "commit-ref=$(json_get "$TASK_DIR/state.json" '.commitRef')"
    echo "questions=$(config_get "$ROOT" '.assessment.numQuestions')"
    ;;
esac
exit 0
