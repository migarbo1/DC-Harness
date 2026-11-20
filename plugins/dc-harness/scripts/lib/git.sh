#!/usr/bin/env bash
# lib/git.sh: the read-only git questions the harness asks.
# Source it; it only defines functions. Every function works on the repo of the current
# directory, so callers cd to the project root first.
#
# Nothing here changes the repo, its index or its refs. git_worktree_tree uses its own
# temporary index for that reason.

# git_root: prints the repo's top folder (C:/x/y form on Windows). Fails outside a repo.
git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

# git_branch: prints the current branch name, as git reports it (feature/x).
# Prints nothing and fails when HEAD is detached (check G2).
git_branch() {
  git symbolic-ref --quiet --short HEAD
}

# git_head_sha: prints HEAD's full 40-char commit SHA (the task's commit-ref).
git_head_sha() {
  git rev-parse --verify --quiet HEAD
}

# git_is_clean: succeeds when nothing is modified, staged or untracked (check S4).
# Gitignored files don't count.
git_is_clean() {
  local status
  status=$(git status --porcelain --untracked-files=normal) || return 1
  [ -z "$status" ]
}

# git_tree_of REF: prints the tree hash of a commit (the starting fingerprint for
# stop-check.sh is the commit-ref's tree).
git_tree_of() {
  git rev-parse --verify --quiet "$1^{tree}"
}

# git_worktree_tree: prints a fingerprint of the working tree as git sees it: the tree hash
# that `git add -A && git write-tree` would give, untracked files included, gitignored files
# (.tasks/ among them) left out. Same files, same hash. (Contracts §5.5.)
# Works on a copy of the index, so the developer's staging area is never touched.
git_worktree_tree() {
  local index tmp tree
  index=$(git rev-parse --git-path index) || return 1
  tmp=$(mktemp) || return 1

  # Starting from a copy of the real index lets git skip re-hashing unchanged files.
  if [ -f "$index" ]; then
    cp "$index" "$tmp"
  else
    rm -f "$tmp"     # no index yet (empty repo): git creates one
  fi

  if GIT_INDEX_FILE=$tmp git add -A >/dev/null 2>&1 &&
     tree=$(GIT_INDEX_FILE=$tmp git write-tree); then
    rm -f "$tmp"
    printf '%s\n' "$tree"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# git_changed_files FROM TO: prints the paths that differ between two trees or commits, one
# per line, relative to the repo root. Non-ASCII names are printed as is, not quoted.
git_changed_files() {
  git -c core.quotePath=false diff --name-only --no-renames "$1" "$2"
}
