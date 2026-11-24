---
name: plan
description: Plans an approved DC-Harness spec. Read-only on the code - maps dependencies, slices the work vertically, and writes plan.md as ordered checkpoints (tasks and acceptance criteria) for approval. Run as /dc:plan after typing the spec approval phrase.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" plan *), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" plan *), Read(${CLAUDE_PLUGIN_ROOT}/templates/**)
---
<!-- Draws on: agent-skills planning-and-task-breakdown; spec-kit plan template. See THIRD_PARTY_NOTICES.md. -->

# /dc:plan

This skill only produces `plan.md`. It never writes code or tests, never edits `spec.md`, never
commits, and never edits any file other than `plan.md` in the task folder. The harness blocks
code edits and non-reading shell commands during this step anyway.

The plan has one reader that matters most: a **new session** that runs `/dc:implement` after
`/clear`, with no memory of this conversation. It gets `spec.md`, `plan.md` and the code, nothing
else. Anything it needs to build CP1 must be written in the plan.

## STEP 0: Preconditions

Before reading or searching anything, run exactly this command, on its own:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" plan "${CLAUDE_SESSION_ID}"
```

Append nothing to it (no `; echo $?`, no `$LASTEXITCODE`, no pipe): the harness allows it only
on its own. Tell the result from the output:

- Exit `1`: print its one line exactly, and stop.
- Exit `2`: print its `dc: internal:` line exactly, and stop.
- Exit `0`: it prints `task-dir=…` and `approval-phrase=…`. Keep both values: the steps below
  call them `<task-dir>` and `<approval-phrase>`. Don't work them out again yourself.

## STEP 1: Read the spec

1. Read `<task-dir>/spec.md` in full. It is approved: it is the contract for this plan.
2. Read the plan template now, with the Read tool: `${CLAUDE_PLUGIN_ROOT}/templates/plan.md`. You'll fill it in step 6.
3. **Re-planning.** If `<task-dir>/plan.md` already exists, read it: this is a re-run, and the developer wants the plan revised. If `<task-dir>/implementation-notes.md` exists too, every `## CP<n>` entry in it is a checkpoint already built. The new plan keeps those checkpoints first, with the same numbers and titles, and changes only the checkpoints after them. Say so in your summary.
4. Read the project's own `AGENTS.md` / `CLAUDE.md`, `.harness/AGENTS.md` and `.harness/config.json` (the `stack` and `stackCommands` keys) if you haven't.

## STEP 2: Explore the code

Plan against the code as it is right now. Do the following in read-only mode:

- Search with the Glob and Grep tools in parallel for the modules, routes and names in the spec's Context and Requirements. Read the files the work will touch and one or two neighbours that show the patterns to follow (structure, naming, error handling, how tests are written).
- Find where the tests live, how they are named, and the fixtures or helpers to reuse.
- Note the stack's check commands: `stackCommands` in `.harness/config.json`, or the stack defaults when it doesn't override them.
- Note risks and unknowns as you go: code that is hard to change, missing tests, behaviour the spec doesn't pin down.
- Use the Read, Grep and Glob tools. Shell commands are limited to readers (`git log`, `git show`, `ls`, `cat`…); anything else is blocked by the harness. Don't run the tests or the app.
- Don't spawn subagents.

## STEP 3: Indentify blockers

A gap in the definition can be a blocker since it may tranlate into two different checkpoints. If one gap can be easyly covered, choose the lower-risk option, write it under **Decisions**, and the developer will see it when reviewing.

Ask the developer only when two reasonable answers would give **different checkpoints**, and the spec and the code don't settle it. Then ask one question per turn, with your guess:

```text
Q<n>: <one focused question>
GUESS: <your best answer, and why>
```

End your turn and wait. Record each answer under **Decisions** as "(developer, during planning)". Keep it to two or three questions at most: the spec step already did the interview.

**Never edit `spec.md`.** It is approved by its hash, and the harness can't take a new spec approval during this step. If the spec is wrong or contradicts itself in a way that changes what gets built, stop and say so in a few lines, naming the requirement. Don't write a plan around it.

## STEP 4: Map the dependencies

List the pieces of work (data and models, logic, interfaces, wiring, tests) and what each one needs before it can be built. Sketch the result as the **Dependency graph**: foundations first. Implementation follows the graph from the foundations up.

## STEP 5: Slice, write the tasks, group into checkpoints

1. **Slice vertically.** Prefer one complete path through the layers per slice (for example "R1 works end to end for the main case") over one layer at a time ("all the models, then all the endpoints"). Each slice is something that can be tested on its own.
2. **Write the tasks.** Each task has a short title, a size, one or two sentences on what it does, the files it likely touches (real paths found in step 2, tests included), its dependencies, and one testable "done when" condition. Number tasks T1, T2, … across the whole plan.
   - Sizes: XS (1 file), S (1–2 files), M (3–5 files), L (5–8 files). An XL task (8+ files) is too big: split it. So is a task with "and" in its title, or one whose "done when" needs more than three conditions.
   - Tests are part of the task that builds the behaviour, not a separate task at the end.
3. **Order them.** Dependencies first; high-risk work early, so a wrong assumption shows up before much is built; every task leaves the code in a working state.
4. **Group into checkpoints.** A checkpoint is the unit `/dc:implement` builds, tests and verifies in one run before stopping for the developer. Make each one:
   - a vertical slice the developer can check, usually 1–3 tasks;
   - finished with the whole test suite green and the stack checks passing;
   - provable by its acceptance criteria, each naming the spec item it proves. A small task may be a single checkpoint with one task. Don't pad.
5. **Check coverage.** Every requirement and success criterion of the spec appears in the **Spec coverage** table against a checkpoint. A spec item that no checkpoint delivers is either added or explained under **Risks**. Nothing in the plan goes beyond the spec's scope: if it isn't in the spec, it isn't in the plan.

## STEP 6: Write the plan

1. Use the template you read in step 1. Write `<task-dir>/plan.md` from it with the Write tool: fill every placeholder, delete the template comments, keep the section order. Write in the language the developer uses, but keep the markers in English.
2. **The checkpoint headings are read by a script.** Each is exactly `## CP<n>: <title>`, numbered CP1, CP2, … in file order with no gaps. Inside a checkpoint, use only `###` headings. No other line starts with `## CP`.
3. **No checkboxes** (`- [ ]`). The plan is approved by its hash and never edited to track progress; progress lives in `implementation-notes.md`.
4. No code beyond a one-line signature or a short example where words would be ambiguous. The plan says *what* and *where*; `/dc:implement` writes the code.
5. Before finishing, read the plan once as the new session would, and check:
   - CP1 can be started from `spec.md`, `plan.md` and the files they name, with no question;
   - every task has files, dependencies and a "done when"; every checkpoint has acceptance criteria and a verification;
   - no task is XL, and the order respects the dependency graph;
   - every spec item is in the coverage table.
   Fix what fails before stopping.

## Stop

Summarise the plan in at most six lines: the number of checkpoints with their titles, the main decision, the biggest risk, and any open question. Then print this closing message, with the placeholders filled in:

```text
Plan ready: <task-dir>/plan.md
Review it. To change something, tell me what.
When it's right, type '<approval-phrase>' on its own, run /clear, then /dc:implement.
```

Do nothing else in this turn.

## Later turns in this step

- **The developer asks for changes:** edit `<task-dir>/plan.md` (and nothing else), keeping the checkpoint headings numbered CP1, CP2, … in order. Say in one or two lines what changed, then print the closing message again. Any edit means the plan needs approving again.
- **The developer approves in other words** ("looks good", "ok", "yes"): that isn't approval. Answer: "Only the phrase counts: type '<approval-phrase>' on its own."
- **The harness confirms the approval** (context: "Plan approval recorded…"): tell the developer to run `/clear`, then `/dc:implement`, and nothing else.
- **The developer asks you to start coding now:** don't. The plan is built in a new session, so the next step is to type '<approval-phrase>', run `/clear`, then `/dc:implement`.
- **The developer wants to change the spec:** this step can't do it. Say that the spec is approved by its hash and can't be re-approved once planning has started; if the change is small, offer to record it in the plan under **Decisions** as "(developer, during planning)".
