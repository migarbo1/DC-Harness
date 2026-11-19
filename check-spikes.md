# Running the spikes (S1–S7)

How to run the Phase 0 spikes. Each spike answers one open question before Phase 1 code depends
on it. Results go into `docs/spikes.md`.

Order: **S3 → S1 → S4 → S6 → S7 → S2 → S5**. S3 and S1 come first because the gates depend on
them; S4 and S6 next because every script on Windows depends on them; S2 and S5 last.

All spikes use **one throwaway "spike plugin"** that saves every hook payload to a file. Set it up
once; after that each spike is a few minutes of typing in Claude Code and reading the saved files.

## 0. Setup (once)

**Prerequisite: the Claude Code CLI in Git Bash.** `--plugin-dir` (load a plugin without
installing it) and the S5 commands are CLI-only. Check with `claude --version`.

**The spike plugin** lives at `_spikes/dc-spike/` in this repo. It is outside `plugins/`, so it never
ships. The repo path (`C:/08 - AI Office/...`) has spaces, which is exactly what S4 and S7 need.

```text
_spikes/dc-spike/
  .claude-plugin/plugin.json
  hooks/hooks.json
  scripts/record.sh
  scripts/hello.sh
  skills/hello/SKILL.md
  bin/dcspike-hello
```

`.claude-plugin/plugin.json`:

```json
{ "name": "dcspike", "version": "0.0.1", "description": "Phase 0 spikes", "author": { "name": "Nunsys" } }
```

`hooks/hooks.json` records four events. `PreToolUse` matches every tool, which S2 needs:

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/record.sh\" SessionStart" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/record.sh\" UserPromptSubmit" }] }],
    "PreToolUse":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/record.sh\" PreToolUse" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "bash \"${CLAUDE_PLUGIN_ROOT}/scripts/record.sh\" Stop" }] }]
  }
}
```

`scripts/record.sh` saves each payload, plus one line per call in an index:

```bash
#!/usr/bin/env bash
# record.sh EVENT: saves the hook's JSON input to .spike-log/ in the project.
event=$1
dir="${CLAUDE_PROJECT_DIR:-$PWD}/.spike-log"
mkdir -p "$dir"
file="$dir/$(date +%H%M%S)-$$-$event.json"
cat > "$file"
echo "$(date +%T) $event shell=$(uname -s) root=$CLAUDE_PLUGIN_ROOT file=$(basename "$file")" >> "$dir/index.log"
exit 0
```

`skills/hello/SKILL.md` (used by S7 and S2):

```markdown
---
name: hello
description: Spike S7
disable-model-invocation: true
---
Run exactly this command and show its output:

