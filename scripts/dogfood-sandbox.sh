#!/usr/bin/env bash
# dogfood-sandbox.sh: builds a disposable copy of the dogfood project with the development
# version of the harness installed, to develop and try the skills and hooks.
# Maintainer tool. It is NOT shipped with the plugin.
#
# Usage: scripts/dogfood-sandbox.sh [--source DIR] [--target DIR] [--force] [--no-venv]
#   --source DIR  the dogfood project to copy (default: ../dogfood-repo, next to this repo)
#   --target DIR  where to build the sandbox (default: ../dc-sandbox, next to this repo)
#   --force       delete and rebuild the target if it is an earlier sandbox
#   --no-venv     skip creating .venv and installing the project (faster; no checks run)
#
# What it does:
#   1. Copies the dogfood project without its .venv, caches and build output.
#   2. Creates .venv and installs the project with its dev extras (pip install -e ".[dev]").
#   3. Onboards it with onboard-repo.sh (.harness/, CLAUDE.md import line, `.tasks/` in
#      .gitignore), then sets stackCommands to the venv's python.
#   4. Wires the plugin to THIS working tree, two ways:
#        - `claude plugin marketplace add/install --scope project` registers this repo as a
#          directory marketplace and enables dc@dc-harness in .claude/settings.json (used by
#          the desktop app and by plain `claude`). A relative-path plugin in a local
#          marketplace is read in place from plugins/dc-harness.
#        - dev-claude.sh starts the CLI with --plugin-dir, which also loads in place and wins
#          over the settings copy when both are present.
#      Either way, edits apply after /reload-plugins or in a new session, with no version bump.
#   5. One commit on `main` (the repo is created in step 3), then a `sandbox` branch to work
#      on (main is protected).
#   6. Runs the full checks (ruff, ruff format, mypy, pytest) once and times them.
#
# Exit codes:
#   0  sandbox built (and checks green, unless --no-venv)
#   1  something failed
#   2  bad usage

set -u

# ---------------------------------------------------------------------------
# Paths and arguments
# ---------------------------------------------------------------------------

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
PLUGIN_DIR="$REPO_ROOT/plugins/dc-harness"
PARENT_DIR=$(cd "$REPO_ROOT/.." && pwd)

MARKETPLACE=dc-harness          # the "name" in .claude-plugin/marketplace.json
MARKER=.dc-sandbox              # file that proves a folder is a sandbox, so --force may delete it

SOURCE="$PARENT_DIR/dogfood-repo"
TARGET="$PARENT_DIR/dc-sandbox"
FORCE=0
VENV=1

usage() {
  echo "Usage: scripts/dogfood-sandbox.sh [--source DIR] [--target DIR] [--force] [--no-venv]"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --source)  [ $# -ge 2 ] || { usage >&2; exit 2; }; SOURCE=$2; shift ;;
    --target)  [ $# -ge 2 ] || { usage >&2; exit 2; }; TARGET=$2; shift ;;
    --force)   FORCE=1 ;;
    --no-venv) VENV=0 ;;
    -h|--help) usage; exit 0 ;;
    *)         usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

step() { echo; echo "== $1"; }
ok()   { echo "  [ok]   $1"; }
die()  { echo "  [FAIL] $1" >&2; exit 1; }

# win_path PATH: the Windows form (C:/x/y) on Git Bash, unchanged elsewhere.
# Claude Code reads settings.json paths as native paths, not /c/x/y.
win_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}

for tool in git jq tar; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool not found (run plugins/dc-harness/scripts/doctor.sh --dev)"
done

[ -d "$SOURCE" ] || die "source project not found: $SOURCE"
SOURCE=$(cd "$SOURCE" && pwd)

echo "DC-Harness dogfood sandbox"
echo "  source: $SOURCE"
echo "  target: $TARGET"
echo "  plugin: $PLUGIN_DIR"

