#!/usr/bin/env bash
# stacks/angular/stack-check.sh: the Angular / TypeScript checks (contracts §1.2). Called by
# scripts/stack-check.sh, never directly.
#
# Usage: stack-check.sh full
#        stack-check.sh affected <file>...
#
# Commands: lint (ESLint 9), types (tsc) and tests (ng test with Vitest by default; Karma,
# Jasmine or Jest through stackCommands.angular), from the project's stackCommands.angular or
# stacks/angular/default.json. An empty or null command is skipped. They run from
# stackCommands.angular.dir (relative to the repo root: the folder with angular.json), or from
# the repo root.
#
#   full      runs the three commands as written.
#   affected  does nothing when no .ts or .html file in the stack's folder changed. Otherwise
#             runs lint and types as written (whole project) and tests on the affected spec
#             files only:
#               - changed spec files (*.spec.ts) that still exist;
#               - for each other changed file <name>.ts or <name>.html: the spec files named
#                 <name>.spec.ts anywhere in the folder (user.service.ts →
#                 user.service.spec.ts; user.component.html → user.component.spec.ts).
#             If a changed file matches no spec (main.ts, app.config.ts, *.routes.ts, a test
#             setup file), all tests run: a miss must not let a change through.
#             The spec paths are added to the tests command as `--include=<path>` each when it
#             runs `ng test` (Vitest and Karma builders), and as plain paths otherwise
#             (`npx jest`, `npx vitest run`).
#
# Exit codes: 0 every check passed (or nothing to check), 1 a check failed.

set -u

# shellcheck source=SCRIPTDIR/../../scripts/lib/stack.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib/stack.sh"

MODE=${1:-}
shift
stack_init angular || exit $?

if [ "$MODE" = full ]; then
  stack_full
  exit "$FAILED"
fi

# --- affected ----------------------------------------------------------------

changed=()
for f in "$@"; do
  rel=$(stack_rel "$f") || continue
  [[ "$rel" == *.ts || "$rel" == *.html ]] && changed+=("$rel")
done
if [ "${#changed[@]}" -eq 0 ]; then
  echo "== angular: no .ts or .html file changed, nothing to check"
  exit 0
fi

stack_run lint "$LINT"
stack_run types "$TYPES"

[ -n "$TESTS" ] || exit "$FAILED"

# Every spec file in the stack's folder, tracked or new.
mapfile -t all_specs < <(stack_ls '*.spec.ts')

declare -A selected=()
run_all=0
for f in "${changed[@]}"; do
  if [[ "$f" == *.spec.ts ]]; then
    [ -f "$f" ] && selected["$f"]=1
    continue
  fi
  base=${f##*/}
  want="${base%.*}.spec.ts"
  found=0
  for t in "${all_specs[@]}"; do
    if [ "${t##*/}" = "$want" ]; then
      selected["$t"]=1
      found=1
    fi
  done
  [ "$found" -eq 1 ] || run_all=1
done

if [ "$run_all" -eq 1 ]; then
  echo "== angular: a changed file has no spec named after it, running all tests"
  stack_run tests "$TESTS"
elif [ "${#selected[@]}" -gt 0 ]; then
  cmd=$TESTS
  while IFS= read -r t; do
    if [[ "$TESTS" == *"ng test"* ]]; then
      cmd+=" $(printf '%q' "--include=$t")"
    else
      cmd+=" $(printf '%q' "$t")"
    fi
  done < <(printf '%s\n' "${!selected[@]}" | sort)
  stack_run tests "$cmd"
else
  echo "== angular: only deleted spec files changed, no tests to run"
fi
exit "$FAILED"
