#!/usr/bin/env bash
# stacks/python/stack-check.sh: the Python checks (contracts §1.2). Called by
# scripts/stack-check.sh, never directly.
#
# Usage: stack-check.sh full
#        stack-check.sh affected <file>...
#
# Commands: lint, types and tests, from the project's stackCommands.python or
# stacks/python/default.json. An empty or null command is skipped.
#
#   full      runs the three commands as written.
#   affected  does nothing when no .py file changed. Otherwise runs lint and types as written
#             (whole project) and tests on the affected test files only, appended to the
#             tests command:
#               - changed test files (test_*.py, *_test.py) that still exist;
#               - for each other changed module <name>.py in <folder>/: the test files named
#                 test_<x>.py or <x>_test.py, where <x> is <name>, <folder>, or <folder>
#                 without a final "s" (services/arithmetic.py → test_arithmetic.py,
#                 test_services.py, test_service.py).
#             If a changed module matches no test file (conftest.py, a module with no
#             test named after it), all tests run: a miss must not let a change through.
#
# Exit codes: 0 every check passed (or nothing to check), 1 a check failed.

set -u

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib" && pwd)"
# shellcheck source=SCRIPTDIR/../../scripts/lib/git.sh
source "$LIB_DIR/git.sh"
# shellcheck source=SCRIPTDIR/../../scripts/lib/task.sh
source "$LIB_DIR/task.sh"

MODE=${1:-}
shift
ROOT=$(git_root) || exit 2
cd "$ROOT" || exit 2

LINT=$(stack_command "$ROOT" python lint)
TYPES=$(stack_command "$ROOT" python types)
TESTS=$(stack_command "$ROOT" python tests)

FAILED=0

# run NAME COMMAND: runs COMMAND from the repo root. A pass prints one line; a failure prints
# the command's whole output, so the Stop hook's last 40 lines are about what failed and not
# pytest's report of a passing run. A failure is remembered; the other checks still run.
run() {
  local name=$1 cmd=$2 out
  [ -n "$cmd" ] || return 0
  if out=$(bash -c "$cmd" 2>&1); then
    echo "-- python $name passed: $cmd"
  else
    echo "== python $name FAILED: $cmd"
    printf '%s\n' "$out"
    echo "-- python $name FAILED"
    FAILED=1
  fi
}

# is_test PATH: PATH is a pytest test file by name.
is_test() {
  local base=${1##*/}
  [[ "$base" == test_*.py || "$base" == *_test.py ]]
}

if [ "$MODE" = full ]; then
  run lint "$LINT"
  run types "$TYPES"
  run tests "$TESTS"
  exit "$FAILED"
fi

# --- affected ----------------------------------------------------------------

changed=()
for f in "$@"; do
  [[ "$f" == *.py ]] && changed+=("$f")
done
if [ "${#changed[@]}" -eq 0 ]; then
  echo "== python: no .py file changed, nothing to check"
  exit 0
fi

run lint "$LINT"
run types "$TYPES"

[ -n "$TESTS" ] || exit "$FAILED"

# Every test file in the repo, tracked or new (gitignored ones left out).
mapfile -t all_tests < <(git -c core.quotePath=false ls-files --cached --others \
  --exclude-standard -- '*.py' | while IFS= read -r f; do is_test "$f" && echo "$f"; done)

declare -A selected=()
run_all=0
for f in "${changed[@]}"; do
  if is_test "$f"; then
    [ -f "$f" ] && selected["$f"]=1
    continue
  fi
  base=${f##*/}
  name=${base%.py}
  folder=""
  [[ "$f" == */* ]] && folder=${f%/*} && folder=${folder##*/}
  names=()
  [ "$name" != __init__ ] && [ "$name" != conftest ] && names+=("$name")
  [ -n "$folder" ] && names+=("$folder" "${folder%s}")

  found=0
  for t in "${all_tests[@]}"; do
    tbase=${t##*/}
    for n in "${names[@]}"; do
      if [ "$tbase" = "test_$n.py" ] || [ "$tbase" = "${n}_test.py" ]; then
        selected["$t"]=1
        found=1
      fi
    done
  done
  [ "$found" -eq 1 ] || run_all=1
done

if [ "$run_all" -eq 1 ]; then
  echo "== python: a changed module has no test file named after it, running all tests"
  run tests "$TESTS"
elif [ "${#selected[@]}" -gt 0 ]; then
  cmd=$TESTS
  while IFS= read -r t; do
    cmd+=" $(printf '%q' "$t")"
  done < <(printf '%s\n' "${!selected[@]}" | sort)
  run tests "$cmd"
else
  echo "== python: only deleted test files changed, no tests to run"
fi
exit "$FAILED"
