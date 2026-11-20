#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/stack-check.sh and stacks/python/stack-check.sh
# (contracts §1.2). The project's commands are stubs (echo), so the tests see exactly what
# would run, without ruff, mypy or pytest installed.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  mkdir -p app/services app/routers lib tests "my tests"
  touch app/__init__.py app/services/calc.py app/services/money.py app/routers/api.py \
        lib/parse.py lib/parse_test.py tests/conftest.py tests/test_calc.py \
        tests/test_service.py "my tests/test_space.py"
  git add -A && git commit --quiet -m project
}

setup() {
  load test_helper
  SC="$REPO_ROOT/plugins/dc-harness/scripts/stack-check.sh"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  commands '{"lint": "echo LINT", "types": "echo TYPES", "tests": "echo TESTS"}'
}

# commands JSON: sets the project's stackCommands.python.
commands() {
  jq -n --argjson c "$1" '{schemaVersion: 1, stackCommands: {python: $c}}' > .harness/config.json
}

sc() {
  run --separate-stderr bash "$SC" "$@"
}

# tests_line: the tests command that ran, as printed on its "passed" line ("TESTS ..."),
# or nothing. The stubs are `echo` commands, so the command shows what was appended.
tests_line() {
  printf '%s\n' "$output" | sed -n 's/^-- python tests passed: echo //p'
}

# ran NAME: the check NAME ran (passed or failed).
ran() {
  [[ "$output" == *"python $1 passed"* || "$output" == *"python $1 FAILED"* ]]
}

# --- Usage and errors (exit 2) ----------------------------------------------------

@test "bad usage exits 2" {
  sc
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: usage:"* ]]
  sc full app/x.py
  [ "$status" -eq 2 ]
  sc everything
  [ "$status" -eq 2 ]
}

@test "not onboarded exits 2" {
  rm .harness/config.json
  sc full
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: this repo isn't onboarded (no .harness/config.json)." ]
}

@test "an unknown stack exits 2 before anything runs" {
  echo '{"stack": ["python", "cobol"]}' > .harness/config.json
  sc full
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: unknown stack 'cobol': the plugin has no stacks/cobol/stack-check.sh." ]
  [ -z "$output" ]
}

# --- full ---------------------------------------------------------------------------

@test "full runs lint, types and tests as written, in that order" {
  sc full
  [ "$status" -eq 0 ]
  [ "$output" = $'-- python lint passed: echo LINT\n-- python types passed: echo TYPES\n-- python tests passed: echo TESTS' ]
}

@test "full: a null or empty command is skipped" {
  commands '{"lint": "", "types": null, "tests": "echo TESTS"}'
  sc full
  [ "$status" -eq 0 ]
  ! ran lint
  ! ran types
  [ "$(tests_line)" = "TESTS" ]
}

@test "full: a failing check fails the run, and the other checks still run" {
  commands '{"lint": "echo E501 too long; exit 3", "types": "echo TYPES", "tests": "echo TESTS"}'
  sc full
  [ "$status" -eq 1 ]
  # A failure shows the command's output; passing checks show one line each.
  [[ "$output" == *$'== python lint FAILED: echo E501 too long; exit 3\nE501 too long\n-- python lint FAILED'* ]]
  ran types
  [ "$(tests_line)" = "TESTS" ]
}

@test "commands run from the repo root, even when called from a subfolder" {
  commands '{"lint": "test -d .harness", "types": null, "tests": null}'
  cd app/services
  sc full
  [ "$status" -eq 0 ]
}

# --- affected ------------------------------------------------------------------------

@test "affected: no .py file changed, nothing runs" {
  sc affected README.md .gitignore
  [ "$status" -eq 0 ]
  [ "$output" = "== python: no .py file changed, nothing to check" ]
}

@test "affected: lint and types run as written, tests get the matching test file" {
  sc affected app/services/calc.py
  [ "$status" -eq 0 ]
  ran lint
  ran types
  # calc.py → test_calc.py; its folder services/ → test_service.py.
  [ "$(tests_line)" = "TESTS tests/test_calc.py tests/test_service.py" ]
}

@test "affected: a module matched only by its folder name, singular" {
  sc affected app/services/money.py
  [ "$(tests_line)" = "TESTS tests/test_service.py" ]
}

@test "affected: <name>_test.py next to the module" {
  sc affected lib/parse.py
  [ "$(tests_line)" = "TESTS lib/parse_test.py" ]
}

@test "affected: a changed test file is run itself" {
  sc affected tests/test_calc.py
  [ "$(tests_line)" = "TESTS tests/test_calc.py" ]
}

@test "affected: a deleted test file is not passed to the tests command" {
  rm tests/test_calc.py
  sc affected tests/test_calc.py
  [ "$status" -eq 0 ]
  [ -z "$(tests_line)" ]
  [[ "$output" == *"only deleted test files changed"* ]]
}

@test "affected: a new, untracked test file is found" {
  touch app/routers/test_api.py
  sc affected app/routers/api.py
  [ "$(tests_line)" = "TESTS app/routers/test_api.py" ]
}

@test "affected: a module with no test named after it runs all tests" {
  sc affected app/routers/api.py
  [[ "$output" == *"running all tests"* ]]
  [ "$(tests_line)" = "TESTS" ]
}

@test "affected: conftest.py runs all tests" {
  sc affected tests/conftest.py
  [ "$(tests_line)" = "TESTS" ]
}

@test "affected: test paths with spaces reach the command as one argument" {
  # Failing on purpose, so the command's output is printed.
  commands '{"lint": null, "types": null, "tests": "f() { printf \"<%s>\" \"$@\"; return 1; }; f TESTS"}'
  sc affected "my tests/test_space.py"
  [[ "$output" == *"<TESTS><my tests/test_space.py>"* ]]
}

@test "affected: a failing test command fails the run" {
  commands '{"lint": "echo LINT", "types": "echo TYPES", "tests": "echo 1 failed; exit 1"}'
  sc affected app/services/calc.py
  [ "$status" -eq 1 ]
  [[ "$output" == *"-- python tests FAILED"* ]]
}
