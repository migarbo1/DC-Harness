---
name: implement
description: Builds the next checkpoint of an approved DC-Harness plan - implement, test, verify, run the full stack check, then write its implementation-notes.md entry and stop for the developer. Never commits. Run as /dc:implement in a new session (after /clear) once the plan approval phrase is typed.
disable-model-invocation: true
argument-hint: "[<checkpoint>, e.g. CP2]"
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" implement *), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" implement *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-check.sh" full), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-check.sh" full), Read(${CLAUDE_PLUGIN_ROOT}/templates/**)
---
<!-- Draws on: agent-skills incremental-implementation. See THIRD_PARTY_NOTICES.md. -->

# /dc:implement

The checkpoint the developer asked for, exactly as typed (often empty):

```text
$ARGUMENTS
```

This skill builds **one checkpoint** of the approved plan: always the first one not done yet. It writes code and tests, and appends one entry to `implementation-notes.md`. It never edits `spec.md` or `plan.md`, never builds a later checkpoint, and **never commits**: no `git commit`, `git add`, `git stash`, `git reset`, `git checkout -- <file>`, `git restore`, `git push`, merge or rebase. Git stays with the developer.

This session doesn't remember the planning conversation, on purpose. Everything you need is in `spec.md`, `plan.md`, `implementation-notes.md` and the code. If the plan isn't enough to build the checkpoint, that is a gap in the plan: say so (step 4) rather than guessing.

## STEP 0: Preconditions

1. **The argument.** Look at the text block above, trimmed:
   - empty: no checkpoint argument;
   - exactly `CP<n>`, `cp<n>` or `<n>` (digits only, for example `CP2`, `cp2`, `2`): use it as the checkpoint argument;
   - anything else: print exactly this and stop, without running anything:

     ```text
     Usage: /dc:implement [<checkpoint>]
     Builds the next checkpoint of the approved plan, for example:
       /dc:implement
       /dc:implement CP2
     Only the next checkpoint not done can run; giving it is optional.
     ```

2. **Gatekeeper.** Before reading or searching anything, run exactly this command, on its own. With a checkpoint argument, add it at the end, as typed (for example `… "${CLAUDE_SESSION_ID}" CP2`):

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" implement "${CLAUDE_SESSION_ID}"
   ```

   Append nothing to it: no `; echo $?`, no `$LASTEXITCODE`, no pipe. The previous step is read-only, so the harness allows this command only on its own. Tell the result from the output:

   - Exit `1` (one line, not `task-dir=…`): print that line exactly, and stop.
   - Exit `2` (a `dc: internal:` line): print it exactly, and stop.
   - Exit `0`: it prints `task-dir=…` and `checkpoint=CP<n>`. Keep both values: the steps below call them `<task-dir>` and `<CP>`. `<CP>` is the checkpoint this run builds, and the only one. Don't work them out again yourself.

## STEP 1: Read the inputs

1. `<task-dir>/plan.md` in full, then `<task-dir>/spec.md` in full. The plan is approved: it is the contract for this run. Find the `## <CP>: <title>` section: its goal, tasks, acceptance criteria and verification are your work list. Read the plan's Technical context, Decisions and Risks too: they apply to every checkpoint.
2. `<task-dir>/implementation-notes.md`, if it exists: the entries of the checkpoints already built (changes, decisions, deviations). Build on them; don't redo or undo them.
3. The notes template, with the Read tool: `${CLAUDE_PLUGIN_ROOT}/templates/implementation-notes.md`. You'll fill it in step 6.
4. The project's own `AGENTS.md` / `CLAUDE.md`, `.harness/AGENTS.md`, and `.harness/config.json` (`stack` and `stackCommands`) if you haven't. The check commands are the project's `stackCommands`, or the stack defaults when it doesn't override them.
5. **An interrupted run.** Run `git status --short`. Changes are expected from the checkpoints already in the notes. A changed file that no notes entry explains is most likely an earlier, unfinished run of `<CP>` (or an edit by the developer): read it and carry on from it, don't start over. If you can't tell which, ask before touching it.
6. Read the files the checkpoint's tasks name, and one neighbour that shows the pattern to follow (structure, naming, error handling, how tests are written). Use the Read, Grep and Glob tools; don't spawn subagents.

## STEP 2: Build the checkpoint, one task at a time

Work through the checkpoint's tasks in plan order. For each task, repeat this cycle in small increments:

1. **Implement** the smallest complete piece of the task.
2. **Test.** Write or change the tests the task names, next to the code they prove. Prefer a test that fails first and expresses the goal, then make it pass.
3. **Verify.** Run the affected tests with the project's tests command (for example `pytest tests/test_foo.py`), plus lint or types when you touched what they check. Fix what fails before the next increment. The task is done when its "done when" holds.

Rules while building (from incremental implementation):

- **Simplicity first.** Ask what the simplest thing is that could work. No abstraction before its third use, no option or error handling for a case that can't happen, no code for requirements the spec doesn't have. Three similar lines beat a premature helper.
- **Scope discipline.** Touch only what `<CP>`'s tasks require. Don't tidy neighbouring code, don't reorder imports in files you didn't otherwise change, don't delete comments you don't understand, modernise syntax, and don't start the next checkpoint's work "while you're here". Note anything you see under **Noticed, not touched** instead.
- **One thing at a time.** Each increment changes one logical thing.
- **Keep it working.** After each increment the code builds and the existing tests pass. Never leave the tree broken between increments: the harness checks it at the end of every turn.
- **Safe defaults.** New behaviour is opt-in where the plan allows it; existing behaviour doesn't change unless the plan says so.
- **Easy to revert.** Prefer additive changes. Don't delete something and replace it in a way that can't be undone file by file.
- **Run, don't guess.** Don't write more than about 100 lines without running the tests. Don't re-run a passing command when nothing changed since.

## STEP 3: Every test must pass

A failing test, lint error or type error is treated as **caused by this task**, even if it looks unrelated, and you fix it. Never make a check pass by weakening it: don't skip, `xfail`, delete or loosen a test, don't add `# noqa` / `# type: ignore` to hide a real problem, and don't change the lint, type or test configuration. If a fix needs one of those, it is a deviation (step 4).

At the end of every turn in which you changed files, the harness's Stop hook runs the affected checks and **won't let the turn end** until they pass, showing you the failures. Fix them and carry on. If a check fails for a reason you can't fix (a service that is down, a missing tool), stop, say exactly what fails and why, and don't write the notes entry; the developer decides (they can press Esc to interrupt).

## STEP 4: Deviations: stop and ask

The plan is approved by its hash, so you build what it says. **Stop and ask the developer before**:

- changing a file, interface, name or behaviour in a way the plan doesn't describe;
- adding a dependency, a migration, or a configuration change the plan doesn't name;
- building something the plan leaves to a later checkpoint, or leaving out part of `<CP>`;
- working around an acceptance criterion that can't be met as written, or a spec requirement the plan turns out to contradict.

Small choices the plan leaves open (a local name, a private helper, the order of two lines) are not deviations: take the lower-risk option and record it under **Decisions**.

To ask, end the turn with this, one deviation per turn:

```text
DEVIATION in <CP>: <what the plan says, and why it doesn't work as written>
OPTIONS:
  A. <option>: <consequence>
  B. <option>: <consequence>
GUESS: <A or B, and why>
```

Leave the code passing the checks before you ask (the Stop hook requires it); if that isn't possible, say so. When the developer answers, carry on and record the answer under **Deviations from the plan** as "(developer, during <CP>)". If the answer changes the plan itself (new or reordered checkpoints, different scope), don't build it: tell the developer to run `/dc:plan` to revise the plan, which then needs a new approval and `/clear`.

## STEP 5: Verify the checkpoint

When every task of `<CP>` is done:

1. Check each **acceptance criterion** of `<CP>` and how you showed it holds (a test, a command and its output). One that doesn't hold means the checkpoint isn't done: go back to step 2.
2. Run the **full stack check**, exactly this command, on its own:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/stack-check.sh" full
   ```

   - Exit `0`: passed. Go on to step 6.
   - Exit `1`: a check failed. Its output names the check and shows the failures. Fix them (step 3) and run it again. Don't go on until it passes.
   - Exit `2`: print its `dc: internal:` line exactly and stop, without writing the notes entry.
3. Look over your own diff (`git diff` and `git status --short`): nothing outside `<CP>`'s scope, no debug output, no leftover files. Fix what you find and run the full check again.

## STEP 6: Write the notes entry

Only after the full check passes: the entry marks `<CP>` as done, so writing it early would let the next checkpoint start on unfinished work.

1. If `<task-dir>/implementation-notes.md` doesn't exist, create it from the template: the title line, then this checkpoint's entry. If it exists, **append** this checkpoint's entry at the end with the Edit tool, and change nothing above it.
2. **The heading is read by a script.** It is exactly the checkpoint's heading in `plan.md`: `## <CP>: <title>`. Inside the entry use only `###` headings. No other line starts with `## CP`.
3. Fill every section from the template and delete the template comments. Write in the language the developer uses, but keep the markers in English. Keep it short: the notes are read by `/dc:assessment` and `/dc:pr-text`, not by a reviewer of every line.
   - **Changes:** every file you changed or created, tests included, one line each.
   - **Decisions:** the small choices you made and why.
   - **Deviations from the plan:** each one with the developer's answer, or "None.".
   - **Verification:** the acceptance criteria and how each held; the full check's commands.
   - **Noticed, not touched:** out-of-scope problems you saw, or "None.".

## Stop

Find the next checkpoint: the first `## CP<m>` in `plan.md` after `<CP>`, if there is one. Then summarise what was built in at most five lines (the tasks done, the tests added, any deviation), and print this closing message, with the placeholders filled in:

```text
<CP> done: <title>
Notes: <task-dir>/implementation-notes.md
Review the changes (git diff, git status). Nothing is committed.
Next: /dc:implement for CP<m>: <title>. No /clear needed.
```

When `<CP>` was the last checkpoint, the last line is instead: `All checkpoints done. Next: /dc:assessment.`

Do nothing else in this turn. Don't start the next checkpoint.

## Later turns in this step

- **The developer asks for changes to `<CP>`:** make them, within its scope, following steps 2–5 (tests, full check). Then update `<CP>`'s entry in the notes (and only that entry), say in one or two lines what changed, and print the closing message again.
- **The developer says "continue", "next" or "go on":** don't start the next checkpoint here. The harness checks its preconditions only through the command: tell them to run `/dc:implement`.
- **The developer asks you to commit, push or open the PR:** don't. Git stays with the developer, and the task stays open until `/dc:pr-text`.
- **The developer asks to change the plan or the spec:** this step can't do it. A small change inside `<CP>` is a deviation (step 4). Anything bigger means running `/dc:plan` again, which needs a new approval and `/clear`.
- **The harness blocks the end of a turn with failing checks:** fix them, as in step 3, and only then finish the turn.
