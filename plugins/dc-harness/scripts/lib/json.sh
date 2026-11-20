#!/usr/bin/env bash
# lib/json.sh: every JSON read and write in the harness goes through these functions.
# Source it; it only defines functions.
#
# Rules from spike S6 (jq on Windows), applied here so callers can't forget them:
#   - jq prints `\r\n` on Windows: everything read back has `\r` stripped.
#   - Text goes into jq with --arg, --rawfile or stdin, NEVER through an environment
#     variable (env.X corrupts non-ASCII text).
#   - Files are written with LF endings, through a temp file, so a failed write leaves the
#     old file untouched.
# And one found in Phase 1: Git Bash rewrites arguments that start with `/` before a native
# program like jq.exe sees them (`--arg p /help` arrives as `C:/Program Files/Git/help`).
# So jq always runs with path conversion off (_jq), and files reach it through stdin, never
# as a path argument.
#
# jq prints `null` for a missing key. Write the filter as `.key // empty` to get "" instead.

# _jq ARGS...: jq with Git Bash's argument path conversion turned off. Harmless elsewhere.
_jq() {
  MSYS_NO_PATHCONV=1 jq "$@"
}

# json_get FILE FILTER [JQ_ARGS...]: prints FILTER applied to FILE, raw (-r), without `\r`.
# Fails when FILE is missing or not JSON.
#   json_get "$dir/state.json" '.branch'
#   json_get "$dir/approvals.json" '.spec.sha256 // empty'
json_get() {
  local file=$1 filter=$2
  shift 2
  [ -f "$file" ] || return 1
  _jq -r "$@" "$filter" < "$file" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

# json_get_text TEXT FILTER [JQ_ARGS...]: like json_get, for JSON held in a variable (a hook
# payload). The text goes in through stdin.
#   prompt=$(json_get_text "$payload" '.prompt // empty')
json_get_text() {
  local text=$1 filter=$2
  shift 2
  printf '%s' "$text" | _jq -r "$@" "$filter" | tr -d '\r'
  return "${PIPESTATUS[1]}"
}

# json_get_merged FILE1 FILE2 FILTER [JQ_ARGS...]: like json_get, on FILE1 * FILE2 (jq deep
# merge: objects merge key by key, FILE2 wins). For config: defaults * project.
json_get_merged() {
  local first=$1 second=$2 filter=$3
  shift 3
  [ -f "$first" ] && [ -f "$second" ] || return 1
  cat "$first" "$second" | _jq -r -s "$@" ".[0] * .[1] | $filter" | tr -d '\r'
  return "${PIPESTATUS[1]}"
}

# json_update FILE FILTER [JQ_ARGS...]: rewrites FILE with FILTER applied to it. When FILE
# doesn't exist, FILTER starts from null, so the same call creates it:
#   json_update "$dir/state.json" '.step = $s | .gate = $g' --arg s plan --arg g plan
# Writes to a temp file in the same folder, then moves it over FILE.
json_update() {
  local file=$1 filter=$2 tmp
  shift 2
  tmp=$(mktemp "$file.XXXXXX") || return 1

  # tr: LF endings on every platform, so the files read the same everywhere and in fixtures.
  if [ -f "$file" ]; then
    _jq "$@" "$filter" < "$file"
  else
    _jq -n "$@" "$filter"
  fi | tr -d '\r' > "$tmp"

  if [ "${PIPESTATUS[0]}" -ne 0 ] || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
}
