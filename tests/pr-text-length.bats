#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/pr-text-length.sh (contracts §4.5).

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  git switch --quiet -c feature/x
}

setup() {
  load test_helper
  PL="$REPO_ROOT/plugins/dc-harness/scripts/pr-text-length.sh"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  T=.tasks/feature/x
  stage finished
  echo '{"prTextMaxChars": 10}' > .harness/config.json
}

# pl ARGS...: runs pr-text-length.sh, output in $output / $stderr, exit code in $status.
pl() {
  run --separate-stderr bash "$PL" "$@"
}

@test "within the limit: prints chars and max, exit 0" {
  printf '123456789\n' > "$T/pr-text.md"
  pl
  [ "$status" -eq 0 ]
  [ "$output" = "chars=10 max=10" ]
}

@test "over the limit: one line with both numbers, exit 1" {
  printf '1234567890\n' > "$T/pr-text.md"
  pl
  [ "$status" -eq 1 ]
  [ "$output" = "pr-text.md has 11 characters; the limit is 10. Shorten it by 1 or more." ]
}

@test "counts characters, not bytes, and ignores \\r" {
  printf 'ñáé\r\nüö\r\n' > "$T/pr-text.md"
  pl
  [ "$status" -eq 0 ]
  [ "$output" = "chars=7 max=10" ]
}

@test "the default limit applies when the project doesn't set one" {
  echo '{ "schemaVersion": 1 }' > .harness/config.json
  printf 'text\n' > "$T/pr-text.md"
  pl
  [ "$status" -eq 0 ]
  [ "$output" = "chars=5 max=3000" ]
}

@test "works from a subfolder" {
  printf 'text\n' > "$T/pr-text.md"
  mkdir -p sub
  cd sub
  pl
  [ "$status" -eq 0 ]
}

@test "internal: no pr-text.md, no task, arguments" {
  rm "$T/pr-text.md"
  pl
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: no .tasks/feature/x/pr-text.md yet." ]
  pl extra
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: usage: pr-text-length.sh" ]
  git switch --quiet -c other
  pl
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: no task on branch other." ]
}

@test "internal: not onboarded" {
  rm .harness/config.json
  pl
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: this repo isn't onboarded"* ]]
}
