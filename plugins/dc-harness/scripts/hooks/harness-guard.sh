#!/usr/bin/env bash
# harness-guard.sh: the PreToolUse hook (contracts §5.4).
#
# Matcher: Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell.
#   - Protected files, at every step: .tasks/**/state.json, approvals.json, stop-check.json,
#     and everything under .harness/. Only the harness writes them.
#   - Read-only steps (start-task, plan): only the task folder is writable, and shell
#     commands must be read-only (an allow-list: anything unknown is blocked).

# SC2016: `$(` and `$null` are matched literally, so single quotes are intended.
# shellcheck disable=SC2016
set -u

# shellcheck source=SCRIPTDIR/../lib/hook.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/hook.sh"

EVENT=PreToolUse
hook_init

TOOL=$(json_get_text "$PAYLOAD" '.tool_name // empty') || fail_open
TASK_REL=$(task_rel_dir "$BRANCH")

READ_ONLY_STEP=0
case "$STEP" in
  start-task|plan) READ_ONLY_STEP=1 ;;
esac

PROTECTED_REASON="DC-Harness files are written only by the harness."

# block REASON: denies the tool call and exits.
block() {
  emit "$EVENT" block "$1" "" ""
  exit 0
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# long_path PATH: on Windows, PATH with 8.3 short names (C:/Users/MIGUEL~1.GAR) expanded to
# the long ones git reports. A file about to be written doesn't exist yet, so the longest
# existing part is expanded and the rest kept as is.
long_path() {
  local dir=$1 rest="" long
  while [ -n "$dir" ] && [ "$dir" != . ] && [ "$dir" != / ]; do
    if [ -e "$dir" ] && long=$(cygpath -m -l "$dir" 2>/dev/null); then
      printf '%s%s\n' "$long" "$rest"
      return 0
    fi
    rest="/$(basename "$dir")$rest"
    [ "$(dirname "$dir")" = "$dir" ] && break
    dir=$(dirname "$dir")
  done
  printf '%s\n' "$1"
}

# norm_path PATH: PATH with `/` separators, `.` and `..` resolved, a lower-case drive letter
# (C:\x and /c/x both become c:/x), short names expanded and, relative paths, resolved from
# the project root.
norm_path() {
  local p=${1//\\//} part out=""
  local -a parts kept=()
  if [[ "$p" == *"~"* ]] && command -v cygpath >/dev/null 2>&1; then
    p=$(long_path "$p")
  fi
  # Git Bash form /c/x → c:/x
  if [[ "$p" =~ ^/([A-Za-z])(/.*)?$ ]]; then
    p="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
  fi
  if [[ "$p" =~ ^([A-Za-z]):(.*)$ ]]; then
    p="${BASH_REMATCH[1],,}:${BASH_REMATCH[2]}"
  elif [[ "$p" != /* ]]; then
    p="$(norm_path "$ROOT")/$p"
  fi
  IFS=/ read -ra parts <<< "$p"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|.) ;;
      ..)   [ "${#kept[@]}" -gt 1 ] && unset 'kept[${#kept[@]}-1]' ;;
      *)    kept+=("$part") ;;
    esac
  done
  for part in "${kept[@]}"; do
    out="$out/$part"
  done
  # A drive path keeps no leading slash: c:/x.
  [[ "${kept[0]:-}" == [a-z]: ]] && out=${out#/}
  printf '%s\n' "$out"
}

# repo_rel PATH: prints PATH relative to the project root, in lower case, and fails when
# PATH is outside the repo. Windows paths are case-insensitive, so the whole comparison is.
repo_rel() {
  local p root
  p=$(norm_path "$1")
  root=$(norm_path "$ROOT")
  p=${p,,}
  root=${root,,}
  [[ "$p" == "$root/"* ]] || return 1
  printf '%s\n' "${p#"$root/"}"
}

# is_protected REL: REL (lower case, relative to the root) is a harness file.
is_protected() {
  case "$1" in
    .harness|.harness/*) return 0 ;;
    .tasks/*/state.json|.tasks/*/approvals.json|.tasks/*/stop-check.json) return 0 ;;
  esac
  return 1
}

# ---------------------------------------------------------------------------
# Shell commands
# ---------------------------------------------------------------------------

# is_task_state_call CMD: CMD is exactly one call to this plugin's task-state.sh. The skills
# run it while the step is still the previous one, so it is always allowed.
is_task_state_call() {
  local re='^[[:space:]]*bash[[:space:]]+"?([^"]+)"?([[:space:]]+[^;&|<>`$]*)?$'
  local called ours
  [[ "$1" =~ $re ]] || return 1
  called=$(norm_path "${BASH_REMATCH[1]}")
  ours=$(norm_path "$PLUGIN_ROOT/scripts/task-state.sh")
  [ "${called,,}" = "${ours,,}" ]
}

# mentions_protected CMD: CMD names a harness file or folder.
mentions_protected() {
  local c=${1//\\//}
  c=${c,,}
  [[ "$c" == *.harness* || "$c" == *state.json* || "$c" == *approvals.json* ||
     "$c" == *stop-check.json* ]]
}

# is_read_only_piece PIECE: one simple command starts with a known reader (contracts §5.4)
# and has none of the options that make a reader write.
is_read_only_piece() {
  local -a w
  local first arg
  read -ra w <<< "$1"
  [ "${#w[@]}" -gt 0 ] || return 0
  first=${w[0],,}
  case "$first" in
    cat|head|tail|less|grep|rg|ls|wc|diff|jq|echo|pwd) ;;
    get-content|type|select-string|get-childitem|dir|test-path|get-item|get-location) ;;
    find)
      for arg in "${w[@]:1}"; do
        case "$arg" in
          -exec|-execdir|-ok|-okdir|-delete|-fprint|-fprint0|-fprintf|-fls) return 1 ;;
        esac
      done ;;
    git)
      case "${w[1]:-}" in
        status|diff|log|show|ls-files|rev-parse) ;;
        branch)
          # Listing only: a name creates a branch; these flags change one.
          for arg in "${w[@]:2}"; do
            case "$arg" in
              -d|-D|-m|-M|-c|-C|-f|-u|--delete|--move|--copy|--force|--set-upstream-to*|\
              --unset-upstream|--edit-description|--track|--no-track) return 1 ;;
              -*) ;;
              *) return 1 ;;
            esac
          done ;;
        *) return 1 ;;
      esac ;;
    *) return 1 ;;
  esac
  # git diff/log/show --output=FILE writes a file.
  [[ "$1" != *--output* ]]
}

