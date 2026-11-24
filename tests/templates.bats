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

@test "assessment.md: the template's score placeholder doesn't finish the assessment" {
  stage cp2
  cp "$TEMPLATES/assessment.md" "$T/assessment.md"
  run --separate-stderr bash "$TS" pr-text sess
  [ "$status" -eq 1 ]
  [ "$output" = "Assessment not finished. Run /dc:assessment." ]
}

@test "assessment.md: the template's score line, filled in, finishes the assessment" {
  stage cp2
  sed -E 's|^Score: .*$|Score: 3/4 (passed)|' "$TEMPLATES/assessment.md" > "$T/assessment.md"
  run --separate-stderr bash "$TS" pr-text sess
  [ "$status" -eq 0 ]
}

@test "assessment.md: exactly one line starts with 'Score:'" {
  run grep -c '^Score:' "$TEMPLATES/assessment.md"
  [ "$output" -eq 1 ]
}

@test "assessment skill: calls task-state.sh assessment as allowed, and can't be started by the model" {
  local skill="$REPO_ROOT/plugins/dc-harness/skills/assessment/SKILL.md"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" assessment "${CLAUDE_SESSION_ID}"' "$skill"
  grep -qF 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" assessment *)' "$skill"
  grep -qF 'disable-model-invocation: true' "$skill"
  grep -qF '.assessment-key.md' "$skill"
}

# strip_comments FILE: FILE without its HTML comments (one-line or multi-line), as the skill
# leaves it.
strip_comments() {
  awk '/<!--/ { c = 1 } !c { print } /-->/ { c = 0 }' "$1"
}

@test "pr-text.md: the template, comments removed, fits the default prTextMaxChars" {
  stage finished
  strip_comments "$TEMPLATES/pr-text.md" > "$T/pr-text.md"
  run grep -c '<!--' "$T/pr-text.md"
  [ "$output" -eq 0 ]
  grep -q '^## DC-Harness$' "$T/pr-text.md"
  grep -q '^1\. \*\*' "$T/pr-text.md"
  run --separate-stderr bash "$REPO_ROOT/plugins/dc-harness/scripts/pr-text-length.sh"
  [ "$status" -eq 0 ]
}

@test "pr-text.md: carries the Score line, and no checkboxes or HTML outside comments" {
  grep -qE '^Score: ' "$TEMPLATES/pr-text.md"
  run grep -n -- '- \[ \]' "$TEMPLATES/pr-text.md"
  [ "$status" -eq 1 ]
  run grep -nE '<(details|summary|br|div|img)' < <(strip_comments "$TEMPLATES/pr-text.md")
  [ "$status" -eq 1 ]
}

@test "pr-text skill: calls task-state.sh pr-text and pr-text-length.sh as allowed, and can't be started by the model" {
  local skill="$REPO_ROOT/plugins/dc-harness/skills/pr-text/SKILL.md"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" pr-text "${CLAUDE_SESSION_ID}"' "$skill"
  grep -qF 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" pr-text *)' "$skill"
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-text-length.sh"' "$skill"
  grep -qF 'Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-text-length.sh")' "$skill"
  grep -qF 'disable-model-invocation: true' "$skill"
}
