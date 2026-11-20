#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/hooks/harness-guard.sh (contracts §5.4), run on the
# recorded PreToolUse payloads (Write, Edit, PowerShell) in tests/fixtures/hooks/.

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
  PROTECTED="DC-Harness files are written only by the harness."
  TASK_STATE="$REPO_ROOT/plugins/dc-harness/scripts/task-state.sh"
}

# winpath REL: the absolute Windows form of a path in the repo, as the file tools send it.
winpath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$PWD/$1"
  else
    printf '%s/%s\n' "$PWD" "$1"
  fi
}

# file_tool TOOL PATH: runs the guard on the recorded Write payload with TOOL and PATH.
file_tool() {
  hook harness-guard pre-tool-use-write '.tool_name = $t | .tool_input.file_path = $p' \
    --arg t "$1" --arg p "$2"
}

# shell TOOL COMMAND: runs the guard on the recorded PowerShell payload with TOOL and COMMAND.
shell() {
  hook harness-guard pre-tool-use-powershell '.tool_name = $t | .tool_input.command = $c' \
    --arg t "$1" --arg c "$2"
}

# denied_with REASON: the last run denied the tool call with REASON.
denied_with() {
  [ "$status" -eq 0 ] || return 1
  [ "$(out .hookSpecificOutput.permissionDecision)" = "deny" ] || return 1
  [ "$(out .hookSpecificOutput.permissionDecisionReason)" = "$1" ]
}

# allowed: the last run said nothing.
allowed() {
  [ "$status" -eq 0 ] && [ -z "$output" ]
}

implementing() {
  stage cp1
  set_state '.step = "implement" | .gate = null'
}

# --- No task: nothing is guarded -------------------------------------------------

@test "silent when the branch has no task" {
  file_tool Write "$(winpath .harness/config.json)"
  allowed
}

# --- Protected files, at every step ------------------------------------------------

@test "file tools: the recorded Edit payload is denied on .harness/ during implement" {
  implementing
  hook harness-guard pre-tool-use-edit '.tool_input.file_path = $p' \
    --arg p "$(winpath .harness/config.json)"
  denied_with "$PROTECTED"
}

@test "file tools: state.json, approvals.json and stop-check.json are protected" {
  implementing
  for f in state.json approvals.json stop-check.json; do
    file_tool Write "$(winpath "$T/$f")"
    denied_with "$PROTECTED"
  done
}

@test "file tools: other casing and .. segments don't get around the protection" {
  implementing
  file_tool Write "$(winpath .)\\src\\..\\.HARNESS\\Config.json"
  denied_with "$PROTECTED"
  file_tool Write ".harness/AGENTS.md"
  denied_with "$PROTECTED"
}

@test "file tools: during implement, code and the task's own files can be written" {
  implementing
  for p in "$(winpath app/main.py)" "$(winpath "$T/implementation-notes.md")" "tests/test_x.py"; do
    file_tool Write "$p"
    allowed
  done
}

# --- Read-only steps: file tools --------------------------------------------------

@test "plan step: writing code is denied, for every file tool" {
  stage planned
  for tool in Write Edit MultiEdit; do
    file_tool "$tool" "$(winpath app/main.py)"
    denied_with "/dc:plan is read-only: write only spec.md or plan.md."
  done
}

@test "plan step: NotebookEdit's notebook_path is checked too" {
  stage planned
  hook harness-guard pre-tool-use-write \
    '.tool_name = "NotebookEdit" | del(.tool_input.file_path) | .tool_input.notebook_path = $p' \
    --arg p "$(winpath analysis.ipynb)"
  denied_with "/dc:plan is read-only: write only spec.md or plan.md."
}

@test "plan step: plan.md in the task folder can be written, absolute or relative" {
  stage planned
  file_tool Write "$(winpath "$T/plan.md")"
  allowed
  file_tool Edit "$T/plan.md"
  allowed
}

@test "start-task step: spec.md is writable, another task's folder isn't" {
  stage started
  file_tool Write "$(winpath "$T/spec.md")"
  allowed
  file_tool Write "$(winpath .tasks/feature/other/spec.md)"
  denied_with "/dc:start-task is read-only: write only spec.md or plan.md."
}

@test "plan step: protected files inside the task folder stay protected" {
  stage planned
  file_tool Write "$(winpath "$T/approvals.json")"
  denied_with "$PROTECTED"
}

@test "plan step: files outside the repo are not the project's code" {
  stage planned
  file_tool Write "$(cygpath -w "$BATS_TEST_TMPDIR" 2>/dev/null || echo "$BATS_TEST_TMPDIR")/scratch/notes.md"
  allowed
}

