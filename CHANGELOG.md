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
