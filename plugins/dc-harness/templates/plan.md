<!-- Template for .tasks/<folder>/plan.md, filled by /dc:plan.
     Replace every <placeholder> and delete these comments. Keep the section order.
     Fixed markers (contracts §6.1), read by task-state.sh:
       - every checkpoint is a level-2 heading "## CP<n>: <title>", numbered CP1, CP2, … in file
         order with no gaps, in implementation order;
       - inside a checkpoint use only level-3 headings (###), so no other line starts with "## CP";
       - the markers stay in English, whatever language the rest is written in.
     No checkboxes: plan.md is approved by its hash, so it is never edited to tick progress.
     Progress lives in implementation-notes.md. -->

# Plan: <short title, as in the spec>

Branch: `<branch>` · Spec: `spec.md` · Date: <YYYY-MM-DD>

## Summary

<2–3 sentences: what will be built (from the spec) and the technical approach chosen.>

## Technical context

<What a new session needs to start CP1 without exploring from scratch. Facts found while
exploring, with paths.>

- **Stack and checks:** <language and version, framework; the lint, types and tests commands
  from `.harness/config.json` or the stack defaults>
- **Code this task touches:** `<path>`: <what it does, and the pattern to follow>
- **Tests:** <where the tests live, how they're named, the fixtures or helpers to reuse>
- **Conventions:** <naming, error handling, layering or style rules the new code must match>

## Decisions

<Design choices that shape more than one checkpoint, each with its reason and the alternative
set aside. Decisions the developer took while planning say so: "(developer, during planning)".>

- **D1:** <decision>. Because <reason>. Not <alternative>, because <why not>.

## Dependency graph

<What has to exist before what. Foundations at the top; the checkpoints follow this order.>

```text
<component>
  └── <component that depends on it>
        └── <…>
```

## Spec coverage

<Every requirement and success criterion of the spec, and the checkpoint that delivers it.
A spec item with no checkpoint is a gap: cover it or explain it under Risks.>

| Spec item | Checkpoint |
| --- | --- |
| R1 / SC1 | CP1 |

## Risks

<Unknowns and things that could go wrong, high-risk first. "None." if there are none.>

| Risk | Impact | Mitigation |
| --- | --- | --- |
| <risk> | <High / Medium / Low> | <what the plan does about it, and in which checkpoint> |

## Open questions

<Anything the developer must decide before approving. "None." when nothing is open.>

None.

<!-- Checkpoints. Each one is a vertical slice that /dc:implement builds, tests and verifies in a
     single run, leaving the system working and every test green. Usually 1–3 tasks. Tasks are
     numbered T1, T2, … across the whole plan. Sizes: XS (1 file), S (1–2), M (3–5), L (5–8);
     XL is too big, split it. -->

## CP1: <title: what works when this checkpoint is done>

### Goal

<One or two sentences: the slice delivered, and the spec items it proves (R…, SC…).>

### Tasks

- **T1: <short title>** (<size>). <What this task does, in one or two sentences.>
  - Files: `<path>`, `<test path>`
  - Depends on: <None, or T…>
  - Done when: <specific, testable condition>

### Acceptance criteria

- <Checkable condition for the whole checkpoint: an input and its expected result, a command and
  its output. Names the spec item it proves.>

### Verification

- Tests to add or change: `<test path>`: <the cases>
- Full stack check passes (run by /dc:implement before it writes the notes entry).
- Manual check: <what the developer can try, or "None.">

## CP2: <title>

### Goal

<…>

### Tasks

- **T2: <short title>** (<size>). <…>
  - Files: `<path>`
  - Depends on: <T1>
  - Done when: <…>

### Acceptance criteria

- <…>

### Verification

- <…>
