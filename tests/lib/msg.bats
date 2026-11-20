#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/lib/msg.sh. The expected JSON is contracts §5.3.

bats_require_minimum_version 1.5.0   # run --separate-stderr

setup() {
  load ../test_helper
  source "$LIB_DIR/msg.sh"
}

# jqo JSON FILTER: reads a field of emit's output.
jqo() {
  printf '%s' "$1" | jq -r "$2" | tr -d '\r'
}

# --- refuse / internal ------------------------------------------------------

@test "refuse prints one line on stdout and exits 1" {
  run --separate-stderr refuse "No spec.md. Run /dc:start-task first."
  [ "$status" -eq 1 ]
  [ "$output" = "No spec.md. Run /dc:start-task first." ]
  [ -z "$stderr" ]
}

@test "internal prints 'dc: internal:' on stderr and exits 2" {
  run --separate-stderr internal "not a git repo"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$stderr" = "dc: internal: not a git repo" ]
}

# --- emit -------------------------------------------------------------------

@test "emit: allow with nothing to say prints nothing" {
  for event in UserPromptSubmit PreToolUse Stop; do
    run emit "$event" allow "" "" ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
  done
}

@test "emit UserPromptSubmit: context becomes additionalContext" {
  run emit UserPromptSubmit allow "" "" "Spec approval recorded. Tell the developer to run /dc:plan."
  [ "$status" -eq 0 ]
  [ "$(jqo "$output" .hookSpecificOutput.hookEventName)" = "UserPromptSubmit" ]
  [ "$(jqo "$output" .hookSpecificOutput.additionalContext)" = "Spec approval recorded. Tell the developer to run /dc:plan." ]
  [ "$(jqo "$output" 'has("decision")')" = "false" ]
}

@test "emit UserPromptSubmit: a message becomes systemMessage" {
  run emit UserPromptSubmit allow "" "Not recorded as approval: type the phrase on its own." ""
  [ "$(jqo "$output" .systemMessage)" = "Not recorded as approval: type the phrase on its own." ]
  [ "$(jqo "$output" 'has("hookSpecificOutput")')" = "false" ]
}

@test "emit UserPromptSubmit: block is ignored, prompts are never blocked" {
  run emit UserPromptSubmit block "nope" "" ""
  [ -z "$output" ]
}

@test "emit PreToolUse: block becomes permissionDecision deny with the reason" {
  run emit PreToolUse block "DC-Harness files are written only by the harness." "" ""
  [ "$(jqo "$output" .hookSpecificOutput.hookEventName)" = "PreToolUse" ]
  [ "$(jqo "$output" .hookSpecificOutput.permissionDecision)" = "deny" ]
  [ "$(jqo "$output" .hookSpecificOutput.permissionDecisionReason)" = "DC-Harness files are written only by the harness." ]
}

@test "emit PreToolUse: allow says nothing about the permission" {
  run emit PreToolUse allow "" "note for the developer" ""
  [ "$(jqo "$output" 'has("hookSpecificOutput")')" = "false" ]
  [ "$(jqo "$output" .systemMessage)" = "note for the developer" ]
}

@test "emit Stop: block becomes decision block with the reason" {
  run emit Stop block "Checks failed. Fix them before finishing:" "" ""
  [ "$(jqo "$output" .decision)" = "block" ]
  [ "$(jqo "$output" .reason)" = "Checks failed. Fix them before finishing:" ]
}

@test "emit: block and message together" {
  run emit Stop block "fix it" "Checks failed" ""
  [ "$(jqo "$output" .decision)" = "block" ]
  [ "$(jqo "$output" .systemMessage)" = "Checks failed" ]
}

@test "emit: output is one line of JSON without \\r" {
  run emit Stop block "line one" "" ""
  [ "${#lines[@]}" -eq 1 ]
  [[ "$output" != *$'\r'* ]]
}

@test "emit keeps a reason that starts with / (Git Bash path conversion)" {
  run emit PreToolUse block "/dc:plan is read-only: write only spec.md or plan.md." "" ""
  [ "$(jqo "$output" .hookSpecificOutput.permissionDecisionReason)" = "/dc:plan is read-only: write only spec.md or plan.md." ]
}

@test "emit keeps quotes, newlines and accents in the text" {
  reason=$'Checks failed:\nE501 "line too long" in señor.py'
  run emit Stop block "$reason" "" ""
  [ "$(jqo "$output" .reason)" = "$reason" ]
}

# --- fail_open --------------------------------------------------------------

@test "fail_open allows, tells the developer, and exits 0" {
  run fail_open
  [ "$status" -eq 0 ]
  [ "$(jqo "$output" .systemMessage)" = "DC-Harness hook failed: run doctor.sh." ]
  [ "$(jqo "$output" 'has("decision") or has("hookSpecificOutput")')" = "false" ]
}

@test "fail_open works without jq on the PATH" {
  run "$BASH" -c "PATH=/nonexistent; source '$LIB_DIR/msg.sh'; fail_open"
  [ "$status" -eq 0 ]
  [ "$output" = '{"systemMessage":"DC-Harness hook failed: run doctor.sh."}' ]
}