# ---------------------------------------------------------------------------
# 1. Copy the project
# ---------------------------------------------------------------------------

step "Copy the dogfood project"

if [ -e "$TARGET" ]; then
  if [ "$FORCE" -eq 0 ]; then
    die "$TARGET already exists; use --force to rebuild it"
  fi
  # Only delete folders this script built.
  [ -f "$TARGET/$MARKER" ] || die "$TARGET exists but is not a sandbox (no $MARKER); not deleting it"
  rm -rf "$TARGET" || die "could not delete $TARGET (is a terminal or editor open in it?)"
  ok "deleted the previous sandbox"
fi

mkdir -p "$TARGET" || die "could not create $TARGET"
TARGET=$(cd "$TARGET" && pwd)

# A copied .venv keeps absolute paths to the source, so it is rebuilt instead.
tar -C "$SOURCE" -cf - \
  --exclude=./.git --exclude=./.venv --exclude=./.tasks --exclude=./.harness \
  --exclude='*.egg-info' --exclude=__pycache__ \
  --exclude=.mypy_cache --exclude=.ruff_cache --exclude=.pytest_cache \
  --exclude=.coverage --exclude=htmlcov \
  . | tar -C "$TARGET" -xf - || die "copy failed"
echo "Built by nunsys-harness/scripts/dogfood-sandbox.sh. Safe to delete." > "$TARGET/$MARKER"
ok "copied to $TARGET"

# ---------------------------------------------------------------------------
# 2. Virtual environment
# ---------------------------------------------------------------------------

# The stack commands call the venv's python directly, so nobody has to activate it.
if [ -d /c ] || [ "${OS:-}" = "Windows_NT" ]; then
  VENV_PY=".venv/Scripts/python.exe"
else
  VENV_PY=".venv/bin/python"
fi

if [ "$VENV" -eq 1 ]; then
  step "Create .venv and install the project"

  # Prefer the Windows launcher (py), then python3, then python.
  # python3 alone can be the Microsoft Store stub on Windows, so it is tried after py.
  PYTHON=""
  for candidate in "py -3" python3 python; do
    if $candidate -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)' >/dev/null 2>&1; then
      PYTHON=$candidate
      break
    fi
  done
  [ -n "$PYTHON" ] || die "no Python 3.12+ found (the dogfood project needs it)"

  (cd "$TARGET" && $PYTHON -m venv .venv) || die "python -m venv failed"
  ok "created .venv ($($PYTHON --version 2>&1))"

  (cd "$TARGET" && "$VENV_PY" -m pip install --quiet --disable-pip-version-check -e ".[dev]") \
    || die "pip install -e .[dev] failed"
  ok "installed the project with its dev extras"
fi

# ---------------------------------------------------------------------------
# 3. Onboard, with onboard-repo.sh (it needs a git repo, so git init comes first)
# ---------------------------------------------------------------------------

step "Onboard the project"

git -C "$TARGET" init --quiet --initial-branch=main || die "git init failed"
onboard_out=$(bash "$SCRIPT_DIR/onboard-repo.sh" "$TARGET") ||
  { echo "$onboard_out"; die "onboard-repo.sh failed"; }
printf '%s\n' "$onboard_out" | grep -E '^ +\[' || true

# The dogfood project's real commands, through the venv's python (hooks don't activate it).
# `mypy` with no path: pyproject.toml lists the files ([tool.mypy] files).
if ! jq --arg py "$VENV_PY" '
  .stackCommands = {
    python: {
      lint:  ($py + " -m ruff check . && " + $py + " -m ruff format --check ."),
      types: ($py + " -m mypy"),
      tests: ($py + " -m pytest")
    }
  }' "$TARGET/.harness/config.json" | tr -d '\r' > "$TARGET/.harness/config.tmp"; then
  die "could not set stackCommands in .harness/config.json"
fi
mv -f "$TARGET/.harness/config.tmp" "$TARGET/.harness/config.json"
ok ".harness/config.json: stackCommands use $VENV_PY"

