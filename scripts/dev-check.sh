#!/usr/bin/env bash
# dev-check.sh: checks the harness repo before a commit or a release.
# Maintainer tool. It is NOT shipped with the plugin.
#
# Usage: scripts/dev-check.sh
#
# It runs five checks:
#   1. JSON       every .json file parses
#   2. Shell      shellcheck passes on every .sh file
#   3. Schemas    each schema compiles, and the files it describes match it
#   4. Tests      the bats tests in tests/ pass
#
# Exit codes:
#   0  every check passed
#   1  at least one check failed
#   2  bad usage
#
# Read-only: it never changes a file.

set -u

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# The repo root is the folder above this script's folder (scripts/).
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

PLUGIN_DIR="$REPO_ROOT/plugins/dc-harness"
SCHEMA_DIR="$PLUGIN_DIR/schemas"
DEFAULTS_DIR="$PLUGIN_DIR/defaults"
TESTS_DIR="$REPO_ROOT/tests"
SCHEMA_FIXTURES_DIR="$TESTS_DIR/fixtures/schemas"

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

case "${1:-}" in
  "") ;;
  -h|--help) echo "Usage: scripts/dev-check.sh"; exit 0 ;;
  *) echo "Usage: scripts/dev-check.sh" >&2; exit 2 ;;
esac

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

FAILS=0

# section TITLE
section() {
  echo
  echo "== $1"
}

# ok MESSAGE
ok() {
  echo "  [ok]   $1"
}

# skip MESSAGE: nothing to check yet (for example, no tests written so far).
skip() {
  echo "  [skip] $1"
}

# fail MESSAGE
fail() {
  FAILS=$((FAILS + 1))
  echo "  [FAIL] $1"
}

# show_output TEXT: prints a tool's output indented, under the [FAIL] line.
show_output() {
  local line
  while IFS= read -r line; do
    echo "         $line"
  done <<< "$1"
}

# relative PATH: PATH without the repo root in front, to keep messages short.
relative() {
  echo "${1#"$REPO_ROOT"/}"
}

# list_files PATTERN: prints every file in the repo matching PATTERN, one per line.
# Skips .git, node_modules and __OLD (the previous attempt, kept for reference only).
list_files() {
  find "$REPO_ROOT" \
    \( -name .git -o -name node_modules -o -name __OLD \) -prune \
    -o -type f -name "$1" -print
}

echo "DC-Harness dev-check ($REPO_ROOT)"

# ---------------------------------------------------------------------------
# 1. JSON: every .json file parses
# ---------------------------------------------------------------------------

section "JSON syntax"

mapfile -t json_files < <(list_files '*.json')
bad=0
for file in "${json_files[@]}"; do
  if ! output=$(jq empty "$file" 2>&1); then
    fail "$(relative "$file") is not valid JSON"
    show_output "$output"
    bad=1
  fi
done
if [ "$bad" -eq 0 ]; then
  ok "${#json_files[@]} file(s) parse"
fi

# ---------------------------------------------------------------------------
# 2. Shell: shellcheck on every .sh file
# ---------------------------------------------------------------------------

section "Shell scripts"

mapfile -t sh_files < <(list_files '*.sh')
if [ "${#sh_files[@]}" -eq 0 ]; then
  skip "no .sh files"
else
  bad=0
  for file in "${sh_files[@]}"; do
    # -x follows `source` lines, so functions from lib/ are known.
    if ! output=$(shellcheck -x "$file" 2>&1); then
      fail "$(relative "$file")"
      show_output "$output"
      bad=1
    fi
  done
  if [ "$bad" -eq 0 ]; then
    ok "${#sh_files[@]} script(s) pass shellcheck"
  fi
fi

# ---------------------------------------------------------------------------
# 3. Schemas: each schema compiles, and the files it describes match it
#
# For a schema plugins/dc-harness/schemas/<name>.schema.json, the files checked are:
#   plugins/dc-harness/defaults/<name>.json           (if it exists)
#   tests/fixtures/schemas/<name>/valid/*.json        must match
#   tests/fixtures/schemas/<name>/invalid/*.json      must NOT match
# ---------------------------------------------------------------------------

section "JSON schemas"

# ajv_validate SCHEMA DATA: succeeds when DATA matches SCHEMA. Prints ajv's output.
ajv_validate() {
  ajv validate --spec=draft2020 --strict=false -s "$1" -d "$2" 2>&1
}

if ! compgen -G "$SCHEMA_DIR/*.schema.json" >/dev/null; then
  skip "no schemas in $(relative "$SCHEMA_DIR") yet"
else
  for schema in "$SCHEMA_DIR"/*.schema.json; do
    name=$(basename "$schema" .schema.json)

    # The schema itself must be a valid draft 2020-12 schema.
    if ! output=$(ajv compile --spec=draft2020 --strict=false -s "$schema" 2>&1); then
      fail "$(relative "$schema") does not compile"
      show_output "$output"
      continue
    fi
    ok "$(relative "$schema") compiles"

    # The default file, if the schema has one.
    default_file="$DEFAULTS_DIR/$name.json"
    if [ -f "$default_file" ]; then
      if output=$(ajv_validate "$schema" "$default_file"); then
        ok "$(relative "$default_file") matches"
      else
        fail "$(relative "$default_file") does not match $name.schema.json"
        show_output "$output"
      fi
    fi

    # Fixtures that must match.
    for file in "$SCHEMA_FIXTURES_DIR/$name/valid/"*.json; do
      [ -f "$file" ] || continue
      if output=$(ajv_validate "$schema" "$file"); then
        ok "$(relative "$file") matches"
      else
        fail "$(relative "$file") should match but does not"
        show_output "$output"
      fi
    done

    # Fixtures that must be rejected. This proves the schema actually restricts something.
    for file in "$SCHEMA_FIXTURES_DIR/$name/invalid/"*.json; do
      [ -f "$file" ] || continue
      if ajv_validate "$schema" "$file" >/dev/null; then
        fail "$(relative "$file") should be rejected but matches"
      else
        ok "$(relative "$file") is rejected"
      fi
    done
  done
fi

# ---------------------------------------------------------------------------
# 4. Tests: bats
# ---------------------------------------------------------------------------

section "Tests"

if [ -z "$(list_files '*.bats' | head -n 1)" ]; then
  skip "no .bats files yet"
else
  # --recursive finds tests in subfolders of tests/.
  if output=$(bats --recursive "$TESTS_DIR" 2>&1); then
    ok "bats tests pass"
  else
    fail "bats tests failed"
    show_output "$output"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo
if [ "$FAILS" -eq 0 ]; then
  echo "dev-check passed."
  exit 0
fi
echo "dev-check failed: $FAILS problem(s). See the [FAIL] lines above."
exit 1
