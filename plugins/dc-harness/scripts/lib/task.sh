#!/usr/bin/env bash
# lib/task.sh: finding the project and its task. task-state.sh and every hook start the same
# way with these, so they all give the same answer to "is there a task here?".
# Source it; it only defines functions. It sources json.sh itself.
#
# Typical start of a script:
#   root=$(git_root) || <not a git repo>
#   task_onboarded "$root" || <not onboarded: refuse G1, or a hook exits silently>
#   branch=$(git_branch) || <detached HEAD: G2>
#   dir=$(task_for_branch "$root" "$branch") || <no task on this branch: G3>

# shellcheck source=SCRIPTDIR/json.sh
source "$(dirname "${BASH_SOURCE[0]}")/json.sh"

TASKS_DIR=.tasks                    # task folders, relative to the project root
CONFIG_FILE=.harness/config.json    # its presence means "onboarded"

# task_onboarded ROOT: succeeds when ROOT has .harness/config.json (check G1).
task_onboarded() {
  [ -f "$1/$CONFIG_FILE" ]
}

# config_get ROOT FILTER [JQ_ARGS...]: prints FILTER applied to the project's config merged
# over the plugin defaults (contracts §1: defaults/config.json * .harness/config.json), raw,
# without `\r`. A key missing from the project falls back to its default.
#   config_get "$root" '.specApprovalPhrase[0]'
config_get() {
  local root=$1 filter=$2 defaults
  shift 2
  defaults="$(dirname "${BASH_SOURCE[0]}")/../../defaults/config.json"
  json_get_merged "$defaults" "$root/$CONFIG_FILE" "$filter" "$@"
}

# task_folder BRANCH: prints the task folder name for a branch (contracts §2.1).
# `/` is kept, so each part becomes a nested folder; every other character outside
# A-Z a-z 0-9 . _ - becomes `-`, one per character (feature/añadir login#2 →
# feature/a-adir-login-2).
task_folder() {
  # A UTF-8 locale makes `ñ` one character, so it becomes one `-`, not one per byte.
  local LC_ALL=C.UTF-8
  printf '%s\n' "${1//[^A-Za-z0-9._\/-]/-}"
}

# task_rel_dir BRANCH: prints the task folder relative to the project root (.tasks/<folder>),
# the form task-state.sh prints as `task-dir=`.
task_rel_dir() {
  printf '%s/%s\n' "$TASKS_DIR" "$(task_folder "$1")"
}

# task_for_branch ROOT BRANCH: prints the absolute task folder of BRANCH, and fails when the
# branch has no task. The folder must hold a state.json whose `branch` is BRANCH: two branch
# names can map to the same folder, and then only one of them owns it.
task_for_branch() {
  local root=$1 branch=$2 dir owner
  dir="$root/$(task_rel_dir "$branch")"
  owner=$(json_get "$dir/state.json" '.branch // empty' 2>/dev/null) || return 1
  [ "$owner" = "$branch" ] || return 1
  printf '%s\n' "$dir"
}

# task_is_finished DIR: succeeds when the task in DIR is finished (pr-text.md exists).
task_is_finished() {
  [ -f "$1/pr-text.md" ]
}

# task_open_branch ROOT: prints the branch of the open task in the repo, and fails when there
# is none. A task is open while its folder has state.json and no pr-text.md (contracts §2.6).
# There is at most one; if there are more (a bug, or files copied by hand), it prints the
# first found.
task_open_branch() {
  local root=$1 state dir
  [ -d "$root/$TASKS_DIR" ] || return 1
  while IFS= read -r state; do
    dir=$(dirname "$state")
    if ! task_is_finished "$dir"; then
      json_get "$state" '.branch // empty'
      return 0
    fi
  done < <(find "$root/$TASKS_DIR" -name state.json -type f | sort)
  return 1
}
