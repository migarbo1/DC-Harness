# Dogfood log

One entry per task run on the dogfood sandbox (`../dc-sandbox`): timings, friction, and the fix.
Phase 2 needs at least two real tasks per skill, and five end-to-end tasks before v0.

## 2026-11-23 · `/dc:start-task` · smoke test (headless, not a real task)

- **How:** `claude -p` in the sandbox with `--plugin-dir`, continued with `--continue`; the spec
  write approved with `--allowedTools "Write(.tasks/**)"`, standing in for the developer's click.
- **Task:** "add a power operation to the calculator".
- **Flow:** empty description → usage, no task created. Dirty tree (a stray `.spike-log/`) → the
  S4 refusal, printed exactly. Then: turn 1 (gatekeeper, 9 reads/searches, hypothesis 75%, six
  assumptions with file references, one question with a guess) ~30 s; turn 2 (answer → spec
  written, closing message with the project's phrase) ~32 s; turn 3 ("Specification agreed") →
  `approvals.json` recorded, hash equal to `spec.md`, agent said "run `/dc:plan`".
- **Spec quality:** 8 requirements, 11 testable success criteria (inputs and exact responses),
  context with paths, assumptions and out of scope filled.
- **Friction and fixes:**
  - Every plugin file access prompted (the `task-state.sh` call, the template read). Fixed with
    `allowed-tools` using exact `${CLAUDE_PLUGIN_ROOT}` paths, for PowerShell as well as Bash
    (spike S9).
  - Before that fix the agent explored the code before the gatekeeper ran. Step 0 now says to run
    it before reading anything.
- **Still to do:** two real interactive tasks in the desktop app, to check the question-per-turn
  discipline over a longer interview, edits after review, and "looks good" handling.

## 2026-11-23 · `/dc:plan` · smoke test (headless, not a real task)

- **How:** a task started with `task-state.sh start-task`, a hand-written spec ("add `/pow` and
  `/mod` to the calculator", 3 requirements, 3 success criteria) approved by piping a
  "Specification agreed" payload into `approval-capture.sh`. Then `claude -p "/dc:plan"` through
  `dev-claude.sh`; the `plan.md` write approved with `--allowedTools`, standing in for the
  developer's click.
- **Flow:** gatekeeper ran first (`allowed-tools`, no prompt), template read with no prompt, then
  exploration and the plan: ~70–80 s per run. No file outside `.tasks/` changed. Closing message
  with the project's phrase. "Plan agreed" piped into the hook recorded the hash;
  `task-state.sh implement` refused the planning session (I4) and gave `checkpoint=CP1` to a new
  one (I5 passed on the agent-written headings).
- **Plan quality:** 2 checkpoints, each a vertical slice (service + controller + router + tests)
  of one M task; technical context with real paths, signatures, test names and the venv check
  commands; 5 decisions with reasons; spec-coverage table complete; 2 risks (pow overflow, complex
  results) left out of scope instead of silently added. Its tasks named exact test cases, so a new
  session could start CP1 without exploring. The checkpoint order differed between the two runs
  (`/pow` first, then `/mod` first, each with a stated reason): not a problem, but plans are not
  deterministic.
- **Friction and fixes:**
  - `--allowedTools "Write(.tasks/**)"` no longer matches file writes in this CLI version
    ("only Edit(path) rules are"); `Edit(.tasks/**)` does. The first run stopped correctly,
    without writing anywhere else, and printed the plan summary. Only affects headless testing:
    the skills leave artefact writes to the normal prompt (S9).
- **Still to do:** two real interactive tasks in the desktop app, after a real `/dc:start-task`:
  review edits, "looks good" handling, a blocking question, and a re-plan after CP1 is done.
