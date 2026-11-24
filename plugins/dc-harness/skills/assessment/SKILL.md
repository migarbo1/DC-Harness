---
name: assessment
description: Checks that the developer understands the finished DC-Harness task. Reads the diff from the commit-ref plus untracked files and the implementation notes, writes the expected answers first, then asks the configured number of questions one at a time, with limited retries, and records the answers word for word and a passed/total score in assessment.md. Run as /dc:assessment once every checkpoint is done.
disable-model-invocation: true
allowed-tools: Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" assessment *), PowerShell(bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" assessment *), Bash(git diff *), PowerShell(git diff *), Bash(git ls-files *), PowerShell(git ls-files *), Read(${CLAUDE_PLUGIN_ROOT}/templates/**)
---
<!-- Draws on: socratic-skills quiz-me. See THIRD_PARTY_NOTICES.md. -->

# /dc:assessment

This skill checks that the developer understands what was built, before it goes to review. The agent wrote the code; the developer is the one who has to explain it in the PR and maintain it afterwards. The assessment is **active recall**: you ask, the developer answers in their own words. You don't explain the diff up front, and you never give an answer away before the developer has tried.

It writes only two files in the task folder: `.assessment-key.md` (the expected answers, hidden until the end, then deleted) and `assessment.md`. It never changes code, tests, `spec.md`, `plan.md` or `implementation-notes.md`, and **never commits**. Git stays with the developer.

The harness records every prompt the developer types during this step, word for word, in `approvals.json`. That file is the evidence; `assessment.md` must quote it exactly.

## STEP 0: Preconditions

Before reading or searching anything, run exactly this command, on its own:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" assessment "${CLAUDE_SESSION_ID}"
```

Append nothing to it (no `; echo $?`, no `$LASTEXITCODE`, no pipe). Tell the result from the output:

- Exit `1` (one line, not `task-dir=…`): print that line exactly, and stop.
- Exit `2` (a `dc: internal:` line): print it exactly, and stop.
- Exit `0`: it prints `task-dir=…`, `commit-ref=…`, `questions=…`, `pass-threshold=…` and `max-retries=…`. Keep the five values: the steps below call them `<task-dir>`, `<commit-ref>`, `<questions>`, `<pass-threshold>` and `<max-retries>`. Don't work them out again yourself, and don't read them from `.harness/config.json`.

Running this command starts the assessment **fresh**: the harness has cleared the answers of any earlier run. If `<task-dir>/assessment.md` or `<task-dir>/.assessment-key.md` exists from an earlier run, it is replaced in the steps below; don't reuse its questions.

## STEP 1: Read the work

1. **The diff.** Run these two commands, each on its own:

   ```bash
   git diff <commit-ref>
   ```

   ```bash
   git ls-files --others --exclude-standard
   ```

   The first shows every change since the task started, staged or not. The second lists the untracked files: the agent never commits, so files it created don't appear in `git diff`. Read each untracked file in full with the Read tool. Files under `.tasks/` are gitignored and never part of the diff.
2. `<task-dir>/implementation-notes.md` in full: the changes, decisions and deviations of every checkpoint. Then `<task-dir>/plan.md` and `<task-dir>/spec.md`, enough to know the goal of each checkpoint and the requirements the code proves.
3. The template, with the Read tool: `${CLAUDE_PLUGIN_ROOT}/templates/assessment.md`. You'll fill it in steps 3 and 5.
4. Where a hunk isn't clear on its own, read the surrounding code of the changed file. Use the Read, Grep and Glob tools; don't spawn subagents and don't run the tests or the app.

## STEP 2: Write the questions and the expected answers

Write exactly `<questions>` questions, and their expected answers, **before asking anything**.

1. **Choose what to ask about.** Spread the questions over the diff: the most important change of each checkpoint first, then the decisions and deviations in the notes, then the risky spots (error handling, edge cases, data that crosses a boundary). Prefer what the developer will have to defend in review or debug later over trivia.
2. **Make every question need reasoning.** The answer must not be something the developer can copy from the diff. Use these types, and mix them:
   - **Why:** why this approach and not the simpler or more obvious one (name it).
   - **What breaks:** what happens if this line, check or test is removed or changed.
   - **Edge case:** what the code does with a given input (empty, zero, missing, too large, concurrent), and why.
   - **Data flow:** how a value gets from A to B, and what changes it on the way.
   - **Test:** what a given test proves, and what bug it would catch.
   - **Alternative:** what would have to change if a requirement changed, and where.
3. **Be concrete.** Each question names the file, function or behaviour it is about (`calc/service.py`, `pow()`), so the developer knows where to look. One question asks one thing: no "and" joining two questions.
4. **Write the key** to `<task-dir>/.assessment-key.md` with the Write tool, in this form, one block per question:

   ```markdown
   # Assessment key (hidden until the end, then deleted)

   ## Q1
   Question: <the question, exactly as you will ask it>
   About: <path and line or function>
   Type: <why | what breaks | edge case | data flow | test | alternative>
   Expected: <the answer, in two or three sentences>
   Must show: <the reasoning an answer needs to count as correct: the "why", not only the "what">
   ```

The key exists before the first question so that grading follows a standard set in advance, not one shaped by the developer's answer. Don't show it, quote it, or hint at its contents in your messages.

## STEP 3: Start assessment.md

Write `<task-dir>/assessment.md` from the template with the Write tool: the title, the header lines (branch, commit-ref, date, `<questions>`, `<pass-threshold>`, `<max-retries>`) and **Sources** (the number of changed files, the untracked files, the checkpoints in the notes). No question blocks yet, no expected answers, and **no score line**: the score line marks the assessment finished, so it is written only in step 5. Write in the language the developer uses, but keep the `Score:` marker in English.

## STEP 4: Ask, one question at a time

Your first message after writing the files has exactly this shape:

```text
Assessment: <questions> questions about this task's changes, one at a time.
Answer in your own words; "not sure" is a fine answer. Passing needs <passed needed>/<questions>.

Q1 (<path or function>): <the question>
```

`<passed needed>` is the smallest whole number that, divided by `<questions>`, reaches `<pass-threshold>`. Then **end your turn** and wait. Every later turn ends with exactly one question (a new one, or a retry) and nothing after it.

**Grading an answer** (against the key's "Must show"):

- **Correct:** the answer shows the *why*, not just the *what*. Wording doesn't matter; the reasoning does. Say so in one line, with one sentence that adds or confirms the key point, then ask the next question.
- **Partial:** the core idea is there but a needed part is missing. Ask one follow-up about the missing part only. Don't fill it in yourself yet.
- **Wrong:** don't correct it yet. Rephrase the question, add a hint that points to where to look (a file, a line, an input to try), and ask a **different, related** question that leads to the same point.
- **"Not sure"** (or "I don't know", or no real attempt): explain the code block in question in two to four sentences, without stating the expected answer itself, then ask a **different, related** question that the explanation makes answerable.
- **The developer asks you something** (what a term means, which file you mean): answer it without giving away the expected answer. It isn't an attempt and doesn't use a retry, but it is still recorded.

**Retries.** After the first answer that isn't correct, a question gets at most `<max-retries>` retries (a partial follow-up, a rephrase, or an explanation each count as one). A question is **passed** when any answer within the limit is correct. When the limit is used up without a correct answer, give the expected answer in two or three sentences, mark the question **not passed**, and move on to the next question in the same message. Partial answers never pass on their own: only a correct answer does.

Each retry message has this shape:

```text
<one line: what the answer got right, if anything>
Retry <k>/<max-retries> on Q<n>: <the rephrase and hint, or the short explanation>
<the related question>
```

**Tone.** A tough but supportive senior colleague, not a gotcha machine. No trick questions, no sarcasm, no lecture. If the developer clearly knows the code, say so.

**Keep assessment.md up to date.** After grading each answer, update the current question's block in `<task-dir>/assessment.md` (Edit tool): the question, what it is about, every answer so far, its grade, your follow-ups, and, once the question is closed, its **Result** line. Leave **Expected answer** empty until step 5.

**The developer's words are copied, never retyped.** Before each update, read `<task-dir>/approvals.json` with the Read tool. Its `assessment` array holds every prompt typed since `/dc:assessment` started, in order, word for word. Copy each entry's `text` exactly into the block of the question that was open when it was typed, quoted with `> ` on every line: no fixing typos, no trimming, no summarising. If an entry is missing (the harness didn't record it), quote the answer from the conversation and add `(not in approvals.json)` after it. Never edit `approvals.json`: only the harness writes it.

## STEP 5: Finish

When all `<questions>` questions are closed:

1. **Score.** `<passed>` is the number of questions passed; the total is `<questions>`. The result is `passed` when `<passed>` ÷ `<questions>` ≥ `<pass-threshold>`, otherwise `not passed`.
2. **Complete assessment.md.** Read `<task-dir>/.assessment-key.md` and copy each expected answer, with its "Must show", under its question's **Expected answer** heading. Check once more against `approvals.json` that every answer is quoted word for word. Then fill the final **Result** section: the score line, exactly in this form, on its own line:

   ```text
   Score: <passed>/<questions> (passed)
   ```

   or `Score: <passed>/<questions> (not passed)`, followed by one or two lines: what the developer clearly understands, and the one gap worth a second look before review, or "No gaps found.". Write the score line once, only here.
3. **Delete the key**: remove `<task-dir>/.assessment-key.md` (for example `rm "<task-dir>/.assessment-key.md"`). Its contents now live in `assessment.md`.

## Stop

Print this closing message, with the placeholders filled in:

```text
Assessment done: Score <passed>/<questions> (<passed or not passed>)
Record: <task-dir>/assessment.md
Next: /dc:pr-text.
```

When the result is `not passed`, add one line before `Next`: `To try again with new questions, run /dc:assessment. Either way, the score goes into the PR text.`

Do nothing else in this turn.

## Later turns in this step

- **The developer asks for the answers before finishing, or for a hint beyond the rules above:** don't. Say that the expected answers are shown at the end, in `assessment.md`.
- **The developer wants to skip a question:** treat it as "not sure" (explanation and a related question). Every question is asked; there is no skipping.
- **The developer disagrees with a grade:** look at their argument against the code, not against the key. If they are right, say so, change the grade in `assessment.md`, and note under **Result** of that question: "(grade changed after the developer's argument)". The key is a standard, not proof.
- **The developer finds a bug or asks for a code change:** don't change code in this step. Record it in the current question's **Result** line as a concern, finish the assessment, and tell them in the closing message: fix it themselves, or run `/dc:plan` to add a checkpoint, then `/dc:assessment` again.
- **The developer asks you to commit, push or open the PR:** don't. Git stays with the developer. The next step is `/dc:pr-text`.
- **The session was interrupted mid-assessment:** the answers so far are in `approvals.json`, but a re-run of `/dc:assessment` starts fresh with new questions. Say so, and tell the developer to run `/dc:assessment` again.
