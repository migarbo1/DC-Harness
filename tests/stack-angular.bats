#!/usr/bin/env bats
# Tests for plugins/dc-harness/stacks/angular/stack-check.sh (contracts §1.2), through
# scripts/stack-check.sh. The project's commands are stubs (echo), so the tests see exactly what
# would run, without node, ESLint, tsc or a test runner installed.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  mkdir -p web/src/app/user web/src/app/shared
  touch web/angular.json web/src/main.ts web/src/app/app.config.ts \
        web/src/app/user/user.component.ts web/src/app/user/user.component.html \
        web/src/app/user/user.component.spec.ts web/src/app/user/user.service.ts \
        web/src/app/user/user.service.spec.ts web/src/app/shared/format.pipe.ts \
        web/src/app/shared/format.pipe.spec.ts
  git add -A && git commit --quiet -m project
}

setup() {
  load test_helper
  SC="$REPO_ROOT/plugins/dc-harness/scripts/stack-check.sh"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  commands '{"dir": "web", "lint": "echo LINT", "types": "echo TYPES", "tests": "echo ng test --watch=false"}'
}

# commands JSON: makes angular the only stack, with JSON as stackCommands.angular.
commands() {
  jq -n --argjson c "$1" '{schemaVersion: 1, stack: ["angular"], stackCommands: {angular: $c}}' \
    > .harness/config.json
}

sc() {
  run --separate-stderr bash "$SC" "$@"
}

# tests_line: what the tests stub printed on its "passed" line, or nothing.
tests_line() {
  printf '%s\n' "$output" | sed -n 's/^-- angular tests passed: echo //p'
}

@test "defaults: ESLint, tsc on the app and spec configs, ng test with Vitest" {
  local d="$REPO_ROOT/plugins/dc-harness/stacks/angular/default.json"
  [ "$(jq -r .lint "$d")" = "npx eslint ." ]
  [ "$(jq -r .types "$d")" = "npx tsc --noEmit -p tsconfig.app.json && npx tsc --noEmit -p tsconfig.spec.json" ]
  [ "$(jq -r .tests "$d")" = "npx ng test --watch=false" ]
}

@test "full runs lint, types and tests in the stack's folder" {
  commands '{"dir": "web", "lint": "test -f angular.json && echo LINT", "types": "echo TYPES", "tests": "echo TESTS"}'
  sc full
  [ "$status" -eq 0 ]
  [ "$output" = $'-- angular lint passed: test -f angular.json && echo LINT\n-- angular types passed: echo TYPES\n-- angular tests passed: echo TESTS' ]
}

@test "a dir that doesn't exist fails the check" {
  commands '{"dir": "frontend"}'
  sc full
  [ "$status" -eq 1 ]
  [ "$output" = "== angular FAILED: folder 'frontend' (stackCommands.angular.dir) not found" ]
}

@test "affected: no .ts or .html file in the folder changed, nothing runs" {
  sc affected web/src/styles.scss web/package.json README.md other/x.ts
  [ "$status" -eq 0 ]
  [ "$output" = "== angular: no .ts or .html file changed, nothing to check" ]
}

@test "affected: a service runs its spec, with ng test's --include" {
  sc affected web/src/app/user/user.service.ts
  [ "$status" -eq 0 ]
  [[ "$output" == *"-- angular lint passed"* ]]
  [[ "$output" == *"-- angular types passed"* ]]
  [ "$(tests_line)" = "ng test --watch=false --include=src/app/user/user.service.spec.ts" ]
}

@test "affected: a template runs its component's spec; a changed spec runs itself" {
  sc affected web/src/app/user/user.component.html web/src/app/shared/format.pipe.spec.ts
  [ "$(tests_line)" = "ng test --watch=false --include=src/app/shared/format.pipe.spec.ts --include=src/app/user/user.component.spec.ts" ]
}

@test "affected: a file with no spec named after it runs all tests" {
  sc affected web/src/app/app.config.ts
  [[ "$output" == *"running all tests"* ]]
  [ "$(tests_line)" = "ng test --watch=false" ]
}

@test "affected: a runner other than ng test gets plain paths (Jest)" {
  commands '{"dir": "web", "lint": null, "types": null, "tests": "echo jest"}'
  sc affected web/src/app/user/user.service.ts
  [ "$(tests_line)" = "jest src/app/user/user.service.spec.ts" ]
}

@test "affected: a new, untracked spec is found; a deleted spec is not passed" {
  touch web/src/main.spec.ts
  rm web/src/app/user/user.service.spec.ts
  sc affected web/src/main.ts web/src/app/user/user.service.spec.ts
  [ "$(tests_line)" = "ng test --watch=false --include=src/main.spec.ts" ]
}

@test "affected: a failing test command fails the run" {
  commands '{"dir": "web", "lint": null, "types": null, "tests": "echo 1 failed; exit 1"}'
  sc affected web/src/app/user/user.service.ts
  [ "$status" -eq 1 ]
  [[ "$output" == *"-- angular tests FAILED"* ]]
}
