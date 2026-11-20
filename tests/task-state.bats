#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/task-state.sh (contracts §4).
# For every check: one case that passes and one that refuses, with the exact refusal line.

bats_require_minimum_version 1.5.0   # run --separate-stderr

# One template repo per file, copied for each test: git init + commit is the slow part.
setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  git switch --quiet -c feature/x
}

setup() {
  load test_helper
  TS="$REPO_ROOT/plugins/dc-harness/scripts/task-state.sh"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  T=.tasks/feature/x
}

# ts ARGS...: runs task-state.sh, output in $output / $stderr, exit code in $status.
ts() {
  run --separate-stderr bash "$TS" "$@"
}

# hash FILE: SHA-256 of FILE's bytes.
hash() {
  sha256sum < "$1" | cut -d' ' -f1
}

# stage NAME: builds the task folder of feature/x up to NAME, as the skills and hooks would
# leave it. Each stage includes the ones before it.
#   started → spec → spec-approved → planned → plan-approved → cp1 → cp2 → assessed → finished
stage() {
  local target=$1 s
  for s in started spec spec-approved planned plan-approved cp1 cp2 assessed finished; do
    case "$s" in
      started)
        mkdir -p "$T"
        jq -n --arg c "$(git rev-parse HEAD)" '{schemaVersion: 1, branch: "feature/x",
          commitRef: $c, startedAt: "2026-11-20T10:00:00Z", step: "start-task", gate: "spec",
          planSession: null}' > "$T/state.json" ;;
      spec)
        printf '# Spec\n' > "$T/spec.md" ;;
      spec-approved)
        jq -n --arg h "$(hash "$T/spec.md")" '{schemaVersion: 1, spec: {sha256: $h}}' \
          > "$T/approvals.json" ;;
      planned)
        printf '# Plan\n\n## CP1: First\n### Tasks\n\n## CP2: Second\n' > "$T/plan.md"
        jq '.step = "plan" | .gate = "plan" | .planSession = "sess-plan"' "$T/state.json" \
          > "$T/s" && mv "$T/s" "$T/state.json" ;;
      plan-approved)
        jq --arg h "$(hash "$T/plan.md")" '.plan = {sha256: $h}' "$T/approvals.json" \
          > "$T/a" && mv "$T/a" "$T/approvals.json" ;;
      cp1)
        printf '## CP1: First\n### Changes\n' > "$T/implementation-notes.md" ;;
      cp2)
        printf '\n## CP2: Second\n' >> "$T/implementation-notes.md" ;;
      assessed)
        printf '# Assessment\n\nScore: 3/4 (passed)\n' > "$T/assessment.md" ;;
      finished)
        printf 'PR text\n' > "$T/pr-text.md" ;;
    esac
    [ "$s" = "$target" ] && return 0
  done
}

# state KEY: a value from feature/x's state.json.
state() {
  jq -r ".$1" "$T/state.json" | tr -d '\r'
}

# --- Arguments and internal errors (exit 2) ----------------------------------

@test "internal: missing or unknown skill" {
  ts
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: usage:"* ]]
  [ -z "$output" ]
  ts deploy sess
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: unknown skill 'deploy'."* ]]
}

@test "internal: empty session ID, or \${CLAUDE_SESSION_ID} not replaced" {
  ts plan ""
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: no session ID"* ]]
  ts plan '${CLAUDE_SESSION_ID}'
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: no session ID"* ]]
}

@test "internal: a checkpoint on another skill, or a bad checkpoint" {
  ts plan sess CP1
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: only implement takes a checkpoint."* ]]
  ts implement sess CPX
  [ "$status" -eq 2 ]
  [[ "$stderr" == "dc: internal: bad checkpoint 'CPX'"* ]]
}

@test "internal: not a git repository" {
  mkdir "$BATS_TEST_TMPDIR/plain" && cd "$BATS_TEST_TMPDIR/plain"
  ts plan sess
  [ "$status" -eq 2 ]
  [ "$stderr" = "dc: internal: not a git repository." ]
}

# --- G1: onboarded ------------------------------------------------------------

