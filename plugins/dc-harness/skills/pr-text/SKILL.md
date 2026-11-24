---
name: pr-text
description: Writes the PR description for a finished DC-Harness task. Reads spec.md, plan.md, implementation-notes.md, assessment.md and approvals.json and summarises what was built and why, how, the key decisions, deviations, what was left out, concerns, testing, the gate status and the assessment score with the developer's answers, in pr-text.md within prTextMaxChars characters. Never commits, pushes or opens the PR. Run as /dc:pr-text after /dc:assessment.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" pr-text *), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" pr-text *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-text-length.sh"), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-text-length.sh"), Read(${CLAUDE_PLUGIN_ROOT}/templates/**)
---
<!-- Draws on: sdd implement (step 7); agent-skills git-workflow-and-versioning ("Change Summaries"). See THIRD_PARTY_NOTICES.md. -->

# /dc:pr-text

This skill writes the description of the pull request: the only thing from the task that leaves the developer's machine. The artefacts in `.tasks/` stay local; the reviewer sees only this text. It has to let a reviewer judge the change without the task folder: what was built and why, how, what was left out on purpose, what to look at, how it was tested, and that the developer understands it.

It writes one file, `pr-text.md`, in the task folder. Writing it **finishes the task**. It never changes code, tests, `spec.md`, `plan.md`, `implementation-notes.md` or `assessment.md`, and it **never commits, pushes or opens the PR**: no `git` commands that change anything, no `az repos`, no `gh`. The developer pastes the text into the Azure DevOps PR by hand.

## STEP 0: Preconditions

Before reading or searching anything, run exactly this command, on its own:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" pr-text "${CLAUDE_SESSION_ID}"
```

Append nothing to it (no `; echo $?`, no `$LASTEXITCODE`, no pipe). Tell the result from the output:

- Exit `1` (one line, not `task-dir=…`): print that line exactly, and stop.
- Exit `2` (a `dc: internal:` line): print it exactly, and stop.
- Exit `0`: it prints `task-dir=…`, `max-chars=…`, `spec-approval=…` and `plan-approval=…`. Keep the four values: the steps below call them `<task-dir>`, `<max-chars>`, `<spec-approval>` and `<plan-approval>`. Don't work them out again yourself, and don't read them from `.harness/config.json`. An approval is `approved` (the file is the one the developer approved), `changed` (approved, then edited) or `none`.

The command can run on a finished task: then `<task-dir>/pr-text.md` already exists, and this run **regenerates** it from the files. Don't start from the old text; the developer's later edits to it are not kept, so say so in the closing message.

## STEP 1: Read the task's files

Read each in full, with the Read tool:

1. `<task-dir>/spec.md`: Summary, Requirements, Success criteria, Assumptions, Out of scope.
2. `<task-dir>/plan.md`: Summary, Decisions, Risks, and the `## CP<n>: <title>` checkpoints.
3. `<task-dir>/implementation-notes.md`: for every checkpoint, Changes, Decisions, Deviations from the plan, Verification, and Noticed, not touched.
4. `<task-dir>/assessment.md`: each question, the developer's quoted answers, each question's result, and the final **Result** with the `Score:` line.
5. `<task-dir>/approvals.json`: the `phrase` and `at` of the `spec` and `plan` approvals, for the gate table. Read it only; never edit it.
6. The template: `${CLAUDE_PLUGIN_ROOT}/templates/pr-text.md`.

These files are the only source. Don't read the diff or the code, don't run the tests or the app, and don't spawn subagents: the notes already list the changes and the checks that passed. If one of them is missing (the harness only requires `spec.md` and the score line), write "not available" in the sections that need it and name it under **Potential concerns**.

## STEP 2: Write pr-text.md

Write `<task-dir>/pr-text.md` from the template with the Write tool, keeping its sections in order, and delete the template comments. Write in the language of the spec, except `Score:`, which is copied exactly.

**Who reads it.** A reviewer who knows the codebase but not this task. Lead with behaviour, not with files. Explain *why*, not only *what*. Short lines, no filler, no praise of the work, no "this PR".

**Each section, and where it comes from:**

- **Title and opening line:** the spec's title, and one or two sentences that tell the whole change.
- **What:** the requirements that were built, as behaviour the reviewer can check (from the requirements and success criteria). Group small ones.
- **Why:** one or two sentences, from the spec's Summary and Context.
- **How:** the approach and the decisions that shape the code, from the plan's Summary and Decisions and the notes' Decisions, each with its reason. Leave out decisions that don't help review.
- **Changes made:** the notes' Changes of every checkpoint, merged into one list: one line per file, or per folder when there are many. A file changed in two checkpoints appears once.
- **Deviations from the plan:** every deviation in the notes, with the developer's answer that allowed it. Never leave one out: a reviewer comparing the code with the plan needs it. "None." if there were none.
- **Not touched (intentionally):** the spec's Out of scope and the notes' "Noticed, not touched", with reasons. This shows the scope was kept on purpose.
- **Potential concerns:** open risks from the plan, spec assumptions a reviewer may disagree with, the gap named in the assessment's Result, and these, always, when they apply:
  - `<spec-approval>` or `<plan-approval>` is `changed`: "`spec.md` (or `plan.md`) was edited after approval; the approved version is not the one summarised here."
  - `<spec-approval>` or `<plan-approval>` is `none`: "The spec (or plan) has no recorded approval."
  - the assessment was `not passed`: "The developer's assessment did not pass (<score>)."