printf '%s\n' "$MARKER" >> "$TARGET/.gitignore"

# ---------------------------------------------------------------------------
# 4. Wire the plugin to this working tree
# ---------------------------------------------------------------------------

step "Wire the development plugin"

# Writing .claude/settings.json by hand is not enough: Claude Code skips a project's declared
# marketplaces until the folder is trusted, and the plugin needs an install record. The CLI's
# own commands do both, and write the same settings.json.
command -v claude >/dev/null 2>&1 || die "claude CLI not found on PATH (needed to register the plugin)"
(
  cd "$TARGET" &&
  claude plugin marketplace add "$(win_path "$REPO_ROOT")" --scope project >/dev/null &&
  claude plugin install "dc@$MARKETPLACE" --scope project >/dev/null
) || die "could not register the marketplace or install dc@$MARKETPLACE"
ok ".claude/settings.json enables dc@$MARKETPLACE, read from $(win_path "$PLUGIN_DIR")"

# The launcher quotes the plugin path, which has spaces (spike S4).
cat > "$TARGET/dev-claude.sh" <<EOF
#!/usr/bin/env bash
# Starts Claude Code in this sandbox with the dc plugin read straight from the harness
# working tree. Edits to skills and hooks apply on the next session (or /clear).
cd "\$(dirname "\${BASH_SOURCE[0]}")" || exit 1
exec claude --plugin-dir "$(win_path "$PLUGIN_DIR")" "\$@"
EOF
chmod +x "$TARGET/dev-claude.sh"
ok "dev-claude.sh starts the CLI with --plugin-dir"

# ---------------------------------------------------------------------------
# 5. Git
# ---------------------------------------------------------------------------

step "Initialise git"

(
  cd "$TARGET" &&
  # The repo was created before onboarding (step 3).
  # Keep files as copied (LF): a global core.autocrlf=true would warn on every file and
  # convert line endings that the hooks hash.
  git config core.autocrlf false &&
  git add -A &&
  git commit --quiet -m "Dogfood sandbox baseline" &&
  git switch --quiet -c sandbox
) || die "git init or the first commit failed (is git user.name/user.email set?)"
ok "repo on branch 'sandbox', baseline commit on 'main'"

# ---------------------------------------------------------------------------
# 6. Full checks, timed
# ---------------------------------------------------------------------------

FAILED=0
if [ "$VENV" -eq 1 ]; then
  step "Run the full checks"

  # run_check NAME KEY: runs stackCommands.python.KEY from config.json and times it.
  run_check() {
    local name=$1 key=$2 cmd start end output
    cmd=$(jq -r --arg k "$key" '.stackCommands.python[$k]' "$TARGET/.harness/config.json" | tr -d '\r')
    start=$(date +%s%N)
    if output=$(cd "$TARGET" && bash -c "$cmd" 2>&1); then
      end=$(date +%s%N)
      ok "$name ($(( (end - start) / 1000000 )) ms): $cmd"
    else
      FAILED=1
      echo "  [FAIL] $name: $cmd"
      while IFS= read -r line; do echo "         $line"; done <<< "$output"
    fi
  }

  run_check lint  lint
  run_check types types
  run_check tests tests
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

TARGET_WIN=$(win_path "$TARGET")
echo
if [ "$FAILED" -ne 0 ]; then
  echo "Sandbox built at $TARGET_WIN, but the checks are not green. See the [FAIL] lines."
  exit 1
fi
cat <<EOF
Sandbox ready at $TARGET_WIN

  CLI (live plugin):   "$TARGET_WIN/dev-claude.sh"
  Desktop app:         open $TARGET_WIN as the project folder and accept the trust dialog.
                       The plugin comes from .claude/settings.json and loads in place.
  After an edit:       /reload-plugins in the running session, or start a new session.
  Rebuild from scratch: scripts/dogfood-sandbox.sh --force
EOF