# is_read_only CMD: every piece of CMD is a reader, and nothing is written by redirection.
is_read_only() {
  local c=$1 piece
  local -a pieces
  # Command and process substitution run other commands inside a reader.
  [[ "$c" == *'$('* || "$c" == *'`'* || "$c" == *'<('* || "$c" == *'>('* ]] && return 1
  # Allowed redirections: 2>&1, and output to /dev/null or $null. Any other `>` writes.
  c=$(printf '%s' "$c" | sed -E 's/[0-9]*>&[0-9]+//g; s#[0-9]*>>?[[:space:]]*(/dev/null|\$null)##g')
  [[ "$c" == *'>'* ]] && return 1
  # Split at ; && || | & and newlines.
  c=$(printf '%s' "$c" | tr '\n' ';' | sed -E 's/&&|\|\||[|&]/;/g')
  IFS=';' read -ra pieces <<< "$c"
  for piece in "${pieces[@]}"; do
    is_read_only_piece "$piece" || return 1
  done
}

# ---------------------------------------------------------------------------
# Decide
# ---------------------------------------------------------------------------

case "$TOOL" in
  Edit|Write|MultiEdit|NotebookEdit)
    path=$(json_get_text "$PAYLOAD" '.tool_input.file_path // .tool_input.notebook_path // empty') ||
      fail_open
    [ -n "$path" ] || exit 0
    # Outside the repo (the agent's own scratch or memory files): not the project's code.
    rel=$(repo_rel "$path") || exit 0
    is_protected "$rel" && block "$PROTECTED_REASON"
    if [ "$READ_ONLY_STEP" -eq 1 ] && [[ "$rel" != "${TASK_REL,,}/"* ]]; then
      block "/dc:$STEP is read-only: write only spec.md or plan.md."
    fi
    ;;
  Bash|PowerShell)
    cmd=$(json_get_text "$PAYLOAD" '.tool_input.command // empty') || fail_open
    [ -n "$cmd" ] || exit 0
    is_task_state_call "$cmd" && exit 0
    is_read_only "$cmd" && exit 0
    mentions_protected "$cmd" && block "$PROTECTED_REASON"
    if [ "$READ_ONLY_STEP" -eq 1 ]; then
      block "/dc:$STEP is read-only: only reading commands are allowed."
    fi
    ;;
esac
exit 0
