#!/usr/bin/env bash
# doctor.sh: checks that this machine has what the DC-Harness plugin needs.
#
# Usage: doctor.sh [--dev] [--quiet]
#   --dev    also check the tools needed to DEVELOP the harness (bats, shellcheck)
#   --quiet  print only warnings and failures (for use from a SessionStart hook)
#
# Exit codes:
#   0  every required check passed (warnings are allowed)
#   1  at least one required check failed
#   2  bad usage
#
# Read-only: it never installs or changes anything. Each problem prints how to fix it.

set -u

# ---------------------------------------------------------------------------
# Settings
# ---------------------------------------------------------------------------

MIN_BASH_MAJOR=4   # associative arrays, ${var,,}, mapfile
MIN_GIT=2.22       # git branch --show-current
MIN_JQ=1.7         # minimum jq version the harness is tested with

# The plugin root is the folder above this script's folder (plugins/dc-harness/).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

usage() {
  echo "Usage: doctor.sh [--dev] [--quiet]"
}

DEV=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --dev)     DEV=1 ;;
    --quiet)   QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

FAILS=0
WARNS=0

# ok MESSAGE
ok() {
  if [ "$QUIET" -eq 0 ]; then
    echo "  [ok]   $1"
  fi
}

# warn MESSAGE FIX
warn() {
  WARNS=$((WARNS + 1))
  echo "  [warn] $1"
  echo "         Fix: $2"
}

# fail MESSAGE FIX
fail() {
  FAILS=$((FAILS + 1))
  echo "  [FAIL] $1"
  echo "         Fix: $2"
}

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

# Prints the first version number (like 2.45.1) found in its input.
first_version() {
  tr -d '\r' | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1
}

# version_at_least HAVE NEED: succeeds when HAVE >= NEED.
# Compares major, minor and patch as numbers, so 1.10 is newer than 1.9.
version_at_least() {
  local have_major have_minor have_patch
  local need_major need_minor need_patch

  IFS=. read -r have_major have_minor have_patch _ <<< "$1"
  IFS=. read -r need_major need_minor need_patch _ <<< "$2"

  # Missing parts count as 0 ("2.22" means "2.22.0").
  have_major=${have_major:-0}; have_minor=${have_minor:-0}; have_patch=${have_patch:-0}
  need_major=${need_major:-0}; need_minor=${need_minor:-0}; need_patch=${need_patch:-0}

  if [ "$have_major" -ne "$need_major" ]; then
    [ "$have_major" -gt "$need_major" ]
    return
  fi
  if [ "$have_minor" -ne "$need_minor" ]; then
    [ "$have_minor" -gt "$need_minor" ]
    return
  fi
  [ "$have_patch" -ge "$need_patch" ]
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

if [ "$QUIET" -eq 0 ]; then
  echo "DC-Harness doctor"
fi

# 1. Platform. On Windows the harness supports Git Bash only.
platform=$(uname -s 2>/dev/null || echo unknown)
case "$platform" in
  MINGW*|MSYS*) ok "platform: Windows, Git Bash ($platform)" ;;
  Linux|Darwin) ok "platform: $platform" ;;
  *) warn "platform '$platform' is not tested" \
          "on Windows, run Claude Code with Git for Windows (Git Bash)" ;;
esac

# 2. bash version.
if [ "${BASH_VERSINFO[0]}" -ge "$MIN_BASH_MAJOR" ]; then
  ok "bash $BASH_VERSION"
else
  fail "bash $BASH_VERSION is too old (need $MIN_BASH_MAJOR or newer)" \
       "install Git for Windows, or on macOS: brew install bash"
fi

# 3. git. The harness reads the repository with read-only git commands.
if command -v git >/dev/null 2>&1; then
  git_version=$(git --version | first_version)
  if version_at_least "$git_version" "$MIN_GIT"; then
    ok "git $git_version"
  else
    fail "git $git_version is too old (need $MIN_GIT or newer)" \
         "update Git for Windows: winget upgrade Git.Git"
  fi
else
  fail "git not found" "install Git for Windows: winget install Git.Git"
fi

# 4. jq. Every script reads and writes JSON with it. Without jq the hooks block everything.
if command -v jq >/dev/null 2>&1; then
  jq_version=$(jq --version 2>&1 | first_version)
  if version_at_least "$jq_version" "$MIN_JQ"; then
    ok "jq $jq_version"
  else
    fail "jq $jq_version is too old (need $MIN_JQ or newer)" \
         "update jq: winget upgrade jqlang.jq"
  fi
