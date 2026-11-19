# DC-Harness: roadmap

DC-Harness is a plugin for coding agents that makes agent-assisted development consistent across teams while the developer keeps the knowledge of what was built. Its philosophy is "controlled but appealing". The control comes from a few human gates that need the developer's own words: the interview answers, the approval of the specifications, the approval of the plan, and a short assessment on the final diff. Everything else stays light. Developers are trusted, not monitored: artefacts stay on their machine and the only thing shared is a short PR text pasted into the pull request. The scope is one task per branch, from the task description to the PR text. Git stays in the developer's hands, there is no CI gate, and general engineering advice (TDD, review, security) is reused from existing skill libraries instead of rewritten.

## How DC-Harness works

This section defines every term used in the rest of the document. Features are marked with the
version they belong to: **v0** is the first usable harness, built in Phases 0–2 and used in the
pilot; **v1** is everything added in Phase 3, once dogfooding or the pilot shows it's needed.

### Workflow

A **task** is one piece of work on one git branch. Its files live in `.tasks/<branch-name>/` in
the project repo; that folder is gitignored, so it stays on the developer's machine.

```text
  /dc:start-task <description> → "specification agreed" → /dc:plan → "Plan agreed" → /clear + /dc:implement [<checkpoint>] → /dc:assessment → /dc:pr-text → paste in PR
```

### Skills

Every command is written in full, with the plugin's `dc:` namespace (see "Command names and
paths" in the v0 development process).

