#!/usr/bin/env bash
# lib/stack.sh: what every stacks/<name>/stack-check.sh shares (contracts §1.2).
# Source it; it only defines functions. It sources git.sh and task.sh itself.
#
# Typical start of a stack script:
#   stack_init angular || exit $?
#   [ "$MODE" = full ] && { stack_run lint "$LINT"; …; exit "$FAILED"; }
#   while …; do rel=$(stack_rel "$f") || continue; …; done

# SC2034: STACK_DIR, LINT, TYPES, TESTS and FAILED are read by the stack scripts that source this.
# shellcheck disable=SC2034

# shellcheck source=SCRIPTDIR/git.sh
source "$(dirname "${BASH_SOURCE[0]}")/git.sh"
# shellcheck source=SCRIPTDIR/task.sh
source "$(dirname "${BASH_SOURCE[0]}")/task.sh"

# stack_init STACK: sets STACK, ROOT, STACK_DIR, LINT, TYPES, TESTS and FAILED=0, and cds into
# the stack's folder: stackCommands.<STACK>.dir, relative to the repo root, or the root itself
# when it isn't set. Commands run there, and changed files are made relative to it.
# Returns 2 outside a git repo, and 1 (with a FAILED line) when the folder doesn't exist.
stack_init() {
  STACK=$1
  ROOT=$(git_root) || return 2
  STACK_DIR=$(stack_command "$ROOT" "$STACK" dir)
  STACK_DIR=${STACK_DIR#./}
  STACK_DIR=${STACK_DIR%/}
  [ "$STACK_DIR" = . ] && STACK_DIR=""
  LINT=$(stack_command "$ROOT" "$STACK" lint)
  TYPES=$(stack_command "$ROOT" "$STACK" types)
  TESTS=$(stack_command "$ROOT" "$STACK" tests)
  FAILED=0
  if [ -n "$STACK_DIR" ] && [ ! -d "$ROOT/$STACK_DIR" ]; then
    echo "== $STACK FAILED: folder '$STACK_DIR' (stackCommands.$STACK.dir) not found"
    return 1
  fi
  cd "$ROOT/$STACK_DIR" || return 2
}

# stack_rel FILE: prints FILE (relative to the repo root) relative to the stack's folder, and
# fails when FILE is outside it.
stack_rel() {
  if [ -z "$STACK_DIR" ]; then
    printf '%s\n' "$1"
  elif [[ "$1" == "$STACK_DIR"/* ]]; then
    printf '%s\n' "${1#"$STACK_DIR"/}"
  else
    return 1
  fi
}

# stack_ls PATTERN...: every file under the stack's folder matching a git pathspec, tracked or
# new (gitignored ones left out), relative to the folder.
stack_ls() {
  git -c core.quotePath=false ls-files --cached --others --exclude-standard -- "$@"
}

# stack_run NAME COMMAND: runs COMMAND from the stack's folder. A pass prints one line; a
# failure prints the command's whole output, so the Stop hook's last 40 lines are about what
# failed and not a test runner's report of a passing run. A failure sets FAILED=1; the other
# checks still run. An empty COMMAND is skipped.
stack_run() {
  local name=$1 cmd=$2 out
  [ -n "$cmd" ] || return 0
  if out=$(bash -c "$cmd" 2>&1); then
    echo "-- $STACK $name passed: $cmd"
  else
    echo "== $STACK $name FAILED: $cmd"
    printf '%s\n' "$out"
    echo "-- $STACK $name FAILED"
    FAILED=1
  fi
}

# stack_full: runs lint, types and tests as written. The `full` size of every stack.
stack_full() {
  stack_run lint "$LINT"
  stack_run types "$TYPES"
  stack_run tests "$TESTS"
}
