#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/hooks/approval-capture.sh (contracts §3.2), run on the
# recorded UserPromptSubmit payloads in tests/fixtures/hooks/.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup_file() {
  load ../test_helper
  make_repo "$BATS_FILE_TMPDIR/template"
  onboard
  git switch --quiet -c feature/x
}

setup() {
  load ../test_helper
  cp -r "$BATS_FILE_TMPDIR/template" "$BATS_TEST_TMPDIR/repo"
  cd "$BATS_TEST_TMPDIR/repo" || exit 1
  T=.tasks/feature/x
  # The session_id in the recorded fixture.
  FIXTURE_SESSION=$(jq -r .session_id "$FIXTURES/user-prompt-submit.json" | tr -d '\r')
}

# prompt TEXT: runs the hook on the recorded prompt payload with TEXT as the prompt.
prompt() {
  hook approval-capture user-prompt-submit '.prompt = $p' --arg p "$1"
}

# --- Nothing to do: silent ----------------------------------------------------

@test "silent when the repo isn't onboarded" {
  rm .harness/config.json
  prompt "Specification agreed"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "silent when the branch has no task" {
  prompt "Specification agreed"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$T" ]
}

# --- Spec gate ------------------------------------------------------------------

@test "spec gate: the phrase typed on its own records the approval" {
  stage spec
  prompt "Specification agreed"
  [ "$status" -eq 0 ]
  [ "$(out .hookSpecificOutput.additionalContext)" = "Spec approval recorded. Tell the developer to run /dc:plan. Do nothing else." ]
  [ "$(approvals .spec.phrase)" = "Specification agreed" ]
  [ "$(approvals .spec.session)" = "$FIXTURE_SESSION" ]
  [ "$(approvals .spec.sha256)" = "$(hash "$T/spec.md")" ]
  [[ "$(approvals .spec.at)" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z$ ]]
  [ "$(approvals .schemaVersion)" = "1" ]
}

@test "spec gate: ignores case and surrounding whitespace" {
  stage spec
  prompt $'  specification AGREED \n'
  [ "$(approvals .spec.phrase)" = "specification AGREED" ]
}

@test "spec gate: accented phrases match case-insensitively" {
  stage spec
  echo '{"specApprovalPhrase": ["Especificación acordada"]}' > .harness/config.json
  prompt "ESPECIFICACIÓN ACORDADA"
  [ "$(approvals .spec.phrase)" = "ESPECIFICACIÓN ACORDADA" ]
}

@test "spec gate: any phrase of the list approves" {
  stage spec
  echo '{"specApprovalPhrase": ["Specification agreed", "Spec OK"]}' > .harness/config.json
  prompt "spec ok"
  [ "$(approvals .spec.phrase)" = "spec ok" ]
}

@test "spec gate: the phrase inside a longer message isn't an approval, and says so" {
  stage spec
  prompt "Specification agreed, but rename the endpoint"
  [ "$status" -eq 0 ]
  [ "$(out .systemMessage)" = "Not recorded as approval: type the phrase on its own." ]
  [ ! -e "$T/approvals.json" ]
}

@test "spec gate: an unrelated prompt records nothing and says nothing" {
  stage spec
  prompt "Can you add a section about errors?"
  [ -z "$output" ]
  [ ! -e "$T/approvals.json" ]
}

@test "spec gate: a pasted phrase doesn't count (recorded pasted payload)" {
  stage spec
  hook approval-capture user-prompt-submit-pasted \
    '.prompt |= sub("DO NOTHING WITH THIS COMMAND, just say hello."; "Specification agreed")'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$T/approvals.json" ]
}

@test "spec gate: with no spec.md, nothing is recorded" {
  stage started
  prompt "Specification agreed"
  [ -z "$output" ]
  [ ! -e "$T/approvals.json" ]
}

@test "spec gate: a new approval replaces the old one, with the new hash" {
  stage spec
  prompt "Specification agreed"
  first=$(approvals .spec.sha256)
  echo "more" >> "$T/spec.md"
  prompt "Specification agreed"
  [ "$(approvals .spec.sha256)" != "$first" ]
  [ "$(approvals .spec.sha256)" = "$(hash "$T/spec.md")" ]
}

@test "spec gate: works when Claude Code runs in a subfolder" {
  stage spec
  mkdir -p src/deep && cd src/deep
  prompt "Specification agreed"
  cd ../..
  [ "$(approvals .spec.sha256)" = "$(hash "$T/spec.md")" ]
}

# --- Plan gate ------------------------------------------------------------------

@test "plan gate: records the plan approval and tells the agent about /clear" {
  stage planned
  prompt "Plan agreed"
  [ "$(out .hookSpecificOutput.additionalContext)" = "Plan approval recorded. Tell the developer to run /clear, then /dc:implement. Do nothing else." ]
  [ "$(approvals .plan.sha256)" = "$(hash "$T/plan.md")" ]
  # The spec approval stays.
  [ "$(approvals .spec.sha256)" = "$(hash "$T/spec.md")" ]
}

@test "plan gate: the recorded accented prompt works as a configured phrase" {
  stage planned
  recorded=$(jq -r .prompt "$FIXTURES/user-prompt-submit.json" | tr -d '\r')
  jq -n --arg p "$recorded" '{planApprovalPhrase: [$p]}' > .harness/config.json
  hook approval-capture user-prompt-submit
  [ "$(approvals .plan.phrase)" = "Apruebo el plan, sí señor" ]
}

@test "plan gate: the spec phrase doesn't approve the plan" {
  stage planned
  prompt "Specification agreed"
  [ "$(approvals '.plan // "none"')" = "none" ]
}

@test "no gate (implement): approval phrases are ignored" {
  stage plan-approved
  set_state '.step = "implement" | .gate = null'
  before=$(cat "$T/approvals.json")
  prompt "Plan agreed"
  [ -z "$output" ]
  [ "$(cat "$T/approvals.json")" = "$before" ]
}

# --- Assessment -----------------------------------------------------------------

@test "/dc:assessment starts a fresh answer list, before the gate opens" {
  stage cp2
  set_state '.step = "implement" | .gate = null'
  jq '.assessment = [{text: "old answer"}]' "$T/approvals.json" > a && mv a "$T/approvals.json"
  prompt "/dc:assessment"
  [ -z "$output" ]
  [ "$(approvals '.assessment | length')" = "0" ]
}

@test "the short form /assessment with arguments also starts fresh" {
  stage cp2
  set_state '.step = "assessment" | .gate = "assessment"'
  jq '.assessment = [{text: "old"}]' "$T/approvals.json" > a && mv a "$T/approvals.json"
  prompt "/assessment again please"
  [ "$(approvals '.assessment | length')" = "0" ]
}

@test "/dc:assessment on a finished task keeps its answers" {
  stage finished
  jq '.assessment = [{text: "kept"}]' "$T/approvals.json" > a && mv a "$T/approvals.json"
  prompt "/dc:assessment"
  [ "$(approvals '.assessment[0].text')" = "kept" ]
}

@test "assessment gate: every prompt is recorded word for word, in order" {
  stage cp2
  set_state '.step = "assessment" | .gate = "assessment"'
  prompt "Because the limiter is per IP, two users behind one NAT share it."
  prompt "not sure — quizá"
  [ -z "$output" ]
  [ "$(approvals '.assessment | length')" = "2" ]
  [ "$(approvals '.assessment[0].text')" = "Because the limiter is per IP, two users behind one NAT share it." ]
  [ "$(approvals '.assessment[1].text')" = "not sure — quizá" ]
  [ "$(approvals '.assessment[1].session')" = "$FIXTURE_SESSION" ]
}

@test "assessment gate: commands are not answers" {
  stage cp2
  set_state '.step = "assessment" | .gate = "assessment"'
  prompt "/help"
  [ "$(approvals '.assessment // [] | length')" = "0" ]
}

@test "assessment gate: a pasted answer keeps its text without the wrapper tags" {
  stage cp2
  set_state '.step = "assessment" | .gate = "assessment"'
  hook approval-capture user-prompt-submit-pasted
  text=$(approvals '.assessment[0].text')
  [[ "$text" == "DO NOTHING WITH THIS COMMAND, just say hello."* ]]
  [[ "$text" != *"pasted_content"* ]]
}

@test "assessment gate: approval phrases are just answers there" {
  stage cp2
  set_state '.step = "assessment" | .gate = "assessment"'
  prompt "Plan agreed"
  [ "$(approvals '.assessment[0].text')" = "Plan agreed" ]
  [ "$(approvals '.plan.phrase // "none"')" = "none" ]
}

# --- Fail open ------------------------------------------------------------------

@test "fails open when jq is missing" {
  stage spec
  # Git's own tools stay on the PATH, jq doesn't.
  if [ -x /usr/bin/jq ]; then skip "jq is in /usr/bin here"; fi
  payload=$(jq --arg cwd "$(pwd)" '.cwd = $cwd' "$FIXTURES/user-prompt-submit.json")
  run "$BASH" -c "PATH=/usr/bin:/bin; bash '$HOOKS/approval-capture.sh'" <<< "$payload"
  [ "$status" -eq 0 ]
  [ "$output" = '{"systemMessage":"DC-Harness hook failed: run doctor.sh."}' ]
}