bash "${CLAUDE_PLUGIN_ROOT}/scripts/hello.sh" "$ARGUMENTS"
```

`scripts/hello.sh`:

```bash
#!/usr/bin/env bash
echo "hello.sh ran from: $0"
echo "arguments: $*"
```

`bin/dcspike-hello` is the S7 fallback. It has the same two lines as `hello.sh`, no file
extension, and must be executable (`chmod +x`).

Add `.spike-log/` to `.gitignore`.

**Start every spike session** from the repo root with:

```powershell
claude --plugin-dir "./_spikes/dc-spike"
```

Hooks are read when a session starts, so restart Claude Code after editing `hooks.json` or a
SKILL.md.

### Recording results

Each spike gets an entry in `docs/spikes.md` with:

- **Question**: the spike's question.
- **What I did**: the steps, briefly.
- **Result**: pass or fail, with the payload file as evidence.
- **Decision**: what Phase 1 builds, or which fallback was chosen.
- **Claude Code version**: from `claude --version`.

Copy the payloads you'll need later into `tests/fixtures/hooks/`. Phase 1's bats tests feed them to
the real hooks.

## S3: does `UserPromptSubmit` receive exactly what the developer typed?

The approval gates and the assessment answers depend on this.

1. Type these prompts, one at a time:
   - `apruebo el plan, sí — señor` (accents, `ñ` and an em dash)
   - a message of two lines (Shift+Enter between them)
   - `/dcspike:hello world` (a slash command with an argument)
   - a long text pasted in, which the UI shows as `[Pasted text #1]`
2. Look at each saved prompt:

   ```bash
   jq -r .prompt .spike-log/*-UserPromptSubmit.json
   ```

3. **Pass if** each `prompt` is byte-for-byte what you typed: accents, the newline, the text
   `/dcspike:hello world`, and the **full** pasted text rather than the placeholder.
4. Record which of the four cases differ. The paste case and the slash command case are the most
   likely to surprise.

## S1: does `/clear` start a new session ID that the `SessionStart` hook sees?

The fresh-session rule depends on this.

1. Start a session and type anything. The first `SessionStart` file should have
   `"source": "startup"` and a `session_id` (call it A).
2. Type `/clear`. Expected: a new `SessionStart` file with `"source": "clear"` and a different
   ID (B).
3. Type another prompt and check that its `UserPromptSubmit` payload carries B.
4. For completeness, also try:
   - `/compact`: expected `source: "compact"`; note whether the ID stays the same or changes.
   - Quitting and running `claude --resume`: note what a resumed session reports.
5. **Pass if** `/clear` gives a new ID visible from both events. Write down what `compact` and
   `resume` do: the fresh-session rule has to decide whether those count as "fresh".

**Fallback if it fails:** `/dc:plan` writes a random token; a session started by `/clear`
invalidates it, so `/dc:implement` knows a `/clear` happened.

## S4: do plugin hooks run in Git Bash when paths contain spaces?

1. If `.spike-log/index.log` has lines after S3 and S1, the hooks ran. Check that each line shows
   `shell=MINGW…` and a `root=` with the spaces intact.
2. To prove the quoting matters, remove the `\"` quotes around the variable in one command in
   `hooks.json`, restart, and confirm that hook stops writing. Then put the quotes back.
3. Record the quoted form (`bash \"${CLAUDE_PLUGIN_ROOT}/...\"`) as the rule for
   `hooks/hooks.json` in Phase 1.

**Fallback if it fails:** quoting in the adapter and a documented install path.

## S6: does `jq` on Windows handle Windows line endings and non-English characters?

Run these in Git Bash. `od -c` shows any `\r` in the output.

```bash
printf '{"a":"b"}' | jq -r .a | od -c                          # extra \r at the end of the output?
printf '{"a":"b"}\r\n' | jq -r .a                               # input with CRLF
printf '{"t":"sí, señor — ü"}' | jq -r .t | od -c               # UTF-8 kept as UTF-8?
jq -r .prompt .spike-log/*-UserPromptSubmit.json | head -1      # the real S3 payload with accents
printf '\xef\xbb\xbf{"a":1}' | jq .a                            # a UTF-8 file with BOM (PowerShell writes these)
jq -n --arg t "señor" '{t:$t}' > s6.json && jq -r .t s6.json    # write, then read back
```

- Expected: jq on Windows adds `\r` to its output.
- Decide whether the `lib/json.sh` helper always strips `\r`, and whether it rejects or strips a
  BOM.

**Fallback if it fails:** strip the extra line-ending character in the JSON helper.

## S7: do the `/dc:` commands work, and does `${CLAUDE_PLUGIN_ROOT}` resolve to a path with spaces?

Every skill starts by calling `task-state.sh`, so this has to work.

1. Type `/dcspike:hello a b`. **Pass if** the output shows the full path with spaces and the
   arguments `a b`.
2. Type `/hello a b`. Note whether the short form also reaches the skill.
3. Ask Claude to run `dcspike-hello test`. This checks the `bin/` fallback is on the Bash tool's
   `PATH`.

**Fallback if it fails:** ship `task-state.sh` in the plugin's `bin/` folder and call it by name.

## S2: can a `PreToolUse` hook see when a skill is loaded?

The order guard (v1) depends on this.

1. Type `/dcspike:hello x`, then check whether any `PreToolUse` file has `"tool_name": "Skill"`:

   ```bash
   grep -l '"tool_name": *"Skill"' .spike-log/*-PreToolUse.json
   ```

2. Remove `disable-model-invocation` from `skills/hello/SKILL.md`, restart, ask *"use the hello
   skill"*, and check again.
3. What to expect:
   - A **model**-invoked skill shows up as a `Skill` tool call.
   - A **typed** slash command doesn't; it only appears as the `UserPromptSubmit` prompt from S3.

   Since every `/dc:` skill is typed by the developer, the order guard can probably be built on
   `UserPromptSubmit` and doesn't need `PreToolUse`. Check this against what you actually see.

**Fallback if it fails:** skill precondition checks only.

## S5: can the plugin be installed and updated from Azure DevOps without a password prompt?

This needs the repo in Azure DevOps (`origin` is currently GitHub).

1. Push the harness repo to an Azure DevOps repo.
2. Register it and install:

   ```powershell
   claude plugin marketplace add https://dev.azure.com/<org>/<project>/_git/<repo>
   ```

   ```powershell
   claude plugin install dc@<marketplace-name>
   ```

3. Simulate an update: raise the version in `plugin.json`, push, run
   `claude plugin marketplace update`, and check that the new version arrives.
4. Repeat with `GIT_TERMINAL_PROMPT=0` set. This behaves like a background auto-update that can't
   show a prompt. **Pass if** Git Credential Manager signs in without one.
5. Also test the team route: a project `.claude/settings.json` with `extraKnownMarketplaces` and
   `enabledPlugins`, opened on a second machine or user account.

**Fallback if it fails:** manual update plus an "outdated" warning.

## Done

The spikes are done when all seven entries in `docs/spikes.md` have a result and a decision. Then
delete `_spikes/` (or keep it out of releases) and keep only the fixtures in `tests/fixtures/hooks/`.