else
  fail "jq not found" "install jq: winget install jqlang.jq (then restart the terminal)"
fi

# 5. Claude Code CLI. Only a warning: the desktop app and the IDE extensions
#    don't put `claude` on PATH, and the plugin still works there.
if command -v claude >/dev/null 2>&1; then
  ok "claude $(claude --version 2>/dev/null | first_version)"
else
  warn "claude command not found on PATH" \
       "only needed in a terminal; install Claude Code from https://code.claude.com/docs"
fi

# 6. Git Credential Manager. Claude Code uses git to install and update the plugin
#    from the private repository, and GCM signs in without a prompt. Only a warning:
#    whether it is signed in can't be checked without a network call.
if gcm_version=$(git credential-manager --version 2>/dev/null) && [ -n "$gcm_version" ]; then
  ok "git credential manager $(echo "$gcm_version" | first_version)"
else
  warn "git credential manager not found" \
       "it ships with Git for Windows; reinstall Git and keep the Credential Manager option"
fi

# 7. Line endings. A .sh file with Windows line endings (CRLF) fails in bash with
#    "$'\r': command not found". -U makes Git Bash's grep keep the carriage
#    returns it would otherwise drop, so it can find them.
CR=$(printf '\r')
crlf_files=""
while IFS= read -r file; do
  if grep -qU "$CR" "$file"; then
    crlf_files="$crlf_files ${file#"$PLUGIN_ROOT"/}"
  fi
done < <(find "$PLUGIN_ROOT" -name '*.sh' -type f)

if [ -z "$crlf_files" ]; then
  ok "plugin scripts use LF line endings"
else
  fail "scripts with CRLF line endings:$crlf_files" \
       "add '*.sh text eol=lf' to .gitattributes, then check the files out again"
fi

# 8. Windows only: the `bash` that PowerShell finds must be Git's (spike S2).
#    On Windows, Claude Code often runs commands through its PowerShell tool, and the
#    skills call `bash ...`. If PowerShell finds WSL's bash (C:\Windows\System32\bash.exe)
#    first, it can't run C:/ paths and every skill fails.
#    The check asks PowerShell itself: inside Git Bash, Git's usr\bin is always on the
#    PATH, so looking at this shell's PATH would prove nothing.
case "$platform" in
  MINGW*|MSYS*)
    git_root=$(cygpath -w /)              # where Git is installed, e.g. C:\Program Files\Git\
    git_usr_bin=$(cygpath -w /usr/bin)    # the folder that must be on the Windows PATH

    path_fix="add Git's usr\\bin to the SYSTEM Path, ahead of System32 (needs admin rights):
           1. Start > type 'Edit the system environment variables' > Environment Variables
           2. Under 'System variables' select Path > Edit > New, and paste:
              $git_usr_bin
           3. Click 'Move Up' until it is above %SystemRoot%\\system32, then OK
           4. Restart your terminals and Claude Code
           A User Path entry is not enough: Windows reads the System Path first."

    if ! command -v powershell.exe >/dev/null 2>&1; then
      warn "powershell.exe not found, can't check which bash PowerShell runs" \
           "run this check from a normal Git Bash window on Windows"
    else
      powershell_bash=$(powershell.exe -NoProfile -NonInteractive -Command \
        "(Get-Command bash -ErrorAction SilentlyContinue | Select-Object -First 1).Source" \
        2>/dev/null | tr -d '\r')

      # Compare in lower case: Windows paths are case-insensitive.
      if [ -z "$powershell_bash" ]; then
        fail "PowerShell finds no bash" "$path_fix"
      elif [[ "${powershell_bash,,}" == "${git_root,,}"* ]]; then
        ok "PowerShell runs Git's bash ($powershell_bash)"
      else
        fail "PowerShell runs $powershell_bash, not Git's bash" "$path_fix"
      fi
    fi
    ;;
esac

# 9. Development tools, only with --dev.
if [ "$DEV" -eq 1 ]; then
  if command -v bats >/dev/null 2>&1; then
    ok "bats $(bats --version | first_version)"
  else
    fail "bats not found" "install bats-core: npm install -g bats"
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    ok "shellcheck $(shellcheck --version | first_version)"
  else
    fail "shellcheck not found" "install shellcheck: winget install koalaman.shellcheck"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if [ "$FAILS" -eq 0 ]; then
  if [ "$QUIET" -eq 0 ]; then
    echo "All required checks passed ($WARNS warning(s))."
  fi
  exit 0
fi

echo "$FAILS check(s) failed, $WARNS warning(s). Fix the [FAIL] lines above."
exit 1
