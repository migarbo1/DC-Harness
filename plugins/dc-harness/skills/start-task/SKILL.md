---
name: start-task
description: Starts a DC-Harness task on the current branch. Records the commit-ref, interviews the developer one question at a time until the task is concrete, and writes spec.md for approval. Run as /dc:start-task <description> on a clean task branch.
disable-model-invocation: true
argument-hint: <description of the task>
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" start-task *), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" start-task *), Read(${CLAUDE_PLUGIN_ROOT}/templates/**)
---
<!-- Draws on: sdd specify (steps 1, 3, 5); agent-skills interview-me; agent-skills spec-driven-development (Phase 1). See THIRD_PARTY_NOTICES.md. -->

# /dc:start-task

The developer's task description, exactly as typed:

```text
$ARGUMENTS
```

This skill only produces `spec.md`. It never writes code, never plans, never commits, and never edits any file other than `spec.md` in the task folder. The harness blocks other writes during this step anyway.

## STEP 0: Preconditions

1. **Empty description.** If the text block above is empty or only whitespace, print exactly this and stop, without running anything:

   ```text
   Usage: /dc:start-task <description>
   Describe the task in a sentence or two, for example:
     /dc:start-task add a per-IP rate limit to the login endpoint
   Run it on a task branch (not a protected one like main), with a clean working tree.
   ```

2. **Gatekeeper.** Before reading or searching anything, run exactly this command, on its own.
   Never put the description in it:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" start-task "${CLAUDE_SESSION_ID}"
   ```

   Append nothing to it (no `; echo $?`, no `$LASTEXITCODE`, no pipe): the harness allows it only on its own. Tell the result from the output:

   - Exit `1`: print its one line exactly, and stop.
   - Exit `2`: print its `dc: internal:` line exactly, and stop.
   - Exit `0`: it prints `task-dir=…`, `commit-ref=…` and `approval-phrase=…`. Keep the three
     values: the steps below call them `<task-dir>`, `<commit-ref>` and `<approval-phrase>`.
     Don't work them out again yourself.

## STEP 1: Read the code

Read relevant source files present in the repo to ask informed questions. Relevant sources can be identified because they share the same entity name (eg `data-models/foo.py`), they are in the same module (eg `backend/`) or they share references (eg `frontend/pages/auth.html`, `backend/services/login.js` for "add security entry to the app").

- Search with the Glob and Grep tools in parallel for the names, routes, modules and terms in the description. Then read the 2–5 most relevant files, only the sections that matter.
- Read the project's own `AGENTS.md` / `CLAUDE.md` and `.harness/AGENTS.md` if you haven't.
- Read the spec template now, with the Read tool: `${CLAUDE_PLUGIN_ROOT}/templates/spec.md`. You'll fill it in step 3.
- Use the Read, Grep and Glob tools. Shell commands are limited to readers in this step (`git log`, `git show`, `ls`, `cat`…); anything else is blocked by the harness.
- Don't spawn subagents and don't design the solution: that is `/dc:plan`'s job.

Never ask the developer something the code already answers.

## STEP 2: Interview - one question at a time

Your first message after exploring has exactly this shape:

```text
HYPOTHESIS: <one sentence: what you think the developer actually wants>
CONFIDENCE: <0–100>% — <what's still missing, when below ~70%>

ASSUMPTIONS:
1. <something you'd otherwise fill in silently, with the file or fact it comes from>
2. …

Q1: <one focused question>
GUESS: <your best answer to it, and the reasoning behind it>
```

Then **end your turn** and wait for the answer. Every later turn holds one question only:

```text
<one line: what the answer changed, and your new confidence>

Q<n>: <one focused question>
GUESS: <your best answer, and why>
```

Rules:

- One question per turn. Never two questions in one message. The next question often depends on this answer.
- Always attach a guess. Reacting to a guess is faster than answering from scratch. Now and then guess in a direction you expect the developer to push back on, so agreement isn't automatic.
- Give priority to questions that may change the work the most: what "done" looks like, edge cases and error behaviour, what's explicitly out of scope, and constraints (compatibility, performance, data).
- Never take decissions on your own. Ask them as a choice between two concrete options.
- Correct your assumptions as answers come in, and say so in the one-line update.
- Stop asking when you can predict the developer's answer to the next three questions you would ask. A small, precise task may need only one or two questions; if the description already answers everything, say so in the first message (confidence ≥ 95%, no `Q1`) and go straight to step 3.
- After about three questions with no rise in confidence, say so: "I've asked <n> questions and still can't predict your answers. Something basic is missing. Can you describe the problem you're solving more in depth, rather than the change?"

## STEP 3: Write the spec

1. Use the template you read in step 1 (`${CLAUDE_PLUGIN_ROOT}/templates/spec.md`).
2. Write `<task-dir>/spec.md` from it with the Write tool: fill every placeholder, delete the template comments, keep the section order. Write in the language the developer uses.
3. What goes in:
   - **Summary** and **Requirements** from the description and the interview. Every requirement is testable and unambiguous.
   - **Context**: the files and patterns you found in step 1, with paths. Facts, no design.
   - **Success criteria**: concrete, checkable conditions, each naming the requirement it proves. No vague words: "fast", "user-friendly", "works correctly" become a number, an input and its expected result, or a visible behaviour.
   - **Assumptions**: everything you assumed and the developer didn't state or correct.
   - **Out of scope**: always filled. Half of misunderstandings are about what is *not* built.
   - **Open questions**: "None." if the interview closed them all.
4. Leave out the implementation plan, task lists, file-by-file changes and code: those come from
   `/dc:plan`.

## Stop

Summarise the spec in at most five lines (the goal, the number of requirements and success
criteria, the main out-of-scope item, any open question). Then print this closing message, with
the placeholders filled in:

```text
Spec ready: <task-dir>/spec.md
Review it. To change something, tell me what.
When it's right, type '<approval-phrase>' on its own, then run /dc:plan.
```

Do nothing else in this turn.

## Later turns in this step

- **The developer asks for changes:** edit `<task-dir>/spec.md` (and nothing else), say in one or two lines what changed, then print the closing message again. Any edit means the spec needs approving again.
- **The developer approves in other words** ("looks good", "ok", "yes"): that isn't approval. Answer: "Only the phrase counts: type '<approval-phrase>' on its own."
- **The harness confirms the approval** (context: "Spec approval recorded…"): tell the developer to run `/dc:plan`, and nothing else.
- **The developer asks you to plan or code now:** don't. Say the next step is to type '<approval-phrase>', then run `/dc:plan`.