@test "G1 refuses when .harness/config.json is missing" {
  rm .harness/config.json
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "This repo isn't onboarded for DC-Harness (no .harness/config.json)." ]
}

# --- G2: detached HEAD --------------------------------------------------------

@test "G2 refuses on a detached HEAD" {
  git switch --quiet --detach
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "HEAD is detached. Check out a branch first." ]
}

# --- G3: the branch has a task -------------------------------------------------

@test "G3 refuses when no task exists" {
  ts plan sess
  [ "$status" -eq 1 ]
  [ "$output" = "No task on this branch. Start one with /dc:start-task <description>." ]
}

@test "G3 refuses on another branch while a task is open, naming its branch" {
  stage started
  git switch --quiet -c feature/other
  ts plan sess
  [ "$status" -eq 1 ]
  [ "$output" = "The open task is on feature/x. Switch back to it." ]
}

@test "G3 works from a subfolder of the repo" {
  stage spec-approved
  mkdir -p src/deep && cd src/deep
  ts plan sess
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/x" ]
}

# --- G4: not finished ----------------------------------------------------------

@test "G4 refuses plan, implement and assessment on a finished task" {
  stage finished
  for skill in plan implement assessment; do
    ts "$skill" sess
    [ "$status" -eq 1 ]
    [ "$output" = "Task finished (pr-text.md exists). Start a new task on a new branch." ]
  done
}

# --- start-task ----------------------------------------------------------------

@test "start-task: creates state.json and prints task-dir and commit-ref" {
  ts start-task sess-1
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/x" ]
  [ "${lines[1]}" = "commit-ref=$(git rev-parse HEAD)" ]
  [ "$(state branch)" = "feature/x" ]
  [ "$(state commitRef)" = "$(git rev-parse HEAD)" ]
  [ "$(state step)" = "start-task" ]
  [ "$(state gate)" = "spec" ]
  [ "$(state planSession)" = "null" ]
  [[ "$(state startedAt)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "start-task: a branch name with special characters gets a safe folder" {
  # git allows ñ and #, but not spaces, in branch names.
  git switch --quiet -c 'feature/añadir#2'
  ts start-task sess
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/a-adir-2" ]
  [ "$(jq -r .branch '.tasks/feature/a-adir-2/state.json' | tr -d '\r')" = 'feature/añadir#2' ]
}

@test "S1 refuses while a task is open on another branch" {
  stage started
  git switch --quiet -c feature/y
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "Task open on branch feature/x. Finish it with /dc:pr-text first." ]
}

@test "S1 passes when the other task is finished" {
  stage finished
  git switch --quiet -c feature/y
  ts start-task sess
  [ "$status" -eq 0 ]
}

@test "S2 refuses on a default protected branch" {
  git switch --quiet main
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "Branch main is protected. Create a task branch first." ]
}

@test "S2 treats entries as glob patterns" {
  git switch --quiet main
  echo '{"protectedBranches": ["release/*"]}' > .harness/config.json
  git commit --quiet -am cfg
  git switch --quiet -c release/1.2
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "Branch release/1.2 is protected. Create a task branch first." ]
  # main is no longer protected: the project's list replaces the default one.
  git switch --quiet main
  ts start-task sess
  [ "$status" -eq 0 ]
}

@test "S3 refuses when the folder already holds a finished task" {
  stage finished
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = ".tasks/feature/x/ already holds a finished task. Delete it to start a new task here." ]
}

@test "S4 refuses with a modified file" {
  echo "edit" >> README.md
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "Working tree not clean. Commit or stash your changes, and discard or gitignore untracked files." ]
  [ ! -e .tasks ]
}

@test "S4 refuses with an untracked file" {
  echo "stray" > stray.py
  ts start-task sess
  [ "$status" -eq 1 ]
  [ "$output" = "Working tree not clean. Commit or stash your changes, and discard or gitignore untracked files." ]
}

# --- plan ----------------------------------------------------------------------

@test "plan: sets step, gate and planSession, prints task-dir only" {
  stage spec-approved
  ts plan sess-plan
  [ "$status" -eq 0 ]
  [ "$output" = "task-dir=.tasks/feature/x" ]
  [ "$(state step)" = "plan" ]
  [ "$(state gate)" = "plan" ]
  [ "$(state planSession)" = "sess-plan" ]
}

