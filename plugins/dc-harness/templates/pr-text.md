<!-- Template for .tasks/<folder>/pr-text.md, filled by /dc:pr-text. Replace every <placeholder> and delete these comments. Keep the section order and the headings.
     The developer pastes this file into an Azure DevOps PR description by hand, so:
       - the whole file stays within prTextMaxChars characters (default 3,000; Azure DevOps allows 4,000). pr-text-length.sh counts it;
       - plain Markdown only: headings, lists, tables, `code`, **bold**, > quotes. No HTML, no <details>, no checkboxes, no images, no links to local files (paths go in backticks);
       - Azure DevOps turns "#<number>" into a work-item link, "!<number>" into a PR link and "@<name>" into a mention: write them only when the files mean exactly that;
       - every line comes from the task's files (spec.md, plan.md, implementation-notes.md, assessment.md, approvals.json). Nothing is invented.
     No marker in this file is read by a script: its existence marks the task finished. The "Score:" line is copied exactly from assessment.md, in English. -->

# <short title, as in the spec>

<One or two sentences: what this PR does, for a reviewer who hasn't seen the task.>

## What

<What was built, from the spec's requirements and success criteria, as the reviewer will see it. One line each; group small items.>

- <behaviour or capability added or changed>

## Why

<One or two sentences: the reason for the change, from the spec's Summary and Context.>

## How

<The approach and the key decisions, from plan.md (Summary, Decisions) and the notes (Decisions), each with its reason. Only the ones a reviewer needs to judge the code.>

- <decision>, because <reason>.

## Changes made

<From the "Changes" of every checkpoint in the notes, merged: one line per file, or per folder when there are many. Tests included.>

- `<path>`: <what changed>

## Deviations from the plan

<From the notes' "Deviations from the plan", with the developer's answer that allowed each one. "None." when every checkpoint followed the plan.>

None.

## Not touched (intentionally)

<From the spec's "Out of scope" and the notes' "Noticed, not touched", each with its reason. "None." if both are empty.>

- <item>: <reason>

## Potential concerns

<What a reviewer should look at or confirm: open risks from plan.md, spec assumptions a reviewer may disagree with, a spec or plan changed after approval, and the gap named in the assessment's result. "None." if there are none.>

- <concern>

## Testing

<From the notes' "Verification": the tests added or changed, the full stack check that passed, and what a reviewer can try by hand.>

- Tests: `<test path>`: <the cases>
- Checks: `<lint, types and tests commands>` passed at the end of every checkpoint
- Manual: <what to try, or "None.">

## DC-Harness

| Gate | Status |
| --- | --- |
| Spec | <Approved ("<phrase>", <YYYY-MM-DD>), or Changed after approval, or Not approved> |
| Plan | <the same as for the spec>, <n> checkpoints |
| Implementation | <CP1–CP<n> done> |
| Assessment | <passed or not passed>, <passed>/<total> |

Score: <passed>/<total> (<passed or not passed>)

<!-- One line per question, in order: the question, shortened if needed, then the developer's last answer word for word, quoted. An answer that doesn't fit is cut at a word boundary and ends with " […]"; it is never reworded. -->

1. **<the question>** (<Passed | Not passed>)
   > <the developer's answer, word for word>
