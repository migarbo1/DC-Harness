# Third-party notices

The DC-Harness skills are our own text, written with the open-source projects below as a
reference. Some steps, rules and template sections are adapted from them. No upstream files are
copied into this plugin.

All four projects are under the MIT licence. Their copyright notices are listed below, and the MIT
licence text that applies to each of them is at the end of this file.

| Project | Licence | Copyright | Our skills that draw on it |
| --- | --- | --- | --- |
| [agent-skills](https://github.com/addyosmani/agent-skills) | MIT | Copyright (c) 2025 Addy Osmani | `/dc:start-task`, `/dc:plan`, `/dc:implement`, `/dc:pr-text` |
| [sdd](https://github.com/alfredoperez/sdd) | MIT | Copyright (c) 2026 Alfredo Perez | `/dc:start-task`, `/dc:pr-text` |
| [socratic-skills](https://github.com/rodbv/socratic-skills) | MIT | Copyright (c) 2026 Rodrigo Vieira | `/dc:assessment` |
| [spec-kit](https://github.com/github/spec-kit) | MIT | Copyright GitHub, Inc. | `/dc:plan` |

## What each project contributes

### agent-skills

<https://github.com/addyosmani/agent-skills>

Copyright (c) 2025 Addy Osmani. MIT licence.

- `/dc:start-task`: from `interview-me`, one question at a time, each with the agent's best guess,
  and surfacing assumptions. From `spec-driven-development` (Phase 1), turning vague requirements
  into testable success criteria, and the spec template, trimmed.
- `/dc:plan`: from `planning-and-task-breakdown`, read-only planning, the dependency graph,
  vertical slices, the task template, the task sizes and checkpoints.
- `/dc:implement`: from `incremental-implementation`, the implement → test → verify cycle and the
  scope-discipline rules, without its commit steps.
- `/dc:pr-text`: from `git-workflow-and-versioning` ("Change Summaries"), the blocks "changes
  made", "things intentionally not touched" and "potential concerns".

### sdd

<https://github.com/alfredoperez/sdd>

Copyright (c) 2026 Alfredo Perez. MIT licence.

- `/dc:start-task`: from `specify` (steps 1, 3 and 5), stopping with usage on an empty
  description, and exploring the code before asking questions.
- `/dc:pr-text`: from `implement` (step 7), the PR body sections What, Why and Testing, without
  any git or PR commands.

### socratic-skills

<https://github.com/rodbv/socratic-skills>

Copyright (c) 2026 Rodrigo Vieira. MIT licence.

- `/dc:assessment`: from `quiz-me`, the code-mode question types, grading the *why*, asking a
  follow-up before correcting, and the final score.

### spec-kit

<https://github.com/github/spec-kit>

Copyright GitHub, Inc. MIT licence.

- `/dc:plan`: from the plan template, the structure of the plan (Summary, Technical context,
  and recording the structure decisions with their reasons).

## Ideas only, no text

The following projects shaped the design, but no text or code from them is used, so their licences
put no conditions on this plugin. They are listed as credit.

- [silver-bullet](https://github.com/alo-exp/silver-bullet) (BUSL 1.1): the idea that hooks can
  block the agent until a step's output exists.
- [sdd](https://github.com/alfredoperez/sdd): besides the text above, the idea of a state file
  that lets a new session resume a task.

## MIT licence

The following text applies to agent-skills, sdd, socratic-skills and spec-kit, each with its own
copyright notice as listed above.

```text
MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

Copyright notices and licences were taken from each project's `LICENSE` file on 2026-11-19.
