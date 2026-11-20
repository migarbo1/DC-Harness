# Shared setup for the bats tests. Load it with `load ../test_helper` (path relative to the
# .bats file).

REPO_ROOT=$(cd "$BATS_TEST_DIRNAME" && git rev-parse --show-toplevel)
LIB_DIR="$REPO_ROOT/plugins/dc-harness/scripts/lib"

# make_repo [DIR]: creates a git repo with one commit on `main`, and cds into it.
# Prints nothing. The repo lives in the test's own temp folder, deleted after the test.
make_repo() {
  local dir=${1:-"$BATS_TEST_TMPDIR/repo"}
  mkdir -p "$dir"
  cd "$dir" || return 1
  git init --quiet --initial-branch=main
  git config user.name "dc test"
  git config user.email "dc-test@example.invalid"
  git config core.autocrlf false
  echo "hello" > README.md
  git add README.md
  git commit --quiet -m "first"
}

# onboard: writes a minimal .harness/config.json in the current repo and commits it.
onboard() {
  mkdir -p .harness
  echo '{ "schemaVersion": 1 }' > .harness/config.json
  printf '.tasks/\n' > .gitignore
  git add .harness .gitignore
  git commit --quiet -m "onboard"
}