@test "P1 refuses without spec.md" {
  stage started
  ts plan sess
  [ "$status" -eq 1 ]
  [ "$output" = "No spec.md. Run /dc:start-task first." ]
}

@test "P2 refuses when the spec isn't approved, with the configured phrase" {
  stage spec
  echo '{"specApprovalPhrase": ["Especificación acordada", "Spec OK"]}' > .harness/config.json
  ts plan sess
  [ "$status" -eq 1 ]
  [ "$output" = "Spec not approved: type 'Especificación acordada'." ]
}

@test "P3 refuses when spec.md changed after approval, and leaves state.json alone" {
  stage spec-approved
  echo "one more line" >> "$T/spec.md"
  before=$(cat "$T/state.json")
  ts plan sess
  [ "$status" -eq 1 ]
  [ "$output" = "spec.md changed since approval: review it and type 'Specification agreed' again." ]
  [ "$(cat "$T/state.json")" = "$before" ]
}

# --- implement -----------------------------------------------------------------

@test "implement: in a new session, runs CP1 and closes the gate" {
  stage plan-approved
  ts implement sess-new
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/x" ]
  [ "${lines[1]}" = "checkpoint=CP1" ]
  [ "$(state step)" = "implement" ]
  [ "$(state gate)" = "null" ]
  [ "$(state planSession)" = "sess-plan" ]
}

@test "implement: after CP1 is done, the next one is CP2" {
  stage cp1
  ts implement sess-new
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "checkpoint=CP2" ]
}

@test "I1 refuses without plan.md" {
  stage spec-approved
  ts implement sess
  [ "$status" -eq 1 ]
  [ "$output" = "No plan.md. Run /dc:plan first." ]
}

@test "I2 refuses when the plan isn't approved" {
  stage planned
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "Plan not approved: type 'Plan agreed'." ]
}

@test "I3 refuses when plan.md changed after approval" {
  stage plan-approved
  echo "## CP3: Sneaked in" >> "$T/plan.md"
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "plan.md changed since approval: review it and type 'Plan agreed' again." ]
}

@test "I4 refuses in the session that wrote the plan, and leaves state.json alone" {
  stage plan-approved
  before=$(cat "$T/state.json")
  ts implement sess-plan
  [ "$status" -eq 1 ]
  [ "$output" = "This session wrote the plan. Run /clear, then /dc:implement." ]
  [ "$(cat "$T/state.json")" = "$before" ]
}

# approve_plan TEXT: replaces plan.md with TEXT (printf format) and approves it.
approve_plan() {
  # shellcheck disable=SC2059
  printf "$1" > "$T/plan.md"
  jq --arg h "$(hash "$T/plan.md")" '.plan = {sha256: $h}' "$T/approvals.json" \
    > "$T/a" && mv "$T/a" "$T/approvals.json"
}

@test "I5 refuses a plan with no checkpoint headings" {
  stage plan-approved
  approve_plan '# Plan\n\n## Step 1: no CP prefix\n### CP1: wrong level\n'
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "plan.md has no checkpoints (## CP<n>: <title>). Run /dc:plan again." ]
}

@test "I5 refuses a gap in the numbering" {
  stage plan-approved
  approve_plan '## CP1: a\n## CP3: c\n'
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "plan.md checkpoints must be numbered CP1, CP2, … in order. Run /dc:plan again." ]
}

@test "I5 refuses checkpoints out of order" {
  stage plan-approved
  approve_plan '## CP2: b\n## CP1: a\n'
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "plan.md checkpoints must be numbered CP1, CP2, … in order. Run /dc:plan again." ]
}

@test "I5 reads a plan.md with CRLF line endings" {
  stage plan-approved
  approve_plan '## CP1: a\r\n### Tasks\r\n## CP2: b\r\n'
  ts implement sess-new
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "checkpoint=CP1" ]
}

@test "I6 refuses when every checkpoint is done" {
  stage cp2
  ts implement sess-new
  [ "$status" -eq 1 ]
  [ "$output" = "All checkpoints done. Run /dc:assessment." ]
}

