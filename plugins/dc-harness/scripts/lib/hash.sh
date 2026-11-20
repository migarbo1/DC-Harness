#!/usr/bin/env bash
# lib/hash.sh: file hashes for the approval gates (contracts §3).
# Source it; it only defines functions.

# sha256_file FILE: prints the SHA-256 of FILE's raw bytes, as 64 lowercase hex characters.
# Fails when FILE is missing. Nothing converts line endings, so CRLF and LF files differ.
sha256_file() {
  local file=$1 out
  [ -f "$file" ] || return 1
  # Read from stdin: with a file name, sha256sum prefixes the hash with `\` when the name has
  # a backslash or newline.
  out=$(sha256sum < "$file") || return 1
  printf '%s\n' "${out%% *}"
}
