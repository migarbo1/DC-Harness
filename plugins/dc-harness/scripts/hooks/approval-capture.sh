#!/usr/bin/env bash
# approval-capture.sh: the UserPromptSubmit hook (contracts §3.2).
#
# Records the developer's own words in .tasks/<folder>/approvals.json:
#   - while the spec or plan gate is open: an approval phrase typed on its own, with the hash
#     of spec.md / plan.md at that moment;
#   - while the assessment gate is open: every prompt, word for word.
# It never blocks a prompt. It writes approvals.json only, never state.json.

# SC2016: jq filters use $variables inside single quotes on purpose.
# shellcheck disable=SC2016
# Case-insensitive matching must work for accented phrases ("Especificación acordada").
export LC_ALL=C.UTF-8
set -u

# shellcheck source=SCRIPTDIR/../lib/hook.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/hook.sh"

EVENT=UserPromptSubmit
hook_init
APPROVALS="$TASK_DIR/approvals.json"

PROMPT=$(json_get_text "$PAYLOAD" '.prompt // empty') || fail_open

# trim TEXT: TEXT without leading and trailing whitespace (newlines included).
trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# save FILTER [JQ_ARGS...]: updates approvals.json, creating it on the first record.
save() {
  local filter=$1
  shift
  json_update "$APPROVALS" "(. // {schemaVersion: 1}) | $filter" "$@" || fail_open
}

TRIMMED=$(trim "$PROMPT")

# ---------------------------------------------------------------------------
# Step 2: /dc:assessment (or /assessment) starts a fresh answer list.
# The command fires this hook before the skill runs task-state.sh, so this can't wait for
# the gate. A finished task keeps its answers (a refused run must not wipe them).
# ---------------------------------------------------------------------------

if [[ "$TRIMMED" =~ ^/(dc:)?assessment([[:space:]]|$) ]]; then
  if ! task_is_finished "$TASK_DIR"; then
    save '.assessment = []'
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 3: act on the open gate.
# ---------------------------------------------------------------------------

# approval KIND FILE PHRASES_KEY NEXT: the spec or plan gate.
approval() {
  local kind=$1 file=$2 key=$3 next=$4 phrase typed lowered found_inside=0
  local -a phrases

  # Approvals have to be typed: anything pasted doesn't count (spike S3).
  [[ "$PROMPT" == *"<pasted_content"* ]] && return 0

  mapfile -t phrases < <(config_get "$ROOT" ".${key}[]?")
  lowered=${TRIMMED,,}
  for phrase in "${phrases[@]}"; do
    typed=$(trim "$phrase")
    [ -n "$typed" ] || continue
    if [ "$lowered" = "${typed,,}" ]; then
      # Approving a file that doesn't exist records nothing.
      [ -f "$TASK_DIR/$file" ] || return 0
      save ".$kind = {phrase: \$p, at: \$t, session: \$s, sha256: \$h}" \
        --arg p "$TRIMMED" --arg t "$(now_utc)" --arg s "$SESSION_ID" \
        --arg h "$(sha256_file "$TASK_DIR/$file")"
      emit "$EVENT" allow "" "" "$next"
      return 0
    fi
    [[ "$lowered" == *"${typed,,}"* ]] && found_inside=1
  done

  if [ "$found_inside" -eq 1 ]; then
    emit "$EVENT" allow "" "Not recorded as approval: type the phrase on its own." ""
  fi
}

case "$GATE" in
  spec)
    approval spec spec.md specApprovalPhrase \
      "Spec approval recorded. Tell the developer to run /dc:plan. Do nothing else."
    ;;
  plan)
    approval plan plan.md planApprovalPhrase \
      "Plan approval recorded. Tell the developer to run /clear, then /dc:implement. Do nothing else."
    ;;
  assessment)
    # Other commands typed during the assessment are not answers.
    [[ "$TRIMMED" == /* ]] && exit 0
    # Answers may be pasted: keep the text, drop the client's wrapper tags. Both tags carry
    # the id: <pasted_content id="5405"> … </pasted_content id="5405">.
    TEXT=$(json_get_text "$PAYLOAD" '.prompt | gsub("</?pasted_content[^>]*>"; "")') || fail_open
    TEXT=$(trim "$TEXT")
    save '.assessment = ((.assessment // []) + [{at: $t, session: $s, text: $x}])' \
      --arg t "$(now_utc)" --arg s "$SESSION_ID" --arg x "$TEXT"
    ;;
esac
exit 0
