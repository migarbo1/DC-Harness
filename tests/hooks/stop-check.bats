#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/hooks/stop-check.sh (contracts §5.5), run on the
# recorded Stop payload. stack-check.sh is replaced by a stub (DC_STACK_CHECK) that logs its
# arguments and passes or fails on demand.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load ../test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  mkdir app && echo "x = 1" > app/main.py && echo "y = 2" > app/util.py
  git add app && git commit --quiet -m app
  git switch --quiet -c feature/x
}

setup() {
  load ../test_helper
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  T=.tasks/feature/x

  # The stub: logs "affected <files>" to calls.log, prints stub.out, exits with stub.rc.
  STUB_DIR="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB_DIR"
  echo 0 > "$STUB_DIR/rc"
  : > "$STUB_DIR/out"
  cat > "$STUB_DIR/stack-check.sh" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$STUB_DIR/calls.log"
cat "$STUB_DIR/out"
exit "\$(cat "$STUB_DIR/rc")"
EOF
  export DC_STACK_CHECK="$STUB_DIR/stack-check.sh"
}

implementing() {
  stage cp1
  set_state '.step = "implement" | .gate = null'
}

stop() {
  hook stop-check stop
}

# calls: how many times the stub ran.
calls() {
  if [ -f "$STUB_DIR/calls.log" ]; then wc -l < "$STUB_DIR/calls.log" | tr -d ' '; else echo 0; fi
}

# last_call: the stub's last arguments.
last_call() {
  tail -n 1 "$STUB_DIR/calls.log"
}

# --- When it runs ----------------------------------------------------------------

@test "silent when the branch has no task" {
  echo "z = 3" >> app/main.py
  stop
  [ "$status" -eq 0 ] && [ -z "$output" ]
  [ "$(calls)" = 0 ]
}

@test "outside implement (plan step) nothing runs, even with changes" {
  stage planned
  echo "z = 3" >> app/main.py
  stop
  [ -z "$output" ]
  [ "$(calls)" = 0 ]
}

@test "implement, nothing changed since the commit-ref: nothing runs" {
  implementing
  stop
  [ -z "$output" ]
  [ "$(calls)" = 0 ]
  [ ! -e "$T/stop-check.json" ]
}

@test "changes only in .tasks/ don't count" {
  implementing
  echo "more notes" >> "$T/implementation-notes.md"
  stop
  [ "$(calls)" = 0 ]
}

# --- Passing checks ---------------------------------------------------------------

@test "a change runs the affected checks on the changed files, and a pass is recorded" {
  implementing
  echo "z = 3" >> app/main.py
  stop
  [ "$status" -eq 0 ] && [ -z "$output" ]
  [ "$(calls)" = 1 ]
  [ "$(last_call)" = "affected app/main.py" ]
  tree=$(source "$LIB_DIR/git.sh" && git_worktree_tree)
  [ "$(jq -r .lastPassedTree "$T/stop-check.json" | tr -d '\r')" = "$tree" ]
  [ "$(jq -r .schemaVersion "$T/stop-check.json" | tr -d '\r')" = "1" ]
}

@test "new, modified and deleted files are all passed, untracked included" {
  implementing
  echo "z = 3" >> app/main.py
  rm app/util.py
  echo "def f(): ..." > app/new.py
  stop
  [ "$(last_call)" = "affected app/main.py app/new.py app/util.py" ]
}

@test "after a pass, the next stop with no new change runs nothing" {
  implementing
  echo "z = 3" >> app/main.py
  stop
  stop
  [ "$(calls)" = 1 ]
}

@test "after a pass, only files changed since then are checked" {
  implementing
  echo "z = 3" >> app/main.py
  stop
  echo "w = 4" >> app/util.py
  stop
  [ "$(calls)" = 2 ]
  [ "$(last_call)" = "affected app/util.py" ]
}

# --- Failing checks ---------------------------------------------------------------

@test "a failure blocks the stop with the last 40 lines, and nothing is recorded" {
  implementing
  echo 1 > "$STUB_DIR/rc"
  for i in $(seq 1 60); do echo "line $i"; done > "$STUB_DIR/out"
  echo "z = 3" >> app/main.py
  stop
  [ "$status" -eq 0 ]
  [ "$(out .decision)" = "block" ]
  reason=$(out .reason)
  [[ "$reason" == "Checks failed. Fix them before finishing:"$'\n'"line 21"* ]]
  [[ "$reason" == *"line 60" ]]
  [[ "$reason" != *"line 20"$'\n'* ]]
  [ ! -e "$T/stop-check.json" ]
}

@test "blocked until it passes: every stop re-checks everything since the last pass" {
  implementing
  echo 1 > "$STUB_DIR/rc"
  echo "z = 3" >> app/main.py
  stop
  [ "$(out .decision)" = "block" ]
  # The agent fixes it, touching a second file.
  echo 0 > "$STUB_DIR/rc"
  echo "w = 4" >> app/util.py
  stop
  [ -z "$output" ]
  [ "$(last_call)" = "affected app/main.py app/util.py" ]
  [ -e "$T/stop-check.json" ]
}

@test "a failure blocks again on the next stop even with no new change" {
  implementing
  echo 1 > "$STUB_DIR/rc"
  echo "z = 3" >> app/main.py
  stop
  stop
  [ "$(calls)" = 2 ]
  [ "$(out .decision)" = "block" ]
}

# --- Fail open ---------------------------------------------------------------------

@test "fails open when stack-check.sh is missing" {
  implementing
  export DC_STACK_CHECK="$STUB_DIR/missing.sh"
  echo "z = 3" >> app/main.py
  stop
  [ "$status" -eq 0 ]
  [ "$(out .systemMessage)" = "DC-Harness hook failed: run doctor.sh." ]
  [ "$(out 'has("decision")')" = "false" ]
}
