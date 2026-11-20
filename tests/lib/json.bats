#!/usr/bin/env bats
# Tests for plugins/dc-harness/scripts/lib/json.sh. The S6 cases come from docs/spikes.md.

setup() {
  load ../test_helper
  source "$LIB_DIR/json.sh"
  cd "$BATS_TEST_TMPDIR" || exit 1
}

@test "json_get reads a value without a trailing \\r" {
  printf '{"branch":"main"}' > f.json
  run json_get f.json '.branch'
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
  # The S6 bug: jq on Windows prints main\r\n. Comparing must work as is.
  [[ "$output" != *$'\r'* ]]
}

@test "json_get reads a file with CRLF line endings" {
  printf '{\r\n  "step": "plan"\r\n}\r\n' > f.json
  run json_get f.json '.step'
  [ "$output" = "plan" ]
}

@test "json_get reads a file with a UTF-8 BOM" {
  printf '\xef\xbb\xbf{"a":"x"}' > f.json
  run json_get f.json '.a'
  [ "$status" -eq 0 ]
  [ "$output" = "x" ]
}

@test "json_get prints every line of a list without \\r" {
  printf '{"p":["Plan agreed","Plan OK"]}' > f.json
  run json_get f.json '.p[]'
  [ "${lines[0]}" = "Plan agreed" ]
  [ "${lines[1]}" = "Plan OK" ]
  [[ "$output" != *$'\r'* ]]
}

@test "json_get passes --arg through, keeping accents" {
  printf '{"p":["Especificación acordada"]}' > f.json
  run json_get f.json '.p[] | select(. == $x)' --arg x "Especificación acordada"
  [ "$output" = "Especificación acordada" ]
}

@test "json_get passes --arg values that start with / unchanged (Git Bash path conversion)" {
  printf '{}' > f.json
  run json_get f.json '$x' --arg x "/help"
  [ "$output" = "/help" ]
  run json_get_text '{}' '$x' --arg x "/usr/local is where it lives"
  [ "$output" = "/usr/local is where it lives" ]
}

@test "json_update stores --arg values that start with / unchanged" {
  json_update s.json '{t: $t}' --arg t "/dc:plan"
  [ "$(json_get s.json .t)" = "/dc:plan" ]
}

@test "json_get_merged: the second file wins, objects merge key by key" {
  printf '{"a":1,"o":{"x":1,"y":1},"l":[1,2]}' > d.json
  printf '{"o":{"y":2},"l":[3]}' > p.json
  [ "$(json_get_merged d.json p.json '[.a, .o.x, .o.y, (.l | length)] | join(",")')" = "1,1,2,1" ]
}

@test "json_get: '// empty' turns a missing key into an empty string" {
  printf '{}' > f.json
  run json_get f.json '.planSession // empty'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "json_get fails on a missing file" {
  run json_get missing.json '.a'
  [ "$status" -ne 0 ]
}

@test "json_get fails on a file that isn't JSON" {
  echo "not json" > f.json
  run json_get f.json '.a'
  [ "$status" -ne 0 ]
}

@test "json_get_text reads a payload held in a variable, accents kept" {
  payload='{"prompt":"Apruebo el plan, sí señor","session_id":"abc"}'
  run json_get_text "$payload" '.prompt'
  [ "$status" -eq 0 ]
  [ "$output" = "Apruebo el plan, sí señor" ]
}

@test "json_get_text keeps a multi-line prompt" {
  payload='{"prompt":"line one\nsí — señor"}'
  run json_get_text "$payload" '.prompt'
  [ "${lines[0]}" = "line one" ]
  [ "${lines[1]}" = "sí — señor" ]
}

@test "json_get_text fails on text that isn't JSON" {
  run json_get_text "nope" '.a'
  [ "$status" -ne 0 ]
}

@test "json_update creates a missing file" {
  run json_update new.json '{schemaVersion: 1, branch: $b}' --arg b "feature/x"
  [ "$status" -eq 0 ]
  [ "$(jq -r .branch new.json | tr -d '\r')" = "feature/x" ]
}

@test "json_update changes one key and keeps the others" {
  printf '{"schemaVersion":1,"step":"start-task","gate":"spec"}' > s.json
  json_update s.json '.step = $s' --arg s plan
  [ "$(json_get s.json .step)" = "plan" ]
  [ "$(json_get s.json .gate)" = "spec" ]
}

@test "json_update writes LF line endings" {
  json_update s.json '{a: 1, b: [1, 2]}'
  ! grep -qU $'\r' s.json
}

@test "json_update stores accented --arg text as UTF-8 (S6)" {
  json_update s.json '{text: $t}' --arg t "señor"
  # ñ is the two bytes 0xC3 0xB1.
  grep -q $'se\xc3\xb1or' s.json
  [ "$(json_get s.json .text)" = "señor" ]
}

@test "json_update leaves the file untouched when the filter fails" {
  printf '{"a":1}\n' > s.json
  run json_update s.json '.a | error("boom")'
  [ "$status" -ne 0 ]
  [ "$(cat s.json)" = '{"a":1}' ]
  # No temp files left behind.
  [ "$(ls | wc -l)" -eq 1 ]
}