| Skill | When | What it does | Writes |
| --- | --- | --- | --- |
| `/dc:start-task <description>` | v0 | Checks the working tree is clean, HEAD is not detached, no task is already open and the branch is not in `protectedBranches`; with no description, stops and explains the command. Records the current commit hash (commit-ref), which later diffs are taken against. Asks clarifying questions one at a time until the description is concrete, writes the spec for the developer to review, then says "type 'specification agreed', then run `/dc:plan`" and stops | `spec.md`, `state.json` (commit-ref) |
| `/dc:plan` | v0 | Needs `spec.md` approved with "specification agreed" and unchanged since. Read-only on the code: maps dependencies, slices the work vertically, writes and orders tasks, and groups them into checkpoints (each with an ID, its tasks and acceptance criteria). Then says "type 'Plan agreed', run `/clear`, then `/dc:implement`" and stops | `plan.md` |
| `/dc:implement [<checkpoint>]` | v0 | Needs `plan.md` approved with "Plan agreed" and unchanged since, in a session other than the one that ran `/dc:plan`. Implements, tests and verifies one checkpoint, always the first one not yet done (the plan is written in implementation order), running the `full` stack check before writing the notes entry, then stops for the developer to check. Every test must pass: a failing test is treated as caused by the task, and the agent fixes it. It refuses any checkpoint other than that one. Stops and asks before deviating from the plan. Never commits | code, tests, `implementation-notes.md` (one entry per checkpoint: changes and small technical decisions) |
| `/dc:assessment` | v0 | Needs every checkpoint of the plan in `implementation-notes.md`. Takes the diff from commit-ref plus untracked files, and the notes. Writes the expected answers first, then asks `assessment.numQuestions` questions one at a time. A wrong answer gets a rephrase, a hint and a related question; "not sure" gets an explanation and a related question; retries per question are limited by `assessment.maxRetriesPerQuestion`. Ends with a passed/total score, compared with `assessment.passThreshold` | `assessment.md` (questions, the developer's answers word for word, score passed/total, passed or not passed) |
| `/dc:pr-text` | v0 | Needs `spec.md` and a finished assessment. Reads `spec.md`, `plan.md`, `implementation-notes.md` and `assessment.md` and summarises what was built (spec), how and the key decisions (plan and notes), deviations from the plan (notes), gate status, and what the developer understood (assessment score, with the questions and the developer's answers). At most `prTextMaxChars` characters (default 3,000, because Azure DevOps PR descriptions are limited to 4,000). The developer pastes it into the PR by hand | `pr-text.md` |
| `/dc:continue` | v1 | Runs the next step of the workflow and stops at every gate | — |
| `/dc:check` | v1 | Compares the plan with the real diff: planned but missing, built but not planned, missing tests | `check.md` |
| `/dc:blind-spot` | v1 | Maps an unfamiliar area of the code before planning (entry points, patterns, traps with `file:line`) | `blind-spots.md` |

### Gates

The gates are the only places that need the developer's input, either in the form of a command or in its own words.

- **Spec approval.** `/dc:plan` needs the spec approved: the developer types one of the project's
  `specApprovalPhrase` values (for example "specification agreed"). A hook catches the phrase,
  computes a SHA-256 hash of `spec.md` and stores both. If the spec changes afterwards, the hash
  no longer matches and it must be approved again.
- **Plan approval.** The plan is approved only when the developer types one of the project's
  `planApprovalPhrase` values (for example "Plan agreed"). A hook catches the phrase, computes a
  SHA-256 hash of `plan.md` and stores both. "Looks good" is feedback, not approval. If the plan
  changes afterwards, the hash no longer matches and it must be approved again.
- **Fresh session.** Protects the plan approval: the plan is only trusted if a new session can
  work from the files alone. `/dc:implement` refuses to run in the session that wrote the plan, so
  the developer runs `/clear` (which starts a new session) first. If the new session can't build
  from the files alone, the plan was incomplete.
- **Assessment.** `assessment.numQuestions` questions about the diff (default 4), asked one at a
  time; the expected answers are written before the first question is asked. A wrong or unsure
  answer gets an explanation and a related question, up to `assessment.maxRetriesPerQuestion`
  retries per question. The developer's answers are recorded word for word. It ends with a
  passed/total score, which is "passed" when it reaches `assessment.passThreshold` (a share of
  the questions, set by the tech lead). `/dc:pr-text` refuses until every question has been asked
  and the score written.

All diffs are taken from the **commit-ref**: the commit HEAD pointed to when `/dc:start-task` ran.
Don't merge or rebase during a task: other people's changes would end up in the diff.

### State and enforcement

- **`state.json`**: the commit-ref, the last skill run, which gate is open, and the session ID of
  `/dc:plan`. Which steps are done is read from the task's files (spec, plan, notes, assessment,
  PR text), not stored. Only **`task-state.sh`** writes it: every
  skill starts by running `task-state.sh <skill>`, which checks the skill's preconditions and
  refuses with a one-line instruction if something is missing.
- **`approvals.json`**: for the spec and the plan, the approval phrase as typed, its time, the
  session and the file's hash;
  the assessment answers as typed. Only hooks write it.
- **Hooks** are scripts the agent runs on events. Each reads JSON and answers with
  `{decision, reason, message, context}`. A small adapter file (`hooks.json` for Claude Code)
  connects events to scripts.

| Hook | When | Does |
| --- | --- | --- |
| Session recorder (`SessionStart`) | fallback | Records the session ID, for the fresh-session rule. Only needed if skills can't read the session ID directly (`${CLAUDE_SESSION_ID}`) |
| Approval capture (`UserPromptSubmit`) | v0 | While a gate is open, records the approval phrase with the hash of `spec.md` or `plan.md`, or an assessment answer word for word |
| Harness guard (`PreToolUse`) | v0 | Blocks the agent from writing the harness's own files (`state.json`, `approvals.json`, `stop-check.json`, `.harness/`). While writing the spec or the plan, also blocks any change outside the task folder: those steps are read-only |
| Stop check (`Stop`) | v0 | During `/dc:implement`, only when the agent changed files in that turn: doesn't let it finish the turn until lint, type checks and the affected tests pass. Turns that change no files are not checked |
| Order guard | v1 | Blocks skills run out of order (until then, each skill's precondition check does this) |
| Protect files, bash guard | v1 | Block edits to `.env*`, lockfiles and `.git/`; block `rm -rf` outside the repo, `git reset --hard`, force pushes |
| Format on edit, version check | v1 | Run the formatter on each edited file; warn when the plugin or the project's rules are outdated |

### Project setup

A repo is **onboarded** when it has a committed `.harness/` folder. Everywhere else the harness
does nothing. Only the tech lead changes `.harness/`; the agent can't.

- **`.harness/config.json`** keys: `stack` (the list of stack layers that apply),
  `stackCommands` (per stack, override the lint, types and tests commands), `protectedBranches`,
  `specApprovalPhrase` and `planApprovalPhrase` (each a list), `assessment.numQuestions`,
  `assessment.passThreshold`, `assessment.maxRetriesPerQuestion`, `prTextMaxChars`. v1:
  `language`. The config isn't validated: setting it correctly is the tech lead's job. Full
  contract in `docs/contracts.md`.
- **`.harness/AGENTS.md`**: about ten "how to work" rules for the agent, imported by the
  project's own `AGENTS.md` or `CLAUDE.md`.
- **Stack layer**: per language, a `stack-check.sh` that runs the checks in two sizes, plus
  default commands: `affected` (lint, types and only the tests touched by the change, run by the
  Stop hook after every agent turn) and `full` (lint, types and the whole test suite, run by
  `/dc:implement` at the end of each checkpoint). v0 has only Python (ruff, mypy or pyright, pytest).

### Spikes

A spike is a short experiment that answers one question the design depends on. Each has a
fallback in case the answer is no.

| # | Question | Why it matters | Fallback |
| --- | --- | --- | --- |
| S1 | Does `/clear` start a new session ID that the `SessionStart` hook sees? | The fresh-session rule | `/dc:plan` writes a random token; a session started by `/clear` invalidates it, so `/dc:implement` knows a `/clear` happened |
| S2 | Can a `PreToolUse` hook see when a skill is loaded? | The order guard | Skill precondition checks only |
| S3 | Does the `UserPromptSubmit` hook receive exactly what the developer typed? | Spec and plan approval, and assessment answers | Approvals: none for now; Claude Code is expected to pass, and other agents (Codex, OpenCode) are decided when their adapters are built. Assessment answers: a paraphrase of the developer's response is used. The developer can edit the PR text in the PR anyway, outside the agent's control |
| S4 | Do plugin hooks run in Git Bash when paths contain spaces? | Every hook on Windows | Quoting in the adapter and a documented install path |
| S5 | Can the plugin be installed and updated from Azure DevOps without a password prompt? | Distribution | Manual update plus an "outdated" warning |
| S6 | Does `jq` on Windows handle Windows line endings and non-English characters? | All JSON reading | Strip the extra line-ending character in the JSON helper |

### Glossary

- **Dogfooding**: using the harness on real work by its author before anyone else. Here it's
  the author's own Python project, MotoGP_Insights
  (<https://github.com/migarbo1/MotoGP_Insights>), used through a separate copy that can't push
  to the original. Timings and friction go in `dogfood-log.md`.
- **Revision cycle** (v1): after PR review, reopening a finished task for the requested
  changes, with an amended plan, a new approval, and a short assessment on the new diff only.
- **Managed settings** (v1, CTO decision): company-wide Claude Code settings that force the
  plugin on and keep it updated. Stronger, but intrusive and needs admin rights.

## Comparison

> NOTE: The summaries below come from each repo's README

**[addyosmani/agent-skills](https://github.com/addyosmani/agent-skills)** is a large, popular
(about 119k stars) MIT library of 25 engineering skills grouped by phase: define (`interview-me`,
spec), plan, build (incremental implementation, TDD, context engineering), verify, review (code
quality, simplification, security, performance) and ship. It adds 9 slash commands (`/spec`,
`/plan`, `/build`, `/test`, `/review`, `/ship`, ...), 4 reviewer personas and 7 checklists. One
shared `skills/` folder is wrapped by thin adapters for Claude Code, Codex, Gemini CLI, OpenCode,
Copilot and others, with a setup guide per agent. It mostly guides the agent with instructions; it
ships Claude Code hooks, but the README doesn't say what they block. It doesn't record approvals
or check what the developer understood.

**[alfredoperez/sdd](https://github.com/alfredoperez/sdd)** is a small (2 stars) MIT Claude Code
plugin for spec-driven development: specify → plan → tasks → implement, with `/sdd:auto`,
`/sdd:resume`, `/sdd:pause` and `/sdd:status`. A complexity check sends small changes down a
short path. Progress is kept in a per-spec `.spec-context.json`, so a dropped session can resume.
Implementation has three review checkpoints (code review, test results, commit and PR), and
`.sdd.json` configures hooks at 10 points, which can be blocking. It is the closest to our
workflow, and the model for `/dc:continue`.

**[alo-exp/silver-bullet](https://github.com/alo-exp/silver-bullet)** is a large "agentic process
orchestrator" (v0.53, 7 stars, BUSL 1.1 licence) for Claude Code, Codex and Cursor. It ships 85
skills and routes each task to a workflow (feature, bugfix, devops, release, ...). Twelve layers
of hooks block source edits until planning is done, and block PRs, pushes and releases until
review, security, tests and green CI are proven. It manages git, PRs and releases, which we
decided not to do, and its licence restricts some uses. The README doesn't mention a check on
what the developer understood, or Windows.

**[ericrisco/rsc-harness](https://github.com/ericrisco/rsc-harness)** is an MIT "meta-harness"
(631 stars) installed with `npx @ericrisco/rsc onboard`. It reads the project, asks about its goal,
shows a plan (accepted by a SHA-256 plan ID) and then installs a project-local harness: a chosen
part of a 273-skill catalog, working rules, a project wiki and tool connections, for 19 assistants.
Every turn goes down one of three lanes: read-only answer, Fast-Track Development (one feature
document with a checklist checked off against proof) or a ten-phase spec-driven chain (constitution
→ specify → clarify → plan → tasks → analyze → implement → verify → review → ship), with review
depth scaled by a risk policy. Session memory resumes a task in a new session. Hooks enforce rules
only in Claude Code (lane choice, no commits on a closed `main`, confirmation before destructive
commands); in other assistants the rules are instructions only. The README says Windows has had
less testing than macOS and Linux. No comprehension check or PR text.

**[github/spec-kit](https://github.com/github/spec-kit)** is GitHub's MIT toolkit for
spec-driven development (about 150k stars), installed with a Python CLI (`uv tool install
specify-cli`, then `specify init`). A project writes a constitution once, then each feature goes
through `/speckit-specify`, `/speckit-plan`, `/speckit-tasks`, `/speckit-implement` and
`/speckit-converge`, which repeats until the code matches the spec. Extensions add bug-fixing and
idea-assessment flows, quality gates and hooks; presets let a company impose its own templates and
standards. Artefacts live in `.specify/`. Control is by instruction: the developer is asked to
review each step before the next, but nothing records or enforces it. Works on Windows and with
many agents. No comprehension check or PR text.

**[rodbv/socratic-skills](https://github.com/rodbv/socratic-skills)** is not a harness but two
small MIT skills (22 stars) about learning while working with an agent, installed with
`npx skills add`. `quiz-me` checks that you understand a code diff (staged and unstaged changes, or
the last commit), a spec or a plan before you commit or build on it. It asks one numbered question
at a time ("why does this work", "what breaks if this line goes"), probes a wrong or partial answer
before correcting it, and ends with a score such as 4/5. `guide-me` is a tutor that never writes
the code: it splits a spec or plan into steps, lets the developer implement each one, reads the
diff, asks about their choices and gives hints instead of answers, with TDD, test-after, mixed or
no-test modes. There are no hooks, no state and no files written: nothing records the score or
stops a commit, and it expects specs and plans in the folders used by Superpowers, another skill
library (`docs/superpowers/`).

### Support for each DC-Harness step

✅ full support · ◐ partial support · ❌ no support

The step columns say whether the repo has something that does the same job as our skill. **Context
reset** means the work lives in files, so the developer can `/clear` the conversation (or start a new
session) and the next step continues from the files alone. **Enforced dev input** means the
developer's own answer or approval is required, recorded, and checked before the next step can run.

| Repo | `/dc:start-task` (clarify + spec) | `/dc:plan` (tasks + checkpoints) | `/dc:implement` (one checkpoint, then stop) | `/dc:assessment` | `/dc:pr-text` | Context reset | Enforced dev input |
| --- | --- | --- | --- | --- | --- | --- | --- |
| agent-skills | ✅ | ✅ | ◐ | ❌ | ◐ | ◐ | ◐ |
| sdd | ◐ | ✅ | ◐ | ❌ | ◐ | ✅ | ◐ |
| silver-bullet | ◐ | ✅ | ◐ | ❌ | ◐ | ◐ | ❌ |
| rsc-harness | ✅ | ✅ | ◐ | ❌ | ❌ | ✅ | ◐ |
| spec-kit | ✅ | ✅ | ◐ | ❌ | ❌ | ✅ | ❌ |
| socratic-skills | ❌ | ❌ | ❌ | ◐ | ❌ | ❌ | ❌ |
| **DC-Harness** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

Specifying and planning are well covered, so we reuse them. Implementation is covered only in
part: every repo runs the whole implementation, or commits as it goes, instead of stopping after
each checkpoint for the developer. Nobody covers the assessment as a required step, and nobody
records the developer's own words before letting the work continue. Those two columns are the
reason DC-Harness exists.

### Why not use each repo directly

**agent-skills.** *Their approach:* a library of independent skills that tell the agent how a
senior engineer works. The developer is asked to approve the spec and the plan, and the skill tells
the agent to "stop your turn", but nothing records the approval or stops the next skill running
without it. `incremental-implementation` commits after every slice, and `/build auto` runs the
whole plan after one approval. *Ours:* approvals are typed phrases recorded by a hook with a hash of
the file, `/dc:implement` does one checkpoint and never commits, and the assessment is required.
*What we take:* `interview-me` and `spec-driven-development` (Phase 1) for `/dc:start-task`,
`planning-and-task-breakdown` for `/dc:plan`, `incremental-implementation` for `/dc:implement`, and the
"Change Summaries" format for `/dc:pr-text`.

**sdd.** *Their approach:* the closest flow to ours (specify → plan → tasks → implement, state in a
JSON file, resume in a new session). But `specify` writes the spec without clarifying questions,
`implement` runs all the tasks before its review checkpoints, then commits, pushes and opens the
GitHub PR itself, and its approvals are menu choices (continue / fix) that aren't recorded. It is
Claude Code only and calls a Python script. *Ours:* clarification is part of `/dc:start-task`, the
developer handles git, the PR text is pasted into Azure DevOps by hand, and approvals are recorded.
*What we take:* `specify` steps 1–3 and 5 for `/dc:start-task` (step 4, the minimal/normal
classification, is left out), the state-file-and-resume idea, and the PR
body (What, Why, Testing) from `implement` steps 7–8 for `/dc:pr-text`.

**silver-bullet.** *Their approach:* strong enforcement, but of the *agent*: hooks block code
edits until planning skills have run, and block PRs, pushes and releases until review, tests and
green CI are proven. It manages git, PRs and releases. *Ours:* we enforce the *developer's*
involvement (their approval, their answers) and leave git to them. Its 85 skills are far more than
we need, its README says nothing about Windows, and its BUSL licence limits reuse. *What we take:*
the idea only, that hooks can block the agent until a step's output exists; no code.

**rsc-harness.** *Their approach:* a tool that builds a whole harness for a project (skills from a
273-skill catalog, wiki, tool connections, 19 assistants) and decides how each turn is run: a quick
lane or a ten-phase spec chain, with review depth set by risk. Session memory lets a new session
continue. Hooks enforce rules only in Claude Code, and nothing checks the developer's understanding
or writes a PR text. *Ours:* one fixed five-step workflow, centred on the developer's approval and
understanding. Adopting it would mean following its process, not ours. *What we take:* the session
memory idea (for a future `/dc:continue`), the risk-scaled review, and the queue of decisions the
developer must make for risky areas (auth, billing, migrations).

**spec-kit.** *Their approach:* a well-made, widely used spec → plan → tasks → implement flow, with
a "converge" loop that keeps comparing the code with the spec. The developer is asked to review each
step, but nothing records or enforces it; extensions can add hooks, but they don't block. It needs
Python and uv, and keeps its own artefact layout in `.specify/`. *Ours:* the same kind of flow, but
with recorded approvals, one checkpoint at a time and a required assessment. Building that as a
spec-kit extension would still mean writing the same hooks and assessment, plus its dependencies.
*What we take:* its spec and plan templates, and the "converge" idea for a future `/dc:check`.

**socratic-skills.** *Their approach:* two voluntary learning exercises. `quiz-me` asks 5–7
questions on a diff, spec or plan, one at a time, asks a follow-up before correcting, and ends with
a score; nothing is written, nothing is recorded, and nothing stops the developer moving on.
`guide-me` has the developer write the code while the agent only coaches. *Ours:* the agent writes
the code, and the assessment is a required step: expected answers written before asking, a
retry limit set by the tech lead, the developer's answers recorded word for word by a hook, the diff
taken from the commit where the task started plus untracked files, and `assessment.md` as the
record. *What we take:* `quiz-me` as the base of `/dc:assessment`, including its question types and
its "follow-up before correcting" rule.
