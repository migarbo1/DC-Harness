#!/usr/bin/env bash
# stacks/python/stack-check.sh: the Python checks (contracts §1.2). Called by
# scripts/stack-check.sh, never directly.
#
# Usage: stack-check.sh full
#        stack-check.sh affected <file>...
#
# Commands: lint, types and tests, from the project's stackCommands.python or
# stacks/python/default.json. An empty or null command is skipped. They run from
# stackCommands.python.dir (relative to the repo root), or from the repo root.
#
#   full      runs the three commands as written.
#   affected  does nothing when no .py file in the stack's folder changed. Otherwise runs lint
#             and types as written (whole project) and tests on the affected test files only,
#             appended to the tests command:
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

# shellcheck source=SCRIPTDIR/../../scripts/lib/stack.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/stack.sh"

MODE=${1:-}
shift
stack_init python || exit $?

if [ "$MODE" = full ]; then
  stack_full
  exit "$FAILED"
fi

# is_test PATH: PATH is a pytest test file by name.
is_test() {
  local base=${1##*/}
  [[ "$base" == test_*.py || "$base" == *_test.py ]]
}

# --- affected ----------------------------------------------------------------

changed=()
for f in "$@"; do
  rel=$(stack_rel "$f") || continue
  [[ "$rel" == *.py ]] && changed+=("$rel")
done
if [ "${#changed[@]}" -eq 0 ]; then
  echo "== python: no .py file changed, nothing to check"
  exit 0
fi

stack_run lint "$LINT"
stack_run types "$TYPES"

[ -n "$TESTS" ] || exit "$FAILED"

# Every test file in the stack's folder, tracked or new.
mapfile -t all_tests < <(stack_ls '*.py' | while IFS= read -r f; do is_test "$f" && echo "$f"; done)

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
  stack_run tests "$TESTS"
elif [ "${#selected[@]}" -gt 0 ]; then
  cmd=$TESTS
  while IFS= read -r t; do
    cmd+=" $(printf '%q' "$t")"
  done < <(printf '%s\n' "${!selected[@]}" | sort)
  stack_run tests "$cmd"
else
  echo "== python: only deleted test files changed, no tests to run"
fi
exit "$FAILED"
