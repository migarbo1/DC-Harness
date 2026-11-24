# Contracts

The formats and interfaces that the scripts, hooks and skills agree on. Phase 1 code is written
against this file; when the two disagree, fix the code or change this file on purpose.

| # | Contract | Status |
| --- | --- | --- |
| 1 | [`config.json`](#1-configjson) | Agreed |
| 2 | [`state.json`](#2-statejson) | Agreed |
| 3 | [`approvals.json`](#3-approvalsjson) | Agreed |
| 4 | [`task-state.sh <skill>`](#4-task-statesh): preconditions, exit codes, refusals | Agreed |
| 5 | [Hooks](#5-hooks): input, output, `hooks.json` | Agreed |
| 6 | [Fixed markers in the artefacts](#6-fixed-markers-in-the-artefacts) | Agreed |

General rules for every JSON file below:

- **`schemaVersion`** is written in every file (currently `1`) and never checked at runtime.
- **Nothing is validated at runtime.** The files in `plugins/dc-harness/schemas/` are
  documentation and editor autocomplete. Unknown keys are ignored.
- **Reading and writing go through `lib/json.sh`** (from spike S6): strip `\r` from everything read
  back from jq; pass text into jq with `--arg`, `--rawfile` or stdin, never through an environment
  variable. `json_update` strips the `\r` that jq writes on Windows, so the files have LF line
  endings on every platform.
- **Git Bash rewrites arguments that start with `/`** before a native program like `jq.exe` sees
  them (`--arg p /help` arrives as `C:/Program Files/Git/help`). `lib/json.sh` and `emit` run jq
  with `MSYS_NO_PATHCONV=1` and pass files through stdin, never as path arguments (found in
  Phase 1).
- Times are ISO 8601 in UTC (`date -u +%FT%TZ`), for example `2026-11-19T10:15:00Z`.

## 1. `config.json`

The tech lead's settings for one project.

**Files:**

| File | Ships in | Holds |
| --- | --- | --- |
| `plugins/dc-harness/defaults/config.json` | plugin | A default for every key that applies to all stacks |
| `plugins/dc-harness/stacks/<stack>/default.json` | plugin | That stack's default commands |
| `<project>/.harness/config.json` | project repo (committed) | The project's values |

- **Onboarded** means `.harness/config.json` exists at the repo root. Without it, every hook
  exits silently and `task-state.sh` refuses (check G1, §4.3).
- **Only the tech lead edits `.harness/`.** `harness-guard.sh` blocks the agent from writing it.
- `onboard-repo.sh` copies the full `defaults/config.json` into `.harness/config.json`, so the
  tech lead sees every key.
- **Reading:** scripts read `defaults/config.json * .harness/config.json` (jq deep merge: objects
  merge key by key, arrays and scalars are replaced). A key missing from an older project config
  falls back to its default. Nothing is ever written back into the project's file.
- Schema: `plugins/dc-harness/schemas/config.schema.json`.

### 1.1 Keys

| Key | Type | Default | Read by | Meaning |
| --- | --- | --- | --- | --- |
| `schemaVersion` | integer | `1` | — | Format version. Not checked |
| `stack` | string[] | `["python"]` | `stop-check.sh`, `/dc:implement` | The stacks in this repo, in the order their checks run. Each name is a folder in `stacks/` |
| `stackCommands` | object | `{}` | `stack-check.sh` | Per-stack command overrides, keyed by stack name (§1.2) |
| `protectedBranches` | string[] | `["main", "master", "develop"]` | `task-state.sh start-task` | `/dc:start-task` refuses on these branches. Entries are bash glob patterns, so `release/*` works |
| `specApprovalPhrase` | string[] | `["Specification agreed"]` | `approval-capture.sh` | Any one of these approves `spec.md` (§1.3) |
| `planApprovalPhrase` | string[] | `["Plan agreed"]` | `approval-capture.sh` | Any one of these approves `plan.md` (§1.3) |
| `assessment.numQuestions` | integer | `4` | `/dc:assessment` | How many questions the assessment asks. Fixed, not based on the diff size |
| `assessment.passThreshold` | number 0–1 | `0.7` | `/dc:assessment` | Passed when passed ÷ total ≥ threshold. With 4 questions, 3/4 passes and 2/4 doesn't |
| `assessment.maxRetriesPerQuestion` | integer | `2` | `/dc:assessment` | Retries allowed after the first wrong or "not sure" answer |
| `prTextMaxChars` | integer | `3000` | `/dc:pr-text` | Hard limit on `pr-text.md`. Azure DevOps PR descriptions allow 4,000 |

```json
{
  "schemaVersion": 1,
  "stack": ["python"],
  "stackCommands": {},
  "protectedBranches": ["main", "master", "develop"],
  "specApprovalPhrase": ["Specification agreed"],
  "planApprovalPhrase": ["Plan agreed"],
  "assessment": { "passThreshold": 0.7, "maxRetriesPerQuestion": 2, "numQuestions": 4 },
  "prTextMaxChars": 3000
}
```

### 1.2 Stack commands

Each stack has three commands: `lint`, `types` and `tests`. Its defaults live in
`stacks/<stack>/default.json`:

```json
{ "lint": "ruff check . && ruff format --check .", "types": "mypy", "tests": "pytest" }
```

The Python defaults are the dogfood project's own checks (Phase 0 step 5). `mypy` has no path, so
it checks the files listed in the project's `[tool.mypy] files`; a path on the command line would
replace that list. On the dogfood sandbox the full run takes about 6 s (lint 0.7 s, mypy 2.9 s,
pytest 2.1 s; 2026-11-20).

The defaults are bare commands: they expect the tools on the `PATH`. Hooks run from the Claude
Code process, which doesn't activate the project's virtual environment, so a project whose tools
live in a venv overrides the commands to call them through it (for example
`.venv/Scripts/python.exe -m pytest`, or `uv run pytest`).

A project overrides only what differs:

```json
"stackCommands": {
  "python": { "types": null, "tests": "uv run pytest" }
}
```

**Lookup**, for each stack in `stack` and each of `lint`, `types`, `tests`:

1. The key is in the project's `stackCommands.<stack>`: use it. `null` or `""` means **skip that
   check**.
2. Otherwise: use `stacks/<stack>/default.json`.
3. Neither has the key: skip that check.

In jq: `$stackDefault * ($project.stackCommands[$s] // {})`. jq's `*` keeps an explicit `null`
from the right-hand side, so an opt-out survives the merge.

Consequences:

- A stack listed in `stack` but absent from `stackCommands` runs with all its default commands.
- To turn a whole stack off, remove it from `stack`.
- A stack name with no `stacks/<name>/` folder is an error (the plugin has no checks for it).

**Running the checks** (`stack-check.sh affected|full`):

- Stacks run in the order of `stack`. The check fails if any stack fails.
- Each stack's `stack-check.sh` receives the full list of changed files and picks its own (for
  example `*.py`).
- Commands run from the repo root. A stack in a subfolder puts the `cd` in the command itself, for
  example `cd backend && pytest`.
- `full` runs `tests` as written. `affected` appends the chosen test file paths to the end of
  `tests`, so it must be a command that accepts paths (pytest does).
- Every check runs even when an earlier one fails, so the agent sees all failures at once. A
  passing check prints one line (`-- python lint passed: <command>`); a failing one prints its
  whole output between `== python lint FAILED: <command>` and `-- python lint FAILED`. The Stop
  hook keeps the last 40 lines, so they are about what failed, not a passing pytest report.
- Exit codes: `0` all passed (or nothing to check), `1` a check failed, `2` can't run (not a git
  repo, not onboarded, no or unknown stack, bad usage), with a `dc: internal:` line on stderr.

**Python `affected`** (`stacks/python/stack-check.sh`):

- No `.py` file in the list: nothing runs, pass.
- Otherwise `lint` and `types` run as written, on the whole project (on the dogfood project they
  take under 4 s together), and `tests` gets the affected test files:
  - changed test files (`test_*.py`, `*_test.py`) that still exist;
  - for each other changed module `<folder>/<name>.py`: the test files anywhere in the repo named
    `test_<x>.py` or `<x>_test.py`, where `<x>` is `<name>`, `<folder>` or `<folder>` without a
    final `s` (`services/arithmetic.py` → `test_arithmetic.py`, `test_services.py`,
    `test_service.py`). Untracked test files count; gitignored ones don't.
- **A changed module with no matching test file runs all tests** (`conftest.py`, `__init__.py`, or
  a module nobody named a test after). A miss in the heuristic must not let a change through.
- First measurement on the dogfood project (2026-11-20): `services/arithmetic.py` picked
  `test_service.py` (13 of 34 tests); `routers/arithmetic.py` matched nothing and ran all 34. A
  Stop with a change takes 7–8 s there.

### 1.3 Approval phrases

A prompt approves when, after trimming leading and trailing whitespace, it equals one of the
phrases, **ignoring case**. The phrase anywhere inside a longer message doesn't count
("not plan agreed", "Plan agreed, but rename X"). A prompt wrapped in `<pasted_content>` doesn't
count either: approvals have to be typed (spike S3).

## 2. `state.json`

The progress record of one task.

- **Path:** `.tasks/<folder>/state.json` in the project repo (gitignored, stays on the developer's
  machine).
- **Only `task-state.sh` writes it.** Hooks and skills read it; `harness-guard.sh` blocks the
  agent from writing it.
- `task-state.sh start-task` creates it. There is no defaults file.
- Schema: `plugins/dc-harness/schemas/state.schema.json`.

### 2.1 Task folder name

`<folder>` is the branch name with:

- `/` kept, so each part becomes a nested folder (`feature/x` → `.tasks/feature/x/`). Git doesn't
  allow both `feature` and `feature/x` as branches, so the folders can't collide that way.
- every character other than `A–Z a–z 0–9 . _ - /` replaced with `-`
  (`feature/añadir login#2` → `.tasks/feature/a-adir-login-2/`).

`state.json` keeps the real branch name in `branch`.

### 2.2 Keys

`state.json` stores only what can't be worked out from the task's files (§2.3).

| Key | Type | Set by | Meaning |
| --- | --- | --- | --- |
| `schemaVersion` | integer | `start-task` | `1`. Not checked |
| `branch` | string | `start-task` | The branch name as git reports it |
| `commitRef` | string (40-char SHA) | `start-task` | HEAD when the task started. Every diff is taken from here |
| `startedAt` | string (ISO 8601 UTC) | `start-task` | When the task started |
| `step` | `"start-task"` \| `"plan"` \| `"implement"` \| `"assessment"` \| `"pr-text"` | every skill | The last skill whose preconditions passed. Used in refusal messages, and later by `/dc:continue` and the order guard (v1) |
| `gate` | `"spec"` \| `"plan"` \| `"assessment"` \| `null` | every skill | Which gate `approval-capture.sh` listens for (§2.4) |
| `planSession` | string \| `null` | `plan` | The `session_id` that ran `/dc:plan` (§2.5) |

```json
{
  "schemaVersion": 1,
  "branch": "feature/login-rate-limit",
  "commitRef": "9f2c1e7a4b0d3e8f5a6c7b1d2e3f4a5b6c7d8e9f",
  "startedAt": "2026-11-19T10:15:00Z",
  "step": "plan",
  "gate": "plan",
  "planSession": "048e216b-0000-0000-0000-000000000000"
}
```

### 2.3 Progress comes from the files

Each skill calls `task-state.sh <skill>` at its start, so the script never sees a skill finish.
Instead of storing "done" flags, progress is read from the files that prove it:

| Step | Counts as done when |
| --- | --- |
| Spec written | `spec.md` exists |
| Spec approved | `approvals.json` has a spec approval whose hash equals the SHA-256 of `spec.md` now |
| Plan written | `plan.md` exists |
| Plan approved | The same check against `plan.md` |
| Checkpoint `CP<n>` done | `implementation-notes.md` has a `## CP<n>` entry |
| Assessment finished | `assessment.md` has the score line |
| Task finished | `pr-text.md` exists |

The fixed markers (`## CP<n>`, the score line) are defined in §6.

### 2.4 How `gate` moves

`task-state.sh` sets `step` and `gate` when a skill's preconditions pass:

| Skill starts | `gate` becomes | `approval-capture.sh` then |
| --- | --- | --- |
| `/dc:start-task` | `"spec"` | Listens for `specApprovalPhrase` |
| `/dc:plan` | `"plan"` | Listens for `planApprovalPhrase` |
| `/dc:implement` | `null` | Records nothing |
| `/dc:assessment` | `"assessment"` | Records the developer's answers word for word |
| `/dc:pr-text` | `null` | Records nothing |

The hook only reads `gate`; it writes `approvals.json`, never `state.json`. A spec edited during
the spec step is re-approved by typing the phrase again, since `gate` is still `"spec"`.

### 2.5 Fresh session

- The skills pass the current session ID to the script:
  `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" <skill> "${CLAUDE_SESSION_ID}"`. Claude Code
  replaces `${CLAUDE_SESSION_ID}` in SKILL.md text, like `${CLAUDE_PLUGIN_ROOT}`.
  Confirmed in spike S8 (CLI): the ID in the skill equals the hooks' `session_id`. It is **not**
  set as an environment variable, so it must be passed as an argument. `session-recorder.sh` (the
  `SessionStart` hook) isn't needed in v0.
- `/dc:plan` stores the ID in `planSession`.
- `/dc:implement` refuses when the current ID equals `planSession`. Per spike S1: `/clear` gives a
  new ID (fresh); `/compact` and resuming the planning session keep it (not fresh); resuming a
  different older session counts as fresh (known gap, accepted).
- Implementation sessions are not recorded.

### 2.6 Task life cycle

- **One open task per repo.** A task is open while its folder has `state.json` and no
  `pr-text.md`. `/dc:start-task` searches every `.tasks/**/state.json` and refuses while any task
  is open: "Task open on branch `<branch>`. Finish it with `/dc:pr-text` first."
- **The task is found by the current branch.** On another branch, the skills refuse: "The open
  task is on `<branch>`. Switch back to it."
- **Finished** means `pr-text.md` exists. After that, `/dc:plan`, `/dc:implement` and
  `/dc:assessment` refuse ("task finished"); `/dc:pr-text` can be re-run to regenerate the text.
- **A new task on a branch whose folder already holds a finished task** (the same branch again, or
  two branch names that map to the same folder): `/dc:start-task` refuses and asks the developer to
  delete `.tasks/<folder>/`. Nothing is overwritten.

## 3. `approvals.json`

Proof of the developer's own words at each gate.

- **Path:** `.tasks/<folder>/approvals.json`, next to `state.json`.
- **Only `approval-capture.sh` writes it** (the `UserPromptSubmit` hook). `task-state.sh` reads
  it; `harness-guard.sh` blocks the agent from writing it.
- The hook creates it on the first thing it records.
- Schema: `plugins/dc-harness/schemas/approvals.schema.json`.

### 3.1 Keys

| Key | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | `1`. Not checked |
| `spec` | object \| absent | The **latest** spec approval. A new approval replaces it |
| `plan` | object \| absent | The **latest** plan approval. A new approval replaces it |
| `assessment` | array | The developer's prompts during the current assessment run, in order, word for word |

An approval object (`spec`, `plan`):

| Key | Type | Meaning |
| --- | --- | --- |
| `phrase` | string | The phrase as typed, after trimming |
| `at` | string (ISO 8601 UTC) | When it was typed |
| `session` | string | `session_id` from the hook payload |
| `sha256` | string (64 hex chars) | SHA-256 of the file's raw bytes at that moment |

An assessment entry: `at`, `session` and `text` (the prompt, word for word).

```json
{
  "schemaVersion": 1,
  "spec": {
    "phrase": "specification agreed",
    "at": "2026-11-19T10:42:10Z",
    "session": "198e5f67-0000-0000-0000-000000000000",
    "sha256": "3b1f0000000000000000000000000000000000000000000000000000000000e9"
  },
  "plan": {
    "phrase": "Plan agreed",
    "at": "2026-11-19T11:05:33Z",
    "session": "198e5f67-0000-0000-0000-000000000000",
    "sha256": "a07c000000000000000000000000000000000000000000000000000000000041"
  },
  "assessment": [
    { "at": "2026-11-19T15:01:02Z", "session": "7d3a0000-0000-0000-0000-000000000000", "text": "Because the limiter is per IP, two users behind one NAT share it." },
    { "at": "2026-11-19T15:03:40Z", "session": "7d3a0000-0000-0000-0000-000000000000", "text": "not sure" }
  ]
}
```

### 3.2 What the hook does on each prompt

1. No `.harness/config.json`, or no task for the current branch: exit silently.
2. The prompt is `/dc:assessment` (or the short form `/assessment`, with or without arguments) and
   the task isn't finished (no `pr-text.md`): set `assessment` to `[]`. **A re-run starts
   fresh.** Then stop: the command itself is never recorded. The check on `pr-text.md` keeps a
   refused run from wiping the answers of a finished task.
3. Read `gate` from `state.json` and act on it:

| `gate` | Hook does |
| --- | --- |
| `"spec"` / `"plan"` | Ignore the prompt if it contains `<pasted_content` anywhere. Otherwise compare it with `specApprovalPhrase` / `planApprovalPhrase` (§1.3). On a match, with `spec.md` / `plan.md` present: hash the file with `sha256sum`, replace `spec` / `plan`, and return a `context` for the agent: "Spec approval recorded. Tell the developer to run `/dc:plan`. Do nothing else." (for the plan: "… to run `/clear`, then `/dc:implement`"). If the prompt contains a phrase but doesn't equal it, record nothing and return a `message`: "Not recorded as approval: type the phrase on its own." If the file is missing, record nothing |
| `"assessment"` | Skip prompts starting with `/`. Remove any `<pasted_content …>` tags, keeping the text inside (answers may be pasted, spike S3). Both tags carry the id: `<pasted_content id="5405">` … `</pasted_content id="5405">`. The text is trimmed. Append `{at, session, text}` to `assessment`. Every typed prompt counts, side remarks included: the list is a transcript of the developer's input, not a graded answer sheet |
| `null` | Nothing |

The `/dc:assessment` prompt fires the hook **before** the skill runs `task-state.sh`, so `gate`
isn't `"assessment"` yet on a first run. Step 2 handles the command either way.

The hook sets `LC_ALL=C.UTF-8` so case-insensitive matching works for phrases with accents
(for example "Especificación acordada"). Phase 1 has a bats test for this.

### 3.3 How it's used

- **`task-state.sh plan`:** `spec` exists and `spec.sha256` equals the SHA-256 of `spec.md` now.
  Refusals: "Spec not approved: type '<first specApprovalPhrase>'." or "`spec.md` changed since
  approval: review it and type the phrase again."
- **`task-state.sh implement`:** the same check against `plan.md`, plus the session rule (§2.5).
- **`/dc:assessment`:** the agent copies the developer's answers into `assessment.md` itself.
  `approvals.json` is the evidence anyone can compare it with ("trusted, not monitored").

Hashes are taken on raw bytes, both when approving and when checking. Nothing converts line
endings inside `.tasks/`, so CRLF doesn't matter.

## 4. `task-state.sh`

The gatekeeper every skill calls first. It checks the skill's preconditions in a fixed order,
refuses with one line at the first check that fails, and writes `state.json` only when every check
passes. It reads `config.json`, `state.json`, `approvals.json` and the task's files, and writes
nothing but `state.json`.

### 4.1 Command line

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" <skill> "${CLAUDE_SESSION_ID}" [<checkpoint>]
```

| Argument | Values |
| --- | --- |
| `<skill>` | `start-task`, `plan`, `implement`, `assessment`, `pr-text` |
| session ID | Always passed, so every skill calls the script the same way. Empty, or still the literal `${CLAUDE_SESSION_ID}` (substitution failed): exit 2 |
| `<checkpoint>` | `implement` only, optional. `CP2`, `cp2` and `2` are all accepted and read as `CP2` |

- The script finds the project root with `git rev-parse --show-toplevel`, so it works from any
  subfolder.
- **The `/dc:start-task` description never goes into the command.** Claude Code pastes
  `$ARGUMENTS` into the SKILL.md text as is, so a description containing `"` or `$` would break
  the command. The skill itself checks for an empty description and prints the usage before
  calling the script.

### 4.2 Exit codes and output

| Exit | Meaning | Output |
| --- | --- | --- |
| `0` | Allowed; `state.json` updated | `key=value` lines on stdout (below) |
| `1` | Refused: a precondition failed | One line on stdout. The skill prints it exactly and stops |
| `2` | Can't run: not a git repo, `jq` missing, bad arguments, empty session ID | One line on stderr, starting with `dc: internal:` and suggesting `doctor.sh` where it helps |

Success output, for the skill to use instead of working these out again:

| Skill | Prints |
| --- | --- |
| all | `task-dir=.tasks/<folder>` |
| `start-task` | `commit-ref=<sha>`, `approval-phrase=<first specApprovalPhrase>` (for the closing message) |
| `plan` | `approval-phrase=<first planApprovalPhrase>` (for the closing message) |
| `implement` | `checkpoint=CP<n>`: the first one not done |
| `assessment` | `commit-ref=<sha>`, `questions=<assessment.numQuestions>`, `pass-threshold=<assessment.passThreshold>`, `max-retries=<assessment.maxRetriesPerQuestion>` |

Every refusal ends with the next action and names commands in the full `/dc:` form.

### 4.3 Checks

Checks run top to bottom; the first failure refuses. Phrases in refusals (`<phrase>`) are the first
entry of `specApprovalPhrase` / `planApprovalPhrase`.

**Shared checks**, before each skill's own:

| # | Applies to | Check | Refusal |
| --- | --- | --- | --- |
| G1 | all | `.harness/config.json` exists | `This repo isn't onboarded for DC-Harness (no .harness/config.json).` |
| G2 | all | HEAD is not detached | `HEAD is detached. Check out a branch first.` |
| G3 | all but `start-task` | The current branch has a task | Open task on another branch: `The open task is on <branch>. Switch back to it.` No task: `No task on this branch. Start one with /dc:start-task <description>.` |
| G4 | `plan`, `implement`, `assessment` | Task not finished (no `pr-text.md`) | `Task finished (pr-text.md exists). Start a new task on a new branch.` |

**`start-task`**

| # | Check | Refusal |
| --- | --- | --- |
| S1 | No open task anywhere in `.tasks/` (§2.6) | `Task open on branch <branch>. Finish it with /dc:pr-text first.` |
| S2 | The branch matches no `protectedBranches` pattern | `Branch <branch> is protected. Create a task branch first.` |
| S3 | `.tasks/<folder>/` doesn't exist | `.tasks/<folder>/ already holds a finished task. Delete it to start a new task here.` |
| S4 | Working tree clean: `git status --porcelain` is empty, **untracked files included** | `Working tree not clean. Commit or stash your changes, and discard or gitignore untracked files.` |

S4 counts untracked files because the assessment diff includes untracked files: a stray file from
before the task would look like the agent's work.

Writes: creates `.tasks/<folder>/state.json` with `commitRef` = HEAD, `startedAt`,
`step: "start-task"`, `gate: "spec"`, `planSession: null`.

**`plan`**

| # | Check | Refusal |
| --- | --- | --- |
| P1 | `spec.md` exists | `No spec.md. Run /dc:start-task first.` |
| P2 | `approvals.json` has `spec` | `Spec not approved: type '<phrase>'.` |
| P3 | `spec.sha256` equals the SHA-256 of `spec.md` | `spec.md changed since approval: review it and type '<phrase>' again.` |

Writes: `step: "plan"`, `gate: "plan"`, `planSession` = session ID.

**`implement [<checkpoint>]`**

| # | Check | Refusal |
| --- | --- | --- |
| I1 | `plan.md` exists | `No plan.md. Run /dc:plan first.` |
| I2 | `approvals.json` has `plan` | `Plan not approved: type '<phrase>'.` |
| I3 | `plan.sha256` equals the SHA-256 of `plan.md` | `plan.md changed since approval: review it and type '<phrase>' again.` |
| I4 | Session ID ≠ `planSession` | `This session wrote the plan. Run /clear, then /dc:implement.` |
| I5 | `plan.md` has checkpoint headings numbered CP1, CP2, … in file order, with no gaps (§6.1) | No headings: `plan.md has no checkpoints (## CP<n>: <title>). Run /dc:plan again.` Wrong numbering: `plan.md checkpoints must be numbered CP1, CP2, … in order. Run /dc:plan again.` |
| I6 | At least one checkpoint is not done | `All checkpoints done. Run /dc:assessment.` |
| I7 | Checkpoint given: it is the **next** one, the first not done in plan order | `The next checkpoint is CP<m>. Run /dc:implement or /dc:implement CP<m>.` |

Checkpoints are implemented strictly in plan order: `/dc:implement` only ever runs the first
checkpoint not done. Giving it explicitly is allowed but never changes which one runs.

Writes: `step: "implement"`, `gate: null`.

**`assessment`**

| # | Check | Refusal |
| --- | --- | --- |
| A1 | `plan.md` and `implementation-notes.md` exist | `No implementation-notes.md. Run /dc:implement first.` |
| A2 | Every checkpoint in `plan.md` has its entry in the notes | `Checkpoints not done: CP<n>, …. Run /dc:implement.` |

Writes: `step: "assessment"`, `gate: "assessment"`.

**`pr-text`**: allowed on a finished task, so the text can be regenerated.

| # | Check | Refusal |
| --- | --- | --- |
| R1 | `spec.md` exists | `No spec.md. Run /dc:start-task first.` |
| R2 | `assessment.md` has the score line (§6) | `Assessment not finished. Run /dc:assessment.` |

Writes: `step: "pr-text"`, `gate: null`.

### 4.4 Re-running an earlier skill

Allowed. For example, `/dc:plan` after `/dc:implement` has started: `step` goes back to `plan`, the
`plan` gate reopens, the new `plan.md` needs a new approval (its hash changes) and `/clear` is
needed again. Notes for checkpoints already done stay as they are. `/dc:start-task` is the
exception: S1 refuses it while the task is open.

### 4.5 Not in v0

- **Rebase check.** DC-Harness.md says not to merge or rebase during a task. A check such as
  `git merge-base --is-ancestor <commitRef> HEAD` in `assessment` would catch a rebase that lost
  the commit-ref. Left out of v0; the rule stays an instruction.

## 5. Hooks

### 5.1 The v0 hooks

| Script | Event | Job |
| --- | --- | --- |
| `approval-capture.sh` | `UserPromptSubmit` | Records approvals and assessment answers in `approvals.json` (§3.2) |
| `harness-guard.sh` | `PreToolUse` | Protects the harness files; keeps the spec and plan steps read-only (§5.4) |
| `stop-check.sh` | `Stop` | Runs the `affected` checks when the agent changed files during `/dc:implement` (§5.5) |

`session-recorder.sh` (`SessionStart`) is **not in v0** while the `${CLAUDE_SESSION_ID}` check of
§2.5 holds. If that check fails, it comes back as the fallback and gets its contract then.

All scripts live in `plugins/dc-harness/scripts/hooks/`.

### 5.2 Input

Claude Code sends one JSON object on stdin. The fields used (confirmed in the spike payloads,
except `tool_input.file_path`, which comes from the documentation and gets a recorded fixture in
Phase 1):

| Field | Events | Use |
| --- | --- | --- |
| `session_id` | all | Approvals and assessment answers |
| `cwd` | all | Starting point for `git rev-parse --show-toplevel` |
| `hook_event_name` | all | Sanity check |
| `prompt` | `UserPromptSubmit` | The developer's text, word for word (S3) |
| `tool_name` | `PreToolUse` | `Edit`, `Write`, `MultiEdit`, `NotebookEdit`, `Bash`, `PowerShell` |
| `tool_input.file_path` | `PreToolUse` (file tools) | The file the tool will write |
| `tool_input.command` | `PreToolUse` (`Bash`, `PowerShell`) | The command line |
| `stop_hook_active` | `Stop` | Not used in v0 (no loop limit, §5.5) |

If the repo isn't onboarded, or the current branch has no task, every hook **exits 0 with no
output**: it does nothing.

### 5.3 Output: the neutral format

Every hook builds the same object and hands it to `emit` (in `lib/msg.sh`). The scripts never print
agent-specific JSON themselves, so supporting another agent (Codex, Cursor…) later means its own
event wiring and a new branch in `emit`, not changes to the hook logic.

| Field | For | Meaning |
| --- | --- | --- |
| `decision` | — | `"allow"` (default) or `"block"` |
| `reason` | the agent | Why it's blocked, and what to do instead |
| `message` | the developer | Shown in the UI |
| `context` | the agent | Text added to the agent's context without blocking |

`emit` for Claude Code:

| Event | `block` + `reason` → | `context` → | `message` → |
| --- | --- | --- | --- |
| `UserPromptSubmit` | not used: prompts are never blocked | `hookSpecificOutput.additionalContext` | `systemMessage` |
| `PreToolUse` | `hookSpecificOutput.permissionDecision: "deny"` + `permissionDecisionReason` | — | `systemMessage` |
| `Stop` | `decision: "block"` + `reason` | — | `systemMessage` |

- Hooks always exit 0 and say everything through the JSON. Exit code 2 isn't used.
- **Fail open.** If a hook script itself fails (jq missing, a bug), it allows the action and
  returns a `message`: "DC-Harness hook failed: run doctor.sh." A bug of ours must not lock the
  developer out of their session.

### 5.4 `harness-guard.sh`

Matcher: `Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell`. PowerShell is included because the
agent runs most commands through it on Windows (S2).

**Protected files** (at every step):

- `.tasks/**/state.json`, `.tasks/**/approvals.json`, `.tasks/**/stop-check.json`
- anything under `.harness/`

**Read-only steps.** While `step` is `start-task` or `plan`, only `.tasks/<folder>/` is writable,
so `spec.md` and `plan.md` can be written but the code can't.

| Tool | Blocked when | `reason` |
| --- | --- | --- |
| File tools | `file_path` is a protected file | "DC-Harness files are written only by the harness." |
| File tools | `step` is `start-task` or `plan` and `file_path` is outside `.tasks/<folder>/` | "`/dc:<step>` is read-only: write only spec.md or plan.md." |
| Shell tools | The command mentions a protected file and isn't read-only | "DC-Harness files are written only by the harness." |
| Shell tools | `step` is `start-task` or `plan` and the command isn't read-only | "`/dc:<step>` is read-only: only reading commands are allowed." |

`file_path` (`notebook_path` for `NotebookEdit`) is normalised before comparing: backslashes become
`/`, relative paths are resolved from the project root, `.` and `..` are resolved, Windows 8.3
short names are expanded, and the whole comparison ignores case (Windows paths are
case-insensitive, so `.HARNESS/` is still protected). A path **outside the repo** is allowed at
every step: it is the agent's own scratch or memory, not the project's code.

**Read-only command** (an allow-list, so anything unknown is blocked):

1. Calls to `${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh` are always allowed (the skills run it
   while the step is still the previous one). Only a single call to this plugin's own copy: a
   chained command or another `task-state.sh` goes through the checks below.
2. No command or process substitution (`$(…)`, backticks, `<(…)`, `>(…)`): they run other
   commands inside a reader.
3. Split the command at `;`, `&&`, `||`, `|`, `&` and newlines.
4. No output redirection, except to `/dev/null` or `$null` and `2>&1`.
5. Every piece starts with a known reader:
   - `cat`, `head`, `tail`, `less`, `grep`, `rg`, `find`, `ls`, `wc`, `diff`, `jq`, `echo`, `pwd`
   - `git status`, `git diff`, `git log`, `git show`, `git ls-files`, `git rev-parse`,
     `git branch`
   - PowerShell: `Get-Content`, `type`, `Select-String`, `Get-ChildItem`, `dir`, `Test-Path`,
     `Get-Item`, `Get-Location`
6. Readers that can write are refused with those options: `find` with `-exec`, `-execdir`, `-ok`,
   `-okdir`, `-delete` or `-fprint*`/`-fls`; `git branch` with a branch name or a flag that
   changes a branch (`-d`, `-D`, `-m`, `-c`, `-f`, `-u`, …); any `--output` (`git diff --output=`).

The list grows during dogfooding when a harmless reader gets blocked. Quotes aren't parsed, so a
`;`, `|` or `>` inside a quoted argument (`grep "a|b"`) splits or blocks the command: safe, but a
false refusal to fix if it shows up in dogfooding.

Not in v0: blocking `git commit` / `git push` while a task is open (v1 bash guard). Until then it is
an `AGENTS.md` rule.

### 5.5 `stop-check.sh`

Runs only while `step` is `implement`. Turns in the spec, plan and assessment steps are never
checked.

**"The agent changed files in this turn"** is detected with a fingerprint of the working tree:

1. Hash the working tree as git sees it: copy `.git/index` to a temporary file, `git add -A` into
   it (`GIT_INDEX_FILE`), then `git write-tree`. Gitignored files, `.tasks/` included, are left
   out automatically.
2. The hash equals `lastPassedTree` in `stop-check.json`: nothing changed, allow the stop.
3. Otherwise run `stack-check.sh affected` with the changed files:
   `git diff --name-only <lastPassedTree> <new tree>`. The call is
   `bash "<plugin>/scripts/stack-check.sh" affected <file>...`, from the repo root, with paths
   relative to it (new, modified and deleted files). Exit 0 is a pass; anything else is a
   failure, and its stdout and stderr are the output. If `stack-check.sh` is missing, the hook
   fails open (§5.3).
4. Pass: store the new hash as `lastPassedTree`, allow the stop. Fail: `block`, with `reason` =
   "Checks failed. Fix them before finishing:" plus the last ~40 lines of the output.

Before the first check, `lastPassedTree` is the commit-ref's tree (`<commitRef>^{tree}`).

**Every test must pass, with no loop limit.** A failing check is treated as caused by the task,
and the agent fixes it, however many turns it takes. If the agent can't fix it (a service that's
down, a missing tool), the developer presses **Esc** to interrupt; the README says so.

The full test suite is not this hook's job: `/dc:implement` runs `stack-check.sh full` before
writing each checkpoint's notes entry.

**`.tasks/<folder>/stop-check.json`**: written only by `stop-check.sh`, protected by the guard.
Schema: `plugins/dc-harness/schemas/stop-check.schema.json`.

```json
{ "schemaVersion": 1, "lastPassedTree": "4b825dc642cb6eb9a060e54bf8d69288fbee4904" }
```

### 5.6 `hooks.json`

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/approval-capture.sh\"" }] }
    ],
    "PreToolUse": [
      { "matcher": "Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell",
        "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/harness-guard.sh\"" }] }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/hooks/stop-check.sh\"", "timeout": 600 }] }
    ]
  }
}
```

- `${CLAUDE_PLUGIN_ROOT}` is always quoted (S4).
- The Stop hook's 10-minute timeout is a first guess; the dogfood timings set it.

## 6. Fixed markers in the artefacts

The agent writes the Markdown artefacts; scripts read only the three markers below and nothing
else in them. Everything else is decided by a file existing (`spec.md`, `plan.md`, `pr-text.md`) or
by a hash (§3). The templates in `plugins/dc-harness/templates/` carry these markers, so the agent
copies them rather than inventing them. Markers are fixed English, whatever language the rest of
the artefact is written in. Lines are matched after stripping `\r`.

### 6.1 Checkpoint headings in `plan.md`

```markdown
## CP1: Rate limiter middleware
### Tasks
- …
### Acceptance criteria
- …

