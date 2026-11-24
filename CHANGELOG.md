# Changelog

## Unreleased

### Added

- `/dc:start-task` skill (`skills/start-task/SKILL.md`): usage on an empty description, the
  `task-state.sh` gatekeeper, code exploration, a one-question-at-a-time interview with the
  agent's guess, and `spec.md` written from `templates/spec.md`. Ends with the approval-phrase
  closing message.
- `templates/spec.md`: Summary, Context, Requirements, Success criteria, Assumptions, Out of scope,
  Open questions.
- `task-state.sh start-task` also prints `approval-phrase=<first specApprovalPhrase>`, so the
  skill's closing message uses the project's own phrase (contracts §4.2).
- `/dc:plan` skill (`skills/plan/SKILL.md`): the `task-state.sh` gatekeeper, read-only code
  exploration, at most a few blocking questions with the agent's guess, dependency graph,
  vertical slices, tasks with sizes and "done when", grouped into checkpoints, a spec-coverage
  check, and `plan.md` written from `templates/plan.md`. Re-planning keeps the checkpoints already
  in `implementation-notes.md`. Ends with the plan approval-phrase closing message.
- `templates/plan.md`: Summary, Technical context, Decisions, Dependency graph, Spec coverage,
  Risks, Open questions, then `## CP<n>: <title>` checkpoints (Goal, Tasks, Acceptance criteria,
  Verification). No checkboxes: the plan is approved by its hash.
- `task-state.sh plan` prints `approval-phrase=<first planApprovalPhrase>` (contracts §4.2).
- `tests/templates.bats`: a plan copied from the template passes check I5.
- `/dc:implement` skill (`skills/implement/SKILL.md`): argument check (`CP<n>`, `cp<n>`, `<n>` or
  nothing), the `task-state.sh` gatekeeper, reading the plan, spec and earlier notes in a fresh
  session, picking up an interrupted run, the implement → test → verify cycle per task with the
  scope-discipline rules (no commits), "every test must pass" without weakening checks, a fixed
  format for asking before deviating from the plan, the acceptance criteria and
  `stack-check.sh full` before the notes entry, and a closing message naming the next checkpoint
  or `/dc:assessment`. Builds exactly one checkpoint per run.
- `templates/implementation-notes.md`: one `## CP<n>: <title>` entry per checkpoint with Changes,
  Decisions, Deviations from the plan, Verification, and Noticed, not touched.
- `tests/templates.bats`: a notes entry copied from the template marks its checkpoint done; the
  implement skill calls the gatekeeper and the full stack check as allowed tools.

### Fixed

- `/dc:start-task`, `/dc:plan`, `/dc:implement`: the gatekeeper call must run with nothing
  appended (no `; echo $?` or `$LASTEXITCODE`). A chained command is blocked by `harness-guard.sh`
  while the step is read-only; the result is read from the script's output instead.
