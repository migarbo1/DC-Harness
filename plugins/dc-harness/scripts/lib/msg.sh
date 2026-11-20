#!/usr/bin/env bash
# lib/msg.sh: how the harness talks back.
# Source it; it only defines functions.
#
#   task-state.sh (contracts §4.2):  refuse, internal
#   hooks         (contracts §5.3):  emit, fail_open
#
# The hooks build one neutral answer (decision, reason, message, context) and `emit` turns it
# into the agent's own JSON. Supporting another agent later means a new branch in `emit`,
# not changes to the hooks.

# refuse LINE: a precondition failed. Prints LINE on stdout and exits 1.
# The skill prints the line exactly and stops.
refuse() {
  printf '%s\n' "$1"
  exit 1
}

# internal LINE: the script can't run (not a git repo, jq missing, bad arguments).
# Prints "dc: internal: LINE" on stderr and exits 2.
internal() {
  printf 'dc: internal: %s\n' "$1" >&2
  exit 2
}

# emit EVENT DECISION REASON MESSAGE CONTEXT: prints the hook's answer as Claude Code JSON.
#   EVENT     UserPromptSubmit | PreToolUse | Stop
#   DECISION  allow | block       (block is ignored for UserPromptSubmit: prompts never block)
#   REASON    for the agent: why it's blocked and what to do instead
#   MESSAGE   for the developer, shown in the UI
#   CONTEXT   for the agent, added without blocking (UserPromptSubmit only)
# Empty arguments are left out. With nothing to say it prints nothing. Always returns 0 on
# success; the hook then exits 0 (contracts §5.3: hooks say everything through the JSON).
emit() {
  local event=$1 decision=${2:-allow} reason=${3:-} message=${4:-} context=${5:-} out
  out=$(jq -cn \
    --arg event "$event" --arg decision "$decision" --arg reason "$reason" \
    --arg message "$message" --arg context "$context" '
    def block: $decision == "block" and $reason != "";
    (if $event == "UserPromptSubmit" and $context != "" then
       {hookSpecificOutput: {hookEventName: $event, additionalContext: $context}}
     elif $event == "PreToolUse" and block then
       {hookSpecificOutput: {hookEventName: $event, permissionDecision: "deny",
                             permissionDecisionReason: $reason}}
     elif $event == "Stop" and block then
       {decision: "block", reason: $reason}
     else {} end)
    + (if $message != "" then {systemMessage: $message} else {} end)
    | select(. != {})') || return 1
  out=${out//$'\r'/}
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
  fi
}

# fail_open: the hook itself failed (jq missing, a bug). Allows the action, tells the
# developer, and exits 0, so a bug of ours never locks anyone out of their session.
# Written without jq on purpose: a missing jq is one of the failures it covers.
fail_open() {
  printf '%s\n' '{"systemMessage":"DC-Harness hook failed: run doctor.sh."}'
  exit 0
}
