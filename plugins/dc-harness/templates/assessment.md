<!-- Template for .tasks/<folder>/assessment.md, filled by /dc:assessment. Replace every <placeholder> and delete these comments. Keep the section order.
     Written in two passes (contracts §6.4):
       - during the assessment: the header, Sources, and for each question asked so far its question, its exchange and its result. No expected answers yet: they stay in .assessment-key.md;
       - at the end: each question's "Expected answer" copied from .assessment-key.md, then the final Result section with the score line.
     Fixed marker (contracts §6.3), read by task-state.sh and copied by /dc:pr-text:
       - one line "Score: <passed>/<total> (passed)" or "Score: <passed>/<total> (not passed)", written only when the assessment ends. It marks the assessment FINISHED, so it never appears earlier;
       - the developer's answers are always quoted with "> ", so no answer line can be read as the score line;
       - the marker stays in English, whatever language the rest is written in. -->

# Assessment: <short title, as in the spec>

Branch: `<branch>` · Commit-ref: `<first 10 characters of commit-ref>` · Date: <YYYY-MM-DD>
Questions: <questions> · Pass threshold: <pass-threshold> · Retries per question: <max-retries>

## Sources

- Diff: `git diff <commit-ref>`: <n> files changed; untracked: <m> files (<paths, or "none">)
- Notes: `implementation-notes.md` (<CP1–CP<n>>)

<!-- One block per question, in the order asked. Copy the block below for each question. -->

## Q1: <the question, as asked>

Asks about: `<path>` (<the change or decision it is about>) · Type: <why | what breaks | edge case | data flow | test | alternative>

### Exchange

<!-- Every prompt the developer typed while this question was open, word for word from approvals.json ("assessment" entries, in order), each followed by the grade or by the agent's follow-up. Multi-line answers keep their lines, each prefixed with "> ". -->

**Answer 1:**

> <the developer's text, word for word>

Grade: <correct | partial | wrong | not sure>

**Retry 1** (<wrong: rephrase, hint and a related question | not sure: explanation and a related question | partial: a follow-up on the missing part>):

<the agent's follow-up, as asked>

**Answer 2:**

> <the developer's text, word for word>

Grade: <correct | partial | wrong | not sure>

### Expected answer

<!-- Copied from .assessment-key.md at the end, not before. -->

<the expected answer, and the reasoning ("the why") an answer had to show>

### Result

<Passed | Not passed>: <one line: what the developer showed, or what was missing>

## Result

Score: <passed>/<total> (<passed or not passed>)

<One or two lines: what the developer clearly understands, and the one gap worth a second look before review, or "No gaps found.">
