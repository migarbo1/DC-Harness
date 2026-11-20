#!/usr/bin/env bats
# Tests for scripts/onboard-repo.sh.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
}

setup() {
  load test_helper
  OB="$REPO_ROOT/scripts/onboard-repo.sh"
  PLUGIN="$REPO_ROOT/plugins/dc-harness"
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
}

onboard_repo() {
  run --separate-stderr bash "$OB" "$@"
}

@test "bad usage exits 2" {
  onboard_repo
  [ "$status" -eq 2 ]
  onboard_repo --marketplace
  [ "$status" -eq 2 ]
  onboard_repo a b
  [ "$status" -eq 2 ]
}

@test "refuses a folder that isn't in a git repo" {
  mkdir "$BATS_TEST_TMPDIR/plain"
  onboard_repo "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"is not in a git repo"* ]]
}

@test "a fresh repo: config, rules, CLAUDE.md import and .gitignore" {
  onboard_repo .
  [ "$status" -eq 0 ]
  # The full defaults, every key visible, LF endings.
  [ "$(jq -S . .harness/config.json)" = "$(jq -S . "$PLUGIN/defaults/config.json")" ]
  ! grep -qU $'\r' .harness/config.json
  [ "$(cat .harness/AGENTS.md)" = "$(tr -d '\r' < "$PLUGIN/AGENTS.template.md")" ]
  [ "$(cat CLAUDE.md)" = "@.harness/AGENTS.md" ]
  grep -qxF ".tasks/" .gitignore
  [ ! -e .claude/settings.json ]
  [[ "$output" == *"[skip] .claude/settings.json: no --marketplace given"* ]]
}

@test "works from a subfolder path of the repo" {
  mkdir -p src/deep
  onboard_repo src/deep
  [ "$status" -eq 0 ]
  [ -f .harness/config.json ]
  [ ! -e src/deep/.harness ]
}

@test "the project's own CLAUDE.md and .gitignore keep their content, even with no final newline" {
  printf '# Our rules\nUse tabs.' > CLAUDE.md
  printf 'node_modules/' > .gitignore
  onboard_repo .
  [ "$(cat CLAUDE.md)" = $'# Our rules\nUse tabs.\n@.harness/AGENTS.md' ]
  [ "$(head -n 1 .gitignore)" = "node_modules/" ]
  grep -qxF ".tasks/" .gitignore
}

@test "re-running changes nothing and keeps the tech lead's files" {
  onboard_repo .
  echo '{"schemaVersion": 1, "stack": ["python"], "prTextMaxChars": 1000}' > .harness/config.json
  echo "# Tuned rules" > .harness/AGENTS.md
  before=$(cat CLAUDE.md .gitignore .harness/config.json .harness/AGENTS.md)
  onboard_repo .
  [ "$status" -eq 0 ]
  [ "$(cat CLAUDE.md .gitignore .harness/config.json .harness/AGENTS.md)" = "$before" ]
  [[ "$output" == *"[kept] .harness/config.json"* ]]
  [[ "$output" == *"[kept] CLAUDE.md already imports"* ]]
}

@test "--marketplace with a folder: a directory source, other settings kept" {
  mkdir .claude
  echo '{"permissions": {"allow": ["Bash(ls)"]}}' > .claude/settings.json
  onboard_repo --marketplace "$REPO_ROOT" .
  [ "$status" -eq 0 ]
  [ "$(jq -r '.extraKnownMarketplaces["dc-harness"].source.source' .claude/settings.json | tr -d '\r')" = "directory" ]
  [ "$(jq -r '.enabledPlugins["dc@dc-harness"]' .claude/settings.json | tr -d '\r')" = "true" ]
  [ "$(jq -r '.permissions.allow[0]' .claude/settings.json | tr -d '\r')" = "Bash(ls)" ]
}

@test "--marketplace with a URL: a git source" {
  url="https://dev.azure.com/org/project/_git/nunsys-harness"
  onboard_repo --marketplace "$url" .
  [ "$status" -eq 0 ]
  [ "$(jq -c '.extraKnownMarketplaces["dc-harness"].source' .claude/settings.json | tr -d '\r')" = "{\"source\":\"git\",\"url\":\"$url\"}" ]
}

@test "--marketplace with a folder that isn't a marketplace fails" {
  mkdir notamarket
  onboard_repo --marketplace notamarket .
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"has no .claude-plugin/marketplace.json"* ]]
}

@test "the onboarded repo works with task-state.sh" {
  onboard_repo .
  git add -A && git commit --quiet -m onboard
  git switch --quiet -c feature/x
  run bash "$PLUGIN/scripts/task-state.sh" start-task sess
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "task-dir=.tasks/feature/x" ]
  # .tasks/ is ignored, so the tree stays clean.
  [ -z "$(git status --porcelain)" ]
}