@test "I6: a notes entry counts by its ID alone (## CP1 with no title, CRLF)" {
  stage plan-approved
  printf '## CP1\r\n### Changes\r\n' > "$T/implementation-notes.md"
  ts implement sess-new
  [ "${lines[1]}" = "checkpoint=CP2" ]
}

@test "I6: ## CP10 does not count as ## CP1" {
  stage plan-approved
  printf '## CP10: other\n' > "$T/implementation-notes.md"
  ts implement sess-new
  [ "${lines[1]}" = "checkpoint=CP1" ]
}

@test "I7 refuses a checkpoint that isn't the next one" {
  stage plan-approved
  ts implement sess-new CP2
  [ "$status" -eq 1 ]
  [ "$output" = "The next checkpoint is CP1. Run /dc:implement or /dc:implement CP1." ]
}

@test "I7 accepts the next checkpoint as CP2, cp2 or 2" {
  stage cp1
  for cp in CP2 cp2 2 CP02; do
    ts implement sess-new "$cp"
    [ "$status" -eq 0 ]
    [ "${lines[1]}" = "checkpoint=CP2" ]
  done
}

# --- assessment ----------------------------------------------------------------

@test "assessment: opens the assessment gate, prints commit-ref and questions" {
  stage cp2
  echo '{"assessment": {"numQuestions": 6}}' > .harness/config.json
  ts assessment sess
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/x" ]
  [ "${lines[1]}" = "commit-ref=$(state commitRef)" ]
  [ "${lines[2]}" = "questions=6" ]
  [ "$(state step)" = "assessment" ]
  [ "$(state gate)" = "assessment" ]
}

@test "A1 refuses without implementation-notes.md" {
  stage plan-approved
  ts assessment sess
  [ "$status" -eq 1 ]
  [ "$output" = "No implementation-notes.md. Run /dc:implement first." ]
}

@test "A2 refuses and lists the checkpoints not done" {
  stage plan-approved
  approve_plan '## CP1: a\n## CP2: b\n## CP3: c\n'
  printf '## CP2: b\n' > "$T/implementation-notes.md"
  ts assessment sess
  [ "$status" -eq 1 ]
  [ "$output" = "Checkpoints not done: CP1, CP3. Run /dc:implement." ]
}

# --- pr-text -------------------------------------------------------------------

@test "pr-text: closes the gate after the assessment" {
  stage assessed
  ts pr-text sess
  [ "$status" -eq 0 ]
  [ "$output" = "task-dir=.tasks/feature/x" ]
  [ "$(state step)" = "pr-text" ]
  [ "$(state gate)" = "null" ]
}

@test "pr-text: can be re-run on a finished task" {
  stage finished
  ts pr-text sess
  [ "$status" -eq 0 ]
}

@test "R1 refuses without spec.md" {
  stage assessed
  rm "$T/spec.md"
  ts pr-text sess
  [ "$status" -eq 1 ]
  [ "$output" = "No spec.md. Run /dc:start-task first." ]
}

@test "R2 refuses without assessment.md" {
  stage cp2
  ts pr-text sess
  [ "$status" -eq 1 ]
  [ "$output" = "Assessment not finished. Run /dc:assessment." ]
}

@test "R2 refuses an assessment.md whose score line doesn't match the marker" {
  stage cp2
  printf 'Score: 3 of 4 (passed)\nscore: 3/4 (passed)\n' > "$T/assessment.md"
  ts pr-text sess
  [ "$status" -eq 1 ]
  [ "$output" = "Assessment not finished. Run /dc:assessment." ]
}

@test "R2 accepts 'not passed' and CRLF" {
  stage cp2
  printf '# A\r\nScore: 1/4 (not passed)\r\n' > "$T/assessment.md"
  ts pr-text sess
  [ "$status" -eq 0 ]
}

# --- Re-running an earlier skill (§4.4) ---------------------------------------

@test "re-running plan after implement reopens the plan gate with the new session" {
  stage cp1
  ts plan sess-replan
  [ "$status" -eq 0 ]
  [ "$(state step)" = "plan" ]
  [ "$(state gate)" = "plan" ]
  [ "$(state planSession)" = "sess-replan" ]
}
