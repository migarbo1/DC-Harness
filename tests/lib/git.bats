#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/lib/git.sh. Each test runs in its own small repo.

setup() {
  load ../test_helper
  source "$LIB_DIR/git.sh"
  make_repo
}

# --- git_root ---------------------------------------------------------------

@test "git_root prints the top folder, from a subfolder too" {
  top=$(git_root)
  mkdir -p sub/deeper
  cd sub/deeper
  [ "$(git_root)" = "$top" ]
}

@test "git_root fails outside a repo" {
  mkdir "$BATS_TEST_TMPDIR/plain"
  cd "$BATS_TEST_TMPDIR/plain"
  run git_root
  [ "$status" -ne 0 ]
}

# --- git_branch -------------------------------------------------------------

@test "git_branch prints the branch, slashes kept" {
  git switch --quiet -c "feature/login-rate-limit"
  run git_branch
  [ "$status" -eq 0 ]
  [ "$output" = "feature/login-rate-limit" ]
}

@test "git_branch fails and prints nothing on a detached HEAD" {
  git switch --quiet --detach
  run git_branch
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

# --- git_head_sha -----------------------------------------------------------

@test "git_head_sha prints a 40-char SHA equal to HEAD" {
  run git_head_sha
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
  [ "$output" = "$(git rev-parse HEAD)" ]
}

# --- git_is_clean -----------------------------------------------------------

@test "git_is_clean: a fresh repo is clean" {
  git_is_clean
}

@test "git_is_clean: a modified file is not clean" {
  echo "changed" >> README.md
  ! git_is_clean
}

@test "git_is_clean: a staged file is not clean" {
  echo "new" > staged.txt
  git add staged.txt
  ! git_is_clean
}

@test "git_is_clean: an untracked file is not clean (check S4)" {
  echo "stray" > stray.txt
  ! git_is_clean
}

@test "git_is_clean: an untracked file in a new folder is not clean" {
  mkdir -p new/folder
  echo "stray" > new/folder/stray.txt
  ! git_is_clean
}

@test "git_is_clean: gitignored files don't count" {
  printf '.tasks/\n' > .gitignore
  git add .gitignore && git commit --quiet -m ignore
  mkdir -p .tasks/main && echo '{}' > .tasks/main/state.json
  git_is_clean
}

# --- git_tree_of / git_worktree_tree ---------------------------------------

@test "git_worktree_tree equals HEAD's tree on a clean repo" {
  run git_worktree_tree
  [ "$status" -eq 0 ]
  [ "$output" = "$(git_tree_of HEAD)" ]
}

@test "git_worktree_tree changes when a tracked file changes" {
  before=$(git_worktree_tree)
  echo "edit" >> README.md
  [ "$(git_worktree_tree)" != "$before" ]
}

@test "git_worktree_tree counts untracked files" {
  before=$(git_worktree_tree)
  echo "new" > new.py
  [ "$(git_worktree_tree)" != "$before" ]
}

@test "git_worktree_tree ignores gitignored files, .tasks/ included" {
  printf '.tasks/\n' > .gitignore
  git add .gitignore && git commit --quiet -m ignore
  before=$(git_worktree_tree)
  mkdir -p .tasks/main && echo "notes" > .tasks/main/plan.md
  [ "$(git_worktree_tree)" = "$before" ]
}

@test "git_worktree_tree is the same for the same files (an edit undone)" {
  before=$(git_worktree_tree)
  cp README.md README.bak
  echo "edit" >> README.md
  mv README.bak README.md
  [ "$(git_worktree_tree)" = "$before" ]
}

@test "git_worktree_tree never touches the developer's index" {
  echo "new" > new.py
  echo "edit" >> README.md
  before=$(git status --porcelain)
  git_worktree_tree >/dev/null
  [ "$(git status --porcelain)" = "$before" ]
  # Nothing was staged.
  [ -z "$(git diff --cached --name-only)" ]
}

@test "git_worktree_tree prints a tree git can read back" {
  echo "new" > new.py
  tree=$(git_worktree_tree)
  [ "$(git cat-file -t "$tree")" = "tree" ]
}

@test "git_tree_of fails on an unknown ref" {
  run git_tree_of no-such-ref
  [ "$status" -ne 0 ]
}

# --- git_changed_files ------------------------------------------------------

@test "git_changed_files lists modified, new and deleted files between two trees" {
  echo "keep" > keep.txt && echo "gone" > gone.txt
  git add . && git commit --quiet -m more
  start=$(git_tree_of HEAD)

  echo "edit" >> README.md
  echo "new" > new.py
  rm gone.txt
  now=$(git_worktree_tree)

  run git_changed_files "$start" "$now"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"README.md"* ]]
  [[ "$output" == *"new.py"* ]]
  [[ "$output" == *"gone.txt"* ]]
  [[ "$output" != *"keep.txt"* ]]
}

@test "git_changed_files prints non-ASCII names as is" {
  start=$(git_tree_of HEAD)
  echo "x" > "añadir.py"
  run git_changed_files "$start" "$(git_worktree_tree)"
  [ "$output" = "añadir.py" ]
}

@test "git_changed_files prints nothing for the same tree" {
  t=$(git_tree_of HEAD)
  run git_changed_files "$t" "$t"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
