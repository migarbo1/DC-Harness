#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/lib/hash.sh.

setup() {
  load ../test_helper
  source "$LIB_DIR/hash.sh"
  cd "$BATS_TEST_TMPDIR" || exit 1
}

@test "sha256_file prints the known hash of 'abc'" {
  printf 'abc' > f.md
  run sha256_file f.md
  [ "$status" -eq 0 ]
  [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}

@test "sha256_file works on a path with spaces and a backslash-free name" {
  mkdir "a folder"
  printf 'abc' > "a folder/spec.md"
  run sha256_file "a folder/spec.md"
  [ "$output" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ]
}

@test "sha256_file hashes raw bytes: CRLF and LF differ" {
  printf 'a\n' > lf.md
  printf 'a\r\n' > crlf.md
  [ "$(sha256_file lf.md)" != "$(sha256_file crlf.md)" ]
}

@test "sha256_file changes when the file changes" {
  printf 'v1' > f.md
  before=$(sha256_file f.md)
  printf 'v2' > f.md
  [ "$(sha256_file f.md)" != "$before" ]
}

@test "sha256_file fails on a missing file" {
  run sha256_file missing.md
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}
