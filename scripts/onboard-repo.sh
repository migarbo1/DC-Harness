#!/usr/bin/env bash
# onboard-repo.sh: sets a project repo up for DC-Harness.
# Maintainer and tech-lead tool. It is NOT shipped with the plugin.
#
# Usage: scripts/onboard-repo.sh [--marketplace SOURCE] <project-dir>
#   --marketplace SOURCE  where teammates get the plugin: a git URL (the harness repo in
#                         Azure DevOps) or a local folder holding .claude-plugin/marketplace.json.
#                         Without it, .claude/settings.json is left alone.
#
# What it does (each step is skipped when already done, so it can be re-run):
#   1. .harness/config.json  a copy of the plugin's defaults/config.json, every key visible
#   2. .harness/AGENTS.md    a copy of AGENTS.template.md, for the tech lead to tune
#   3. CLAUDE.md             gets the line `@.harness/AGENTS.md` (created if missing)
#   4. .gitignore            gets `.tasks/`
#   5. .claude/settings.json registers the marketplace and enables dc@dc-harness (with
#                            --marketplace), keeping every other setting
# It never overwrites the tech lead's .harness/ files and never commits.
#
# Exit codes: 0 done, 1 failed, 2 bad usage.

# SC2016: jq filters use $variables inside single quotes on purpose.
# shellcheck disable=SC2016
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/plugins/dc-harness"
# shellcheck source=SCRIPTDIR/../plugins/dc-harness/scripts/lib/json.sh
source "$PLUGIN_DIR/scripts/lib/json.sh"

MARKETPLACE_NAME=dc-harness   # the "name" in .claude-plugin/marketplace.json
PLUGIN_ID="dc@$MARKETPLACE_NAME"
IMPORT_LINE="@.harness/AGENTS.md"

usage() {
  echo "Usage: scripts/onboard-repo.sh [--marketplace SOURCE] <project-dir>"
}

MARKETPLACE=""
PROJECT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --marketplace) [ $# -ge 2 ] || { usage >&2; exit 2; }; MARKETPLACE=$2; shift ;;
    -h|--help)     usage; exit 0 ;;
    -*)            usage >&2; exit 2 ;;
    *)             [ -z "$PROJECT" ] || { usage >&2; exit 2; }; PROJECT=$1 ;;
  esac
  shift
done
[ -n "$PROJECT" ] || { usage >&2; exit 2; }

ok()   { echo "  [ok]   $1"; }
kept() { echo "  [kept] $1"; }
skip() { echo "  [skip] $1"; }
die()  { echo "  [FAIL] $1" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq not found (run plugins/dc-harness/scripts/doctor.sh)"
[ -d "$PROJECT" ] || die "no such folder: $PROJECT"
ROOT=$(git -C "$PROJECT" rev-parse --show-toplevel 2>/dev/null) || die "$PROJECT is not in a git repo"
cd "$ROOT" || die "can't enter $ROOT"

echo "DC-Harness onboarding: $ROOT"

# 1-2. .harness/ (the tech lead's files: never overwritten)
mkdir -p .harness || die "can't create .harness/"

if [ -f .harness/config.json ]; then
  kept ".harness/config.json (already there)"
else
  # Through jq: LF endings and a check that the defaults parse.
  json_get "$PLUGIN_DIR/defaults/config.json" '.' > .harness/config.json ||
    die "can't write .harness/config.json"
  ok ".harness/config.json (the plugin defaults)"
fi

if [ -f .harness/AGENTS.md ]; then
  kept ".harness/AGENTS.md (already there)"
else
  tr -d '\r' < "$PLUGIN_DIR/AGENTS.template.md" > .harness/AGENTS.md ||
    die "can't write .harness/AGENTS.md"
  ok ".harness/AGENTS.md (from AGENTS.template.md)"
fi

# 3. CLAUDE.md imports the rules. Claude Code reads CLAUDE.md and follows its @imports.
if [ -f CLAUDE.md ] && tr -d '\r' < CLAUDE.md | grep -qxF "$IMPORT_LINE"; then
  kept "CLAUDE.md already imports .harness/AGENTS.md"
else
  # Start on a new line when the file doesn't end with one.
  if [ -s CLAUDE.md ] && [ -n "$(tail -c 1 CLAUDE.md)" ]; then
    echo >> CLAUDE.md
  fi
  printf '%s\n' "$IMPORT_LINE" >> CLAUDE.md || die "can't write CLAUDE.md"
  ok "CLAUDE.md imports .harness/AGENTS.md"
fi

# 4. .gitignore
if [ -f .gitignore ] && tr -d '\r' < .gitignore | grep -qxF ".tasks/"; then
  kept ".gitignore already has .tasks/"
else
  if [ -s .gitignore ] && [ -n "$(tail -c 1 .gitignore)" ]; then
    echo >> .gitignore
  fi
  printf '# DC-Harness task folders (stay on the developer'"'"'s machine)\n.tasks/\n' >> .gitignore ||
    die "can't write .gitignore"
  ok ".gitignore has .tasks/"
fi

# 5. .claude/settings.json
if [ -z "$MARKETPLACE" ]; then
  skip ".claude/settings.json: no --marketplace given"
else
  if [ -d "$MARKETPLACE" ]; then
    [ -f "$MARKETPLACE/.claude-plugin/marketplace.json" ] ||
      die "$MARKETPLACE has no .claude-plugin/marketplace.json"
    path=$(cd "$MARKETPLACE" && pwd)
    command -v cygpath >/dev/null 2>&1 && path=$(cygpath -w "$path")
    source_json=$(jq -cn --arg p "$path" '{source: "directory", path: $p}')
  else
    source_json=$(jq -cn --arg u "$MARKETPLACE" '{source: "git", url: $u}')
  fi
  mkdir -p .claude || die "can't create .claude/"
  json_update .claude/settings.json \
    '(. // {}) | .extraKnownMarketplaces[$m] = {source: $s} | .enabledPlugins[$id] = true' \
    --arg m "$MARKETPLACE_NAME" --arg id "$PLUGIN_ID" --argjson s "$source_json" ||
    die "can't update .claude/settings.json (is it valid JSON?)"
  ok ".claude/settings.json enables $PLUGIN_ID from $(jq -r '.path // .url' <<< "$source_json" | tr -d '\r')"
fi

cat <<'EOF'

Next:
  - Review .harness/config.json. If the tools live in a virtual environment, set
    stackCommands (docs/contracts.md §1.2), for example
      "stackCommands": { "python": { "tests": ".venv/Scripts/python.exe -m pytest" } }
  - Tune .harness/AGENTS.md if needed.
  - Commit .harness/, CLAUDE.md, .gitignore and .claude/settings.json.
EOF
