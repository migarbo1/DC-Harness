#!/usr/bin/env bash
# stacks/java/stack-check.sh: the Java / Spring Boot checks (contracts §1.2). Called by
# scripts/stack-check.sh, never directly.
#
# Usage: stack-check.sh full
#        stack-check.sh affected <file>...
#
# Commands: lint (none by default), types (compiling main and test code) and tests, with the
# Gradle wrapper, from the project's stackCommands.java or stacks/java/default.json. An empty
# or null command is skipped. They run from stackCommands.java.dir (relative to the repo root:
# the folder with gradlew), or from the repo root.
#
#   full      runs the commands as written.
#   affected  does nothing when no .java file in the stack's folder changed. Otherwise runs
#             lint and types as written (whole project) and tests on the affected test classes
#             only:
#               - changed test classes that still exist: *Test.java, *Tests.java, *IT.java;
#               - for each other changed class <Name>.java: the test classes named
#                 <Name>Test, <Name>Tests or <Name>IT anywhere in the folder.
#             If a changed class matches no test class (a configuration class, a test
#             fixture, an entity nobody named a test after), all tests run: a miss must not
#             let a change through.
#             The classes are added to the tests command as `--tests <Class>` each when it
#             runs Gradle, and as `-Dtest=<Class>,… -Dsurefire.failIfNoSpecifiedTests=false`
#             otherwise (Maven).
#
# Exit codes: 0 every check passed (or nothing to check), 1 a check failed.

set -u

# shellcheck source=SCRIPTDIR/../../scripts/lib/stack.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/stack.sh"

MODE=${1:-}
shift
stack_init java || exit $?

if [ "$MODE" = full ]; then
  stack_full
  exit "$FAILED"
fi

# is_test PATH: PATH is a test class by name. Other files under src/test/ (fixtures, test
# configuration) are not: no test is named after them, so they run all tests.
is_test() {
  local base=${1##*/}
  [[ "$base" == *Test.java || "$base" == *Tests.java || "$base" == *IT.java ]]
}

# --- affected ----------------------------------------------------------------

changed=()
for f in "$@"; do
  rel=$(stack_rel "$f") || continue
  [[ "$rel" == *.java ]] && changed+=("$rel")
done
if [ "${#changed[@]}" -eq 0 ]; then
  echo "== java: no .java file changed, nothing to check"
  exit 0
fi

stack_run lint "$LINT"
stack_run types "$TYPES"

[ -n "$TESTS" ] || exit "$FAILED"

# Every test class in the stack's folder, tracked or new.
mapfile -t all_tests < <(stack_ls '*.java' | while IFS= read -r f; do is_test "$f" && echo "$f"; done)

declare -A selected=()
run_all=0
for f in "${changed[@]}"; do
  base=${f##*/}
  name=${base%.java}
  if is_test "$f"; then
    [ -f "$f" ] && selected["$name"]=1
    continue
  fi
  found=0
  for t in "${all_tests[@]}"; do
    tname=${t##*/}
    tname=${tname%.java}
    if [ "$tname" = "${name}Test" ] || [ "$tname" = "${name}Tests" ] || [ "$tname" = "${name}IT" ]; then
      selected["$tname"]=1
      found=1
    fi
  done
  [ "$found" -eq 1 ] || run_all=1
done

if [ "$run_all" -eq 1 ]; then
  echo "== java: a changed class has no test class named after it, running all tests"
  stack_run tests "$TESTS"
elif [ "${#selected[@]}" -gt 0 ]; then
  mapfile -t classes < <(printf '%s\n' "${!selected[@]}" | sort)
  # Class names are Java identifiers, so they go into the command unquoted.
  cmd=$TESTS
  if [[ "$TESTS" == *gradle* ]]; then
    for c in "${classes[@]}"; do
      cmd+=" --tests $c"
    done
  else
    cmd+=" -Dtest=$(IFS=,; printf '%s' "${classes[*]}") -Dsurefire.failIfNoSpecifiedTests=false"
  fi
  stack_run tests "$cmd"
else
  echo "== java: only deleted test classes changed, no tests to run"
fi
exit "$FAILED"
