<!-- Template for .tasks/<folder>/implementation-notes.md, filled by /dc:implement. The first run copies the title line, then one entry per checkpoint, appended in plan order. Replace every <placeholder> and delete these comments. Keep the section order inside an entry. Fixed markers (contracts §6.2), read by task-state.sh:
       - every entry is a level-2 heading "## CP<n>: <title>", the same heading as in plan.md;
       - an entry marks its checkpoint DONE, so it is written only after `stack-check.sh full` passes, never earlier;
       - inside an entry use only level-3 headings (###), so no other line starts with "## CP";
       - the markers stay in English, whatever language the rest is written in. -->

# Implementation notes: <short title, as in the plan>

<!-- One entry per checkpoint. Copy the block below for each new checkpoint, at the end of the file. -->

## CP1: <title, exactly as in plan.md>

### Changes

<What changed, by file, with paths. Tests included. One line per file.>

- `<path>`: <what changed>
- `<test path>`: <the cases added or changed>

### Decisions

<Small technical decisions taken while building, each with its reason. Lower-risk choices the plan left open. "None." if there were none.>

- <decision>. Because <reason>.

### Deviations from the plan

<What was built differently from plan.md, and the developer's answer that allowed it, as "(developer, during CP<n>)". "None." if the checkpoint followed the plan.>

None.

### Verification

- Acceptance criteria: <each criterion of the checkpoint, and how it was shown to hold>
- Full stack check: passed (`<the commands that ran>`)
- Manual check for the developer: <what to try, or "None.">

### Noticed, not touched

<Problems seen outside this checkpoint's scope and left alone. "None." if there were none.>

None.