- **Testing:** the tests added or changed, the full stack check that passed at every checkpoint (its commands, from the notes' Verification), and the manual checks.
- **DC-Harness:** the gate table and the assessment.
  - Spec and Plan rows: `<spec-approval>` / `<plan-approval>` `approved` → "Approved" with the phrase and the date of `at` from `approvals.json`; `changed` → "Changed after approval"; `none` → "Not approved". The plan row adds the number of checkpoints.
  - Implementation row: the checkpoints in the notes (`CP1–CP3 done`).
  - The score line, **copied exactly** from `assessment.md`, on its own line: `Score: <passed>/<total> (passed)` or `(not passed)`. Never recompute or round it.
  - Then one numbered item per question, in order: the question (shortened if it is long), its result, and the developer's **last** answer to it, quoted with `> `, copied **word for word** from `assessment.md`. Don't fix typos, don't reword, don't summarise. An answer too long for the limit is cut at a word boundary and ends with ` […]`.

**Facts only.** Every line comes from the files in step 1. Don't add requirements, tests, checks or decisions that aren't there, don't claim a check that the notes don't record, and don't soften a `not passed` or a `changed`. When the files disagree (the notes built something the spec doesn't ask for), say so under **Potential concerns**.

**Azure DevOps.** The text is pasted into an Azure DevOps PR description:

- Plain Markdown only: headings, lists, tables, `code`, **bold**, `> ` quotes. No HTML, no `<details>`, no checkboxes, no images, no emoji shortcodes.
- File paths go in backticks, never as links: relative links don't resolve in a PR.
- `#<number>` becomes a link to a work item, `!<number>` to a pull request, `@<name>` a mention. Write them only when the files name that work item, PR or person; otherwise write "item 12", "PR 34" or the name without `@`. Inside backticks they stay plain text.
- No AI or tool attribution line ("Generated with …"). The DC-Harness section already says how the work was done.
- Never copy secrets, tokens, connection strings, customer data or internal URLs that appear in the files.

## STEP 3: Check the length

The whole file must be at most `<max-chars>` characters. You can't count reliably yourself, so run exactly this command, on its own:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/pr-text-length.sh"
```

- Exit `0`: it prints `chars=<n> max=<m>`. Keep `<n>` for the closing message. Go on to Stop.
- Exit `1`: it prints how many characters are over. Shorten the file with the Edit tool, in this order, and run the command again after each pass, until it passes:
  1. **Changes made:** one line per folder instead of per file.
  2. **How** and **Not touched:** merge lines, cut reasons to a few words, drop the decisions least useful for review.
  3. **Testing:** test files by name only, without listing the cases.
  4. **What:** group requirements into fewer lines.
  5. Questions in the DC-Harness section: shorten the question text, then cut the longest answers with ` […]`.

  Never drop: the title, Why, the deviations, the concerns, the gate table, the `Score:` line, or a question and the start of its answer. If the file is still over after all five, print the script's line, and stop without the closing message: the limit is the tech lead's setting (`prTextMaxChars`).
- Exit `2` (a `dc: internal:` line): print it exactly, and stop.

## Stop

Print this closing message, with the placeholders filled in:

```text
PR text ready: <task-dir>/pr-text.md (<n>/<max-chars> characters)
Task finished. Open the file, copy all of it, and paste it into the PR description in Azure DevOps.
Nothing was committed, pushed or opened: git and the PR stay with you.
```

When this run regenerated an existing `pr-text.md`, add one line before the last: `Regenerated from the task's files; earlier edits to pr-text.md were replaced.`

When `<spec-approval>` or `<plan-approval>` is not `approved`, or the assessment was `not passed`, add one line: `Note: <the concern>, stated in the PR text under Potential concerns.`

Do nothing else in this turn.

## Later turns in this step

- **The developer asks for changes to the text** (shorter, another emphasis, another language, a work-item link): edit `pr-text.md` with the Edit tool, keeping the facts-only rule and the word-for-word answers, run `pr-text-length.sh` again, and print the closing message again.
- **The developer asks to hide or soften a `not passed`, a `changed` approval or a deviation:** don't. Those are the record of the task; the developer can still edit the PR description after pasting it, outside the harness.
- **The developer asks you to commit, push, or open or update the PR:** don't. Git and the PR stay with the developer.
- **The developer wants a code change:** this step doesn't change code, and the task is finished, so `/dc:plan` and `/dc:implement` refuse. v0 has no revision cycle: they make the change themselves, or start a new task on a new branch.
- **The developer asks to run `/dc:assessment` again:** it refuses on a finished task. The score in the PR text is the one in `assessment.md`.
