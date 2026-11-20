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
#
# jq prints `null` for a missing key. Write the filter as `.key // empty` to get "" instead.

# json_get FILE FILTER [JQ_ARGS...]: prints FILTER applied to FILE, raw (-r), without `\r`.
# Fails when FILE is missing or not JSON.
#   json_get "$dir/state.json" '.branch'
#   json_get "$cfg" '.specApprovalPhrase[] | select(ascii_downcase == ($p | ascii_downcase))' --arg p "$prompt"
json_get() {
  local file=$1 filter=$2
  shift 2
  [ -f "$file" ] || return 1
  jq -r "$@" "$filter" "$file" | tr -d '\r'
  return "${PIPESTATUS[0]}"
}

# json_get_text TEXT FILTER [JQ_ARGS...]: like json_get, for JSON held in a variable (a hook
# payload). The text goes in through stdin.
#   prompt=$(json_get_text "$payload" '.prompt // empty')
json_get_text() {
  local text=$1 filter=$2
  shift 2
  printf '%s' "$text" | jq -r "$@" "$filter" | tr -d '\r'
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
    jq "$@" "$filter" "$file"
  else
    jq -n "$@" "$filter"
  fi | tr -d '\r' > "$tmp"

  if [ "${PIPESTATUS[0]}" -ne 0 ] || ! mv -f "$tmp" "$file"; then
    rm -f "$tmp"
    return 1
  fi
}