# --- Read-only steps: shell tools -------------------------------------------------

@test "plan step: reading commands are allowed, in Bash and PowerShell" {
  stage planned
  local -a cmds=(
    'git status'
    'git diff HEAD~1 -- app/main.py'
    'git log --oneline -5 | head -3'
    'git show HEAD:README.md'
    'git branch'
    'git branch -a --list'
    'cat README.md && ls -la'
    'grep -rn "def " app 2>/dev/null'
    'find . -name "*.py" -type f'
    'rg TODO; wc -l README.md'
    'jq .stack .harness/config.json'
    'Get-Content README.md | Select-String def'
    'Get-ChildItem -Recurse app 2>&1 | Select-String py'
    'Test-Path .tasks; Get-Location'
    'type README.md > $null'
  )
  for tool in Bash PowerShell; do
    for c in "${cmds[@]}"; do
      shell "$tool" "$c"
      allowed || { echo "not allowed: $tool: $c"; return 1; }
    done
  done
}

@test "plan step: commands that write are denied" {
  stage planned
  local -a cmds=(
    'rm app/main.py'
    'echo hi > notes.txt'
    'cat a >> b'
    'echo $(rm x)'
    'ls `rm x`'
    'find . -name "*.pyc" -delete'
    'find . -exec rm {} ;'
    'git branch new-branch'
    'git branch -D feature/x'
    'git commit -m wip'
    'git diff --output=patch.txt'
    'cd app && ls'
    'grep x README.md | tee out.txt'
    'ls; touch new.py'
    'python -m pytest'
    'Set-Content f.txt x'
    'ls & rm x'
  )
  for c in "${cmds[@]}"; do
    shell PowerShell "$c"
    denied_with "/dc:plan is read-only: only reading commands are allowed." ||
      { echo "not denied: $c ($output)"; return 1; }
  done
}

@test "start-task step: the reason names the step" {
  stage started
  shell Bash "touch x.py"
  denied_with "/dc:start-task is read-only: only reading commands are allowed."
}

@test "the recorded PowerShell payload (a bash call) is denied in the plan step" {
  stage planned
  hook harness-guard pre-tool-use-powershell
  denied_with "/dc:plan is read-only: only reading commands are allowed."
}

@test "task-state.sh calls are always allowed, in the form the skills use" {
  stage planned
  win=$(cygpath -m "$TASK_STATE" 2>/dev/null || echo "$TASK_STATE")
  shell PowerShell "bash \"$win\" implement \"sess-1\""
  allowed
  shell Bash "bash \"$win\" implement \"sess-1\" CP1"
  allowed
}

@test "task-state.sh: chained commands or another copy of the script are denied" {
  stage planned
  win=$(cygpath -m "$TASK_STATE" 2>/dev/null || echo "$TASK_STATE")
  shell PowerShell "bash \"$win\" plan \"s\"; rm app/main.py"
  denied_with "/dc:plan is read-only: only reading commands are allowed."
  shell PowerShell 'bash "./scripts/task-state.sh" plan "s"'
  denied_with "/dc:plan is read-only: only reading commands are allowed."
}

# --- Protected files through the shell, outside read-only steps ---------------------

@test "implement: commands that write harness files are denied" {
  implementing
  for c in 'rm -rf .harness' "echo {} > $T/state.json" 'Remove-Item .tasks\feature\x\approvals.json' \
           "cp x $T/stop-check.json"; do
    shell PowerShell "$c"
    denied_with "$PROTECTED" || { echo "not denied: $c"; return 1; }
  done
}

@test "implement: reading harness files and ordinary writes are allowed" {
  implementing
  for c in "cat $T/state.json" 'jq .stack .harness/config.json' 'python -m pytest' \
           'echo hi > notes.txt' 'git add -A'; do
    shell Bash "$c"
    allowed || { echo "not allowed: $c ($output)"; return 1; }
  done
}

# --- Fail open ------------------------------------------------------------------

@test "fails open when jq is missing" {
  stage planned
  if [ -x /usr/bin/jq ]; then skip "jq is in /usr/bin here"; fi
  payload=$(jq --arg cwd "$(pwd)" '.cwd = $cwd' < "$FIXTURES/pre-tool-use-write.json")
  run "$BASH" -c "PATH=/usr/bin:/bin; bash '$HOOKS/harness-guard.sh'" <<< "$payload"
  [ "$status" -eq 0 ]
  [ "$output" = '{"systemMessage":"DC-Harness hook failed: run doctor.sh."}' ]
}