## CP2: Configurable limits per route
…
```

- **Form:** a level-2 heading, `^## CP([0-9]+): (.+)$`. `CP` is uppercase.
- Inside a checkpoint the template uses only level-3 headings, so no other line starts with
  `## CP`.
- **The plan is written in implementation order.** Headings are numbered CP1, CP2, … in file
  order with no gaps; `task-state.sh` refuses any other numbering (check I5), so a checkpoint's
  number and its position always agree.
- **Read by:** `task-state.sh` (I5, I6, I7, A2).

### 6.2 Checkpoint entries in `implementation-notes.md`

```markdown
## CP1: Rate limiter middleware
### Changes
- …
### Decisions
- …
```

- **Form:** the same heading as in the plan. A checkpoint counts as **done** when a line matches
  `^## CP<n>(:|$)`, so only the ID has to match.
- **Written last:** `/dc:implement` writes the entry only after `stack-check.sh full` passes. An
  entry written early would mark the checkpoint done before the work is.
- **Read by:** `task-state.sh` (I6, I7, A2).

### 6.3 Score line in `assessment.md`

```markdown
Score: 3/4 (passed)
```

- **Form:** one line, `^Score: ([0-9]+)/([0-9]+) \((passed|not passed)\)$`, anywhere in the file,
  written when the assessment ends.
- The total is `assessment.numQuestions`. The agent decides `passed` / `not passed` from
  `assessment.passThreshold`; the script doesn't recompute it.
- **Read by:** `task-state.sh` (R2, "assessment finished"). `/dc:pr-text` copies it into the PR
  text.

### 6.4 Expected answers

The expected answers are written before the first question, but kept out of sight while the
developer answers:

1. Before asking, the agent writes them to a hidden file in the task folder:
   `.tasks/<folder>/.assessment-key.md`.
2. During the assessment, `assessment.md` holds only the questions and the developer's answers.
3. At the end, the agent copies each expected answer into `assessment.md` under its question,
   writes the score line, and deletes `.assessment-key.md`.
4. A re-run of `/dc:assessment` overwrites the key with new answers (and starts fresh, §3.2).

This is a skill instruction and a template, not a check: the developer could still open the file
("trusted, not monitored").
