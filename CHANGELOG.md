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
