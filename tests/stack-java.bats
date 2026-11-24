#!/usr/bin/env bats
# Tests for plugins/dc-harness/stacks/java/stack-check.sh (contracts §1.2), through
# scripts/stack-check.sh. The project's commands are stubs (echo), so the tests see exactly what
# would run, without a JDK or Gradle installed.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  local main=api/src/main/java/com/acme/app test=api/src/test/java/com/acme/app
  mkdir -p "$main/user" "$main/config" "$test/user" "$test/support"
  touch api/gradlew "$main/Application.java" "$main/user/UserService.java" \
        "$main/user/UserController.java" "$main/config/SecurityConfig.java" \
        "$test/user/UserServiceTest.java" "$test/user/UserControllerTests.java" \
        "$test/user/UserControllerIT.java" "$test/support/TestData.java"
  git add -A && git commit --quiet -m project
}

setup() {
  load test_helper
  SC="$REPO_ROOT/plugins/dc-harness/scripts/stack-check.sh"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  commands '{"dir": "api", "lint": "echo LINT", "types": "echo TYPES", "tests": "echo ./gradlew test"}'
  M=api/src/main/java/com/acme/app
  T=api/src/test/java/com/acme/app
}

# commands JSON: makes java the only stack, with JSON as stackCommands.java.
commands() {
  jq -n --argjson c "$1" '{schemaVersion: 1, stack: ["java"], stackCommands: {java: $c}}' \
    > .harness/config.json
}

sc() {
  run --separate-stderr bash "$SC" "$@"
}

# tests_line: what the tests stub printed on its "passed" line, or nothing.
tests_line() {
  printf '%s\n' "$output" | sed -n 's/^-- java tests passed: echo //p'
}

@test "defaults: no lint, Gradle compiles main and test code, Gradle tests" {
  local d="$REPO_ROOT/plugins/dc-harness/stacks/java/default.json"
  [ "$(jq -r .lint "$d")" = "null" ]
  [ "$(jq -r .types "$d")" = "./gradlew testClasses --console=plain -q" ]
  [ "$(jq -r .tests "$d")" = "./gradlew test --console=plain" ]
}

@test "full: the default null lint is skipped; commands run in the stack's folder" {
  commands '{"dir": "api", "types": "test -f gradlew && echo TYPES", "tests": "echo TESTS"}'
  # lint is not set by the project, so the default (null) applies.
  sc full
  [ "$status" -eq 0 ]
  [ "$output" = $'-- java types passed: test -f gradlew && echo TYPES\n-- java tests passed: echo TESTS' ]
}

@test "affected: no .java file in the folder changed, nothing runs" {
  sc affected api/build.gradle api/src/main/resources/application.yml web/x.java
  [ "$status" -eq 0 ]
  [ "$output" = "== java: no .java file changed, nothing to check" ]
}

@test "affected: a class runs its Test, Tests and IT classes, with Gradle's --tests" {
  sc affected "$M/user/UserController.java"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-- java lint passed"* ]]
  [[ "$output" == *"-- java types passed"* ]]
  [ "$(tests_line)" = "./gradlew test --tests UserControllerIT --tests UserControllerTests" ]
}

@test "affected: a changed test class runs itself" {
  sc affected "$T/user/UserServiceTest.java" "$M/user/UserService.java"
  [ "$(tests_line)" = "./gradlew test --tests UserServiceTest" ]
}

@test "affected: a class with no test named after it runs all tests" {
  sc affected "$M/config/SecurityConfig.java"
  [[ "$output" == *"running all tests"* ]]
  [ "$(tests_line)" = "./gradlew test" ]
}

@test "affected: a test fixture under src/test runs all tests" {
  sc affected "$T/support/TestData.java"
  [ "$(tests_line)" = "./gradlew test" ]
}

@test "affected: Maven gets -Dtest with every class" {
  commands '{"dir": "api", "lint": null, "types": null, "tests": "echo ./mvnw -B test"}'
  sc affected "$M/user/UserController.java"
  [ "$(tests_line)" = "./mvnw -B test -Dtest=UserControllerIT,UserControllerTests -Dsurefire.failIfNoSpecifiedTests=false" ]
}

@test "affected: a deleted test class is not passed" {
  rm "$T/user/UserServiceTest.java"
  sc affected "$T/user/UserServiceTest.java"
  [ "$status" -eq 0 ]
  [ -z "$(tests_line)" ]
  [[ "$output" == *"only deleted test classes changed"* ]]
}

@test "two stacks: each checks only its own folder" {
  mkdir -p web
  jq -n '{schemaVersion: 1, stack: ["angular", "java"], stackCommands: {
    angular: {dir: "web", lint: "echo NG-LINT", types: null, tests: null},
    java: {dir: "api", lint: "echo J-LINT", types: null, tests: null}}}' > .harness/config.json
  sc affected "$M/user/UserService.java"
  [ "$status" -eq 0 ]
  [[ "$output" == *"== angular: no .ts or .html file changed, nothing to check"* ]]
  [[ "$output" == *"-- java lint passed: echo J-LINT"* ]]
}
