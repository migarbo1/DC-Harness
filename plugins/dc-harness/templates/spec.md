<!-- Template for .tasks/<folder>/spec.md, filled by /dc:start-task.
     Replace every <placeholder> and delete these comments. Keep the section order.
     No marker in this file is read by a script: the spec is approved by its hash. -->

# Spec: <short title>

Branch: `<branch>` · Commit-ref: `<first 12 characters of commit-ref>` · Date: <YYYY-MM-DD>

## Summary

<2–3 sentences: what changes, for whom, and why. Use the developer's own words where possible.>

## Context

<What exists today, found while exploring the code: the files, modules and patterns this task
touches, with paths. Facts only, no design.>

- `<path>`: <what it does and why it matters here>

## Requirements

<Each one testable and unambiguous. MUST = the task fails without it; SHOULD = expected unless
there's a reason; MAY = nice to have.>

- **R1** (MUST): <requirement>
- **R2** (SHOULD): <requirement>

## Success criteria

<How we'll know it's done: concrete, checkable conditions (an input and its expected result, a
command and its output, a number to hit). Cover the main case and the edge cases agreed in the
interview. Each names the requirement it proves.>

- [ ] **SC1** (R1): When <input or action>, then <observable result>.
- [ ] **SC2** (R1): When <edge case>, then <observable result>.

## Assumptions

<What was taken as given without the developer saying so. Each one is something the developer
can correct before approving.>

- <assumption>

## Out of scope

<What this task explicitly does NOT do, one line each, with the reason when it isn't obvious.>

- <item>

## Open questions

<Anything still unresolved. "None." when the interview closed every question.>

None.
