#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/lib/task.sh (contracts §2.1 and §2.6).

setup() {
  load ../test_helper
  source "$LIB_DIR/git.sh"
  source "$LIB_DIR/task.sh"
  make_repo
  ROOT=$(git_root)
}

# new_task BRANCH [finished]: writes a task folder for BRANCH, as task-state.sh would.
new_task() {
  local dir
  dir="$ROOT/$(task_rel_dir "$1")"
  mkdir -p "$dir"
  json_update "$dir/state.json" '{schemaVersion: 1, branch: $b}' --arg b "$1"
  if [ "${2:-}" = finished ]; then
    echo "PR text" > "$dir/pr-text.md"
  fi
}

# --- task_onboarded ---------------------------------------------------------

@test "task_onboarded fails without .harness/config.json" {
  ! task_onboarded "$ROOT"
}

@test "task_onboarded succeeds with .harness/config.json" {
  onboard
  task_onboarded "$ROOT"
}

# --- task_folder / task_rel_dir (§2.1) ---------------------------------------

@test "task_folder keeps a plain branch name" {
  [ "$(task_folder main)" = "main" ]
  [ "$(task_folder fix-1.2_x)" = "fix-1.2_x" ]
}

@test "task_folder keeps / so each part is a nested folder" {
  [ "$(task_folder feature/login-rate-limit)" = "feature/login-rate-limit" ]
}

@test "task_folder replaces other characters with -, one per character" {
  [ "$(task_folder 'feature/añadir login#2')" = "feature/a-adir-login-2" ]
}

@test "task_folder replaces shell-special characters" {
  [ "$(task_folder 'a$b"c*d')" = "a-b-c-d" ]
}

@test "task_rel_dir is .tasks/<folder>" {
  [ "$(task_rel_dir 'feature/añadir login#2')" = ".tasks/feature/a-adir-login-2" ]
}

# --- task_for_branch ---------------------------------------------------------

@test "task_for_branch fails when the branch has no task" {
  run task_for_branch "$ROOT" main
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "task_for_branch prints the absolute task folder" {
  new_task feature/x
  run task_for_branch "$ROOT" feature/x
  [ "$status" -eq 0 ]
  [ "$output" = "$ROOT/.tasks/feature/x" ]
}

@test "task_for_branch fails when another branch owns the same folder" {
  # 'a#b' and 'a@b' both map to .tasks/a-b/.
  new_task 'a#b'
  run task_for_branch "$ROOT" 'a@b'
  [ "$status" -ne 0 ]
  task_for_branch "$ROOT" 'a#b'
}

@test "task_for_branch fails on a folder with no state.json" {
  mkdir -p "$ROOT/.tasks/main"
  run task_for_branch "$ROOT" main
  [ "$status" -ne 0 ]
}

# --- task_is_finished --------------------------------------------------------

@test "task_is_finished follows pr-text.md" {
  new_task feature/x
  ! task_is_finished "$ROOT/.tasks/feature/x"
  echo "text" > "$ROOT/.tasks/feature/x/pr-text.md"
  task_is_finished "$ROOT/.tasks/feature/x"
}

# --- task_open_branch (§2.6) -------------------------------------------------

@test "task_open_branch fails with no .tasks folder" {
  run task_open_branch "$ROOT"
  [ "$status" -ne 0 ]
}

@test "task_open_branch fails when every task is finished" {
  new_task feature/old finished
  new_task bugfix/older finished
  run task_open_branch "$ROOT"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "task_open_branch prints the open task's real branch name, among finished ones" {
  new_task feature/old finished
  new_task 'feature/añadir login#2'
  run task_open_branch "$ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "feature/añadir login#2" ]
}

@test "task_open_branch finds a task in a nested folder from a subfolder of the repo" {
  new_task team/feature/deep
  mkdir -p "$ROOT/src" && cd "$ROOT/src"
  [ "$(task_open_branch "$(git_root)")" = "team/feature/deep" ]
}
