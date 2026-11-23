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
