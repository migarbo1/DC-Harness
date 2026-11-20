# Shared setup for the bats tests. Load it with `load ../test_helper` (path relative to the
# .bats file).

REPO_ROOT=$(cd "$BATS_TEST_DIRNAME" && git rev-parse --show-toplevel)
LIB_DIR="$REPO_ROOT/plugins/dc-harness/scripts/lib"

# make_repo [DIR]: creates a git repo with one commit on `main`, and cds into it.
# Prints nothing. The repo lives in the test's own temp folder, deleted after the test.
make_repo() {
  local dir=${1:-"$BATS_TEST_TMPDIR/repo"}
  mkdir -p "$dir"
  cd "$dir" || return 1
  git init --quiet --initial-branch=main
  git config user.name "dc test"
  git config user.email "dc-test@example.invalid"
  git config core.autocrlf false
  echo "hello" > README.md
  git add README.md
  git commit --quiet -m "first"
}

# onboard: writes a minimal .harness/config.json in the current repo and commits it.
onboard() {
  mkdir -p .harness
  echo '{ "schemaVersion": 1 }' > .harness/config.json
  printf '.tasks/\n' > .gitignore
  git add .harness .gitignore
  git commit --quiet -m "onboard"
}

# hash FILE: SHA-256 of FILE's bytes.
hash() {
  sha256sum < "$1" | cut -d' ' -f1
}

# stage NAME: builds the task folder of feature/x up to NAME, as the skills and hooks would
# leave it. Each stage includes the ones before it.
#   started → spec → spec-approved → planned → plan-approved → cp1 → cp2 → assessed → finished
stage() {
  local target=$1 s
  for s in started spec spec-approved planned plan-approved cp1 cp2 assessed finished; do
    case "$s" in
      started)
        mkdir -p "$T"
        jq -n --arg c "$(git rev-parse HEAD)" '{schemaVersion: 1, branch: "feature/x",
          commitRef: $c, startedAt: "2026-11-20T10:00:00Z", step: "start-task", gate: "spec",
          planSession: null}' > "$T/state.json" ;;
      spec)
        printf '# Spec\n' > "$T/spec.md" ;;
      spec-approved)
        jq -n --arg h "$(hash "$T/spec.md")" '{schemaVersion: 1, spec: {sha256: $h}}' \
          > "$T/approvals.json" ;;
      planned)
        printf '# Plan\n\n## CP1: First\n### Tasks\n\n## CP2: Second\n' > "$T/plan.md"
        jq '.step = "plan" | .gate = "plan" | .planSession = "sess-plan"' "$T/state.json" \
          > "$T/s" && mv "$T/s" "$T/state.json" ;;
      plan-approved)
        jq --arg h "$(hash "$T/plan.md")" '.plan = {sha256: $h}' "$T/approvals.json" \
          > "$T/a" && mv "$T/a" "$T/approvals.json" ;;
      cp1)
        printf '## CP1: First\n### Changes\n' > "$T/implementation-notes.md" ;;
      cp2)
        printf '\n## CP2: Second\n' >> "$T/implementation-notes.md" ;;
      assessed)
        printf '# Assessment\n\nScore: 3/4 (passed)\n' > "$T/assessment.md" ;;
      finished)
        printf 'PR text\n' > "$T/pr-text.md" ;;
    esac
    [ "$s" = "$target" ] && return 0
  done
}

# state KEY: a value from feature/x's state.json.
state() {
  jq -r ".$1" "$T/state.json" | tr -d '\r'
}

# set_state FILTER [JQ_ARGS...]: changes feature/x's state.json, for example to put the task
# at a given step or gate: set_state '.step = "implement" | .gate = null'
set_state() {
  local filter=$1
  shift
  jq "$@" "$filter" "$T/state.json" > "$T/s" && mv "$T/s" "$T/state.json"
}

# approvals FILTER: a value from feature/x's approvals.json.
approvals() {
  jq -r "$1" "$T/approvals.json" | tr -d '\r'
}

FIXTURES="$REPO_ROOT/tests/fixtures/hooks"
HOOKS="$REPO_ROOT/plugins/dc-harness/scripts/hooks"

# hook NAME FIXTURE [FILTER [JQ_ARGS...]]: runs hooks/NAME.sh on a recorded payload from
# tests/fixtures/hooks/FIXTURE.json. The payload's cwd becomes the current directory, in
# Windows form on Git Bash, as Claude Code sends it; FILTER then changes other fields:
#   hook approval-capture user-prompt-submit '.prompt = $p' --arg p "Plan agreed"
# Results in $status, $output and $stderr (bats `run --separate-stderr`).
hook() {
  local name=$1 fixture=$2 filter=${3:-.} cwd payload
  shift 2
  [ $# -gt 0 ] && shift
  cwd=$(pwd)
  if command -v cygpath >/dev/null 2>&1; then
    cwd=$(cygpath -w "$cwd")
  fi
  # Path conversion off, so a prompt like "/help" reaches jq as typed (see lib/json.sh).
  payload=$(MSYS_NO_PATHCONV=1 jq --arg cwd "$cwd" "$@" ".cwd = \$cwd | $filter" \
    < "$FIXTURES/$fixture.json")
  run --separate-stderr bash "$HOOKS/$name.sh" <<< "$payload"
}

# out FILTER: a field of the hook's JSON output.
out() {
  printf '%s' "$output" | jq -r "$1" | tr -d '\r'
}

