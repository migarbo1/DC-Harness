#!/usr/bin/env bats
# Tests for plugins/dc-harness/templates/: the fixed markers the skills copy from them
# (contracts §6) must be the ones task-state.sh reads.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  load test_helper
  TS="$REPO_ROOT/plugins/dc-harness/scripts/task-state.sh"
  TEMPLATES="$REPO_ROOT/plugins/dc-harness/templates"
  make_repo
  onboard
  git switch --quiet -c feature/x
  T=.tasks/feature/x
}

@test "plan.md: a plan copied from the template passes I5, and CP1 is next" {
  stage spec-approved
  stage planned
  cp "$TEMPLATES/plan.md" "$T/plan.md"
  stage plan-approved
  run --separate-stderr bash "$TS" implement sess-new
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "checkpoint=CP1" ]
}

@test "plan.md: no line starts with '## CP' except the checkpoint headings" {
  run grep -c '^## CP' "$TEMPLATES/plan.md"
  [ "$output" -eq "$(grep -cE '^## CP[0-9]+: .+$' "$TEMPLATES/plan.md")" ]
}

@test "plan.md: no checkboxes, so the approved plan is never ticked" {
  run grep -n -- '- \[ \]' "$TEMPLATES/plan.md"
  [ "$status" -eq 1 ]
}

@test "implementation-notes.md: an entry copied from the template marks CP1 done, CP2 is next" {
  stage plan-approved
  cp "$TEMPLATES/implementation-notes.md" "$T/implementation-notes.md"
  run --separate-stderr bash "$TS" implement sess-new
  [ "$status" -eq 0 ]
  [ "${lines[1]}" = "checkpoint=CP2" ]
}

@test "implementation-notes.md: no line starts with '## CP' except the entry heading" {
  run grep -c '^## CP' "$TEMPLATES/implementation-notes.md"
  [ "$output" -eq 1 ]
  grep -qE '^## CP1: .+$' "$TEMPLATES/implementation-notes.md"
}

@test "implement skill: calls task-state.sh implement and stack-check.sh full as allowed" {
  local skill="$REPO_ROOT/plugins/dc-harness/skills/implement/SKILL.md"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" implement "${CLAUDE_SESSION_ID}"' "$skill"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-check.sh" full' "$skill"
  grep -qF 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-check.sh" full)' "$skill"
  grep -qF 'disable-model-invocation: true' "$skill"
}
