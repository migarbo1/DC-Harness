# Spikes (Phase 0)

Results of the Phase 0 spikes: what was tried, what happened, and what Phase 1 builds because of
it. How to run them is in `check-spikes.md`.

| # | Question | Result | Decision |
| --- | --- | --- | --- |
| S1 | Does `/clear` start a new session ID that `SessionStart` sees? | **Pass** | Fresh session = a `session_id` different from the one recorded at `/dc:plan` |
| S2 | Can a `PreToolUse` hook see when a skill is loaded? | **Partial** | Typed skills are seen in `UserPromptSubmit`, not `PreToolUse`. Command hooks must cover the PowerShell tool too. Git's `usr\bin` required on the Windows PATH |
| S3 | Does `UserPromptSubmit` receive exactly what the developer typed? | **Pass** | Approvals must be typed: trim, and reject pasted content. Paste case to repeat in the CLI |
| S4 | Do plugin hooks run in Git Bash when paths contain spaces? | **Pass** | Quote `${CLAUDE_PLUGIN_ROOT}` in every hook command |
| S5 | Install and update from Azure DevOps without a password prompt? | **Not run** | Waiting for the repo in Azure DevOps |
| S6 | Does `jq` on Windows handle line endings and non-English characters? | **Pass, with rules** | Strip `\r`; pass text with `--arg` or stdin, never through the environment |
| S7 | Do `/dc:` commands run, and does `${CLAUDE_PLUGIN_ROOT}` work with spaces? | **Pass** | Call scripts through `${CLAUDE_PLUGIN_ROOT}` as planned; `bin/` stays as fallback |
| S8 | Is `${CLAUDE_SESSION_ID}` replaced in SKILL.md text (contracts §2.5)? | **Pass** (CLI) | Skills pass it as an argument to `task-state.sh`; no `session-recorder.sh` in v0 |

## Test environment

- **Date:** 2026-11-19.
- **Machine:** Windows 11 (10.0.26200), Git Bash `MINGW64_NT-10.0-26200`, bash 5.2.37, git 2.49.0,
  jq 1.8.1 (Chocolatey), Claude Code CLI 2.1.328.
- **Client:** the payloads carry `scratchpad_dir` and fields such as `context_tokens`, and the
  transcripts are under `~/.claude/projects/`. That points to the Claude desktop app (Code tab)
  rather than the CLI with `CLAUDE_CONFIG_DIR`. **To confirm.**
- **Model:** `claude-opus-5-5`.
- **Spike plugin:** `_spikes/dc-spike/` (plugin name `dcspike`), loaded from a path with spaces
  (`C:\08 - AI Office\nunsys-harness\_spikes\dc-spike`).
- **Raw payloads:** `.spike-log/` (not committed). File names are quoted below as evidence.

## S1: `/clear` and the session ID

**What I did:** started a session, typed a prompt, then ran `/clear`, `/compact`, and quit and
resumed with `--resume`.

**Result:** pass.

| Action | `SessionStart.source` | `session_id` | Evidence |
| --- | --- | --- | --- |
| Start | `startup` | `198e5f67…` (A) | `101545-1286-SessionStart.json` |
| `/clear` | `clear` | `048e216b…` (B, new) | `102049-1399-SessionStart.json` |
| Prompt after `/clear` | (`UserPromptSubmit`) | `048e216b…` (B) | `102153-1408-UserPromptSubmit.json` |
| `/compact` | `compact` | `048e216b…` (B, unchanged) | `102230-1422-SessionStart.json` |
| `--resume` of the first session | `resume` | `198e5f67…` (A again) | `102308-1429-SessionStart.json` |

**Decision:**

- `/dc:plan` records the `session_id`. `/dc:implement` treats the session as fresh only if its
  `session_id` is different.
- `/compact` keeps the ID, so a compacted planning session is **not** fresh. This is intended:
  the summary still carries the planning context.
- Resuming the planning session brings back its ID, so it is **not** fresh either. Intended.
- **Known gap, accepted:** resuming a *different, older* session gives an ID that differs from the
  planning one, so it counts as fresh although it has old context. Accepted to keep the rule
  simple.
- `SessionStart.source` (`startup`, `clear`, `compact`, `resume`) is available and can be stored
  with the ID for clearer refusal messages.

## S2: can a hook see a skill being loaded?

**What I did:** typed `/dcspike:hello x` with `disable-model-invocation: true`. Then removed that
line, restarted, and asked "use the hello skill in dcspike".

**Result:** partial.

- **Typed skill:** no `Skill` tool call. The only trace is the prompt in `UserPromptSubmit`
  (`"/dcspike:hello x"`, `103041-1573-UserPromptSubmit.json`). The skill's command then ran as a
  normal tool call (`103044-1580-PreToolUse.json`).
- **Skill invoked by the model:** seen in `PreToolUse` as `"tool_name": "Skill"` with
  `"tool_input": {"skill": "dcspike:hello"}` (`103305-1614-PreToolUse.json`).
- **Every command ran through the `PowerShell` tool, not `Bash`.** All `PreToolUse` command calls
  in both sessions have `"tool_name": "PowerShell"`, including the skill's
  `bash "C:/08 - AI Office/.../hello.sh" "x"`. The `Bash` tool was never used.

**Decision:**

- All `/dc:` skills set `disable-model-invocation: true`, so the developer always types them. The
  order guard reads the typed command from `UserPromptSubmit` (`prompt` starts with `/dc:`), not
  from `PreToolUse`.
- Hooks that guard commands (for example `harness-guard.sh` blocking `git commit` or `git push`)
  must match **both** `Bash` and `PowerShell`. Matching only `Bash` would let a PowerShell command
  through unnoticed.
- **`bash` called from PowerShell must be Git's.** On this machine PowerShell resolves `bash` to
  `Git\usr\bin\bash.exe` first, then `C:\WINDOWS\system32\bash.exe` (WSL), then the WindowsApps
  copy. If WSL's comes first, it can't run `C:/…` paths and every skill fails.
  **Decision: the harness requires Git's `usr\bin` on the Windows PATH**, ahead of
  `C:\WINDOWS\system32`. The real requirement is that `bash` run from PowerShell resolves to Git's
  bash, so `doctor.sh` checks exactly that (from inside Git Bash, `usr\bin` is always on the PATH,
  so checking the PATH there proves nothing).

## S3: does `UserPromptSubmit` receive exactly what was typed?

**What I did:** typed an approval with accents, a two-line message, a slash command with an
argument, and pasted a long text.

**Result:** pass, in the desktop app.

| Typed | `prompt` received | Evidence |
| --- | --- | --- |
| `Apruebo el plan, sí señor` | identical | `101603-1293-UserPromptSubmit.json` |
| Two lines with `sí — señor` | identical, with `\n` between the lines and the em dash kept | `101712-1328-UserPromptSubmit.json` |
| `/dcspike:hello world` | identical | `101813-1349-UserPromptSubmit.json` |
| A long pasted text | the **full** text, preceded by `\n\n` and wrapped in `<pasted_content id="…">…</pasted_content>` | `101910-1378-UserPromptSubmit.json` |

**Decision:**

- Approval gates trim leading and trailing whitespace before comparing.
- A prompt whose approval text is inside `<pasted_content …>` is **not** accepted as an approval:
  approvals have to be typed.
- Assessment answers may be pasted. The hook removes the `<pasted_content …>` tags and keeps the
  text inside.
- **Caveat:** the `<pasted_content>` wrapper comes from the client. The CLI may pass pasted text
  without it, and then a pasted approval can't be told apart from a typed one. **To repeat the
  paste case in the CLI and in the clients the pilot developers use.**

## S4: hooks in Git Bash with spaces in the path

**What I did:** ran every spike with the plugin at `C:\08 - AI Office\...`, with hook commands
written as `bash \"${CLAUDE_PLUGIN_ROOT}/scripts/record.sh\" <event>`.

**Result:** pass. Every hook call wrote a line to `.spike-log/index.log` with
`shell=MINGW64_NT-10.0-26200` and `root=C:\08 - AI Office\nunsys-harness\_spikes\dc-spike`.

**Decision:** every command in `hooks/hooks.json` quotes `${CLAUDE_PLUGIN_ROOT}`. Not tried: the
unquoted variant, to show it breaks (optional).

## S5: install and update from Azure DevOps

**Not run.** The repo is not in Azure DevOps yet, and distribution is only needed at the end of
Phase 2. Fallback if it fails: manual update plus an "outdated" warning.

## S6: jq on Windows

**What I did:** ran the commands from `check-spikes.md`, then re-checked two results by reading
the bytes.

**Result:** pass, with rules for `lib/json.sh`.

| Test | Result |
| --- | --- |
| `jq -r` output | Ends in `\r\n`: every line read back from jq carries an extra `\r` |
| Input with CRLF | Read correctly |
| UTF-8 input (`sí, señor — ü`) | Kept as UTF-8 (`í` = `303 255`, `ñ` = `303 261`) |
| Accents in a real `UserPromptSubmit` payload | Read correctly |
| Input with a UTF-8 BOM | Accepted by jq 1.8.1 |
| `--arg` with `señor`, written to a file and read back | The file holds correct UTF-8, and the value read into a variable equals `señor`. The terminal showed `se├▒or` only because jq.exe printed straight to the console; captured output is correct |
| Files written by jq | Have CRLF line endings |
| Text passed through an environment variable (`T="señor" jq -rn 'env.T'`) | **Corrupted**: `se` followed by the replacement character `�` |

**Decision:**

- `lib/json.sh` strips `\r` from everything it reads back from jq.
- Text goes into jq with `--arg` or `--rawfile`, or through stdin. **Never through an environment
  variable** (`env.X`, `$ENV.X`).
- State files written by jq have CRLF endings. Anything that hashes or compares them must expect
  that, or the helper writes them with LF.
- BOM handling was tested with jq 1.8.1 only. `doctor.sh` allows jq 1.7: either test 1.7 or raise
  the minimum to 1.8.

## S7: namespaced commands and `${CLAUDE_PLUGIN_ROOT}` with spaces

**What I did:** typed `/dcspike:hello a b`, then `/hello a b`, then asked Claude to run
`dcspike-hello test`.

**Result:** pass.

- `/dcspike:hello a b`: `${CLAUDE_PLUGIN_ROOT}` was replaced with
  `C:/08 - AI Office/nunsys-harness/_spikes/dc-spike` (forward slashes, spaces kept), and the
  script received `a b`.
- `/hello a b`: the short form reached the same skill, because no other command had that name.
- `dcspike-hello test`: the `bin/` folder is on the PATH. Claude ran it as
  `bash -c 'command -v dcspike-hello; dcspike-hello test'` through the PowerShell tool.

**Decision:** skills call `bash "${CLAUDE_PLUGIN_ROOT}/scripts/task-state.sh" <skill>`, as planned.
`bin/` stays as the fallback. Docs always use the full `/dc:` form; the short form works only while
no other command has the same name.

## S8: `${CLAUDE_SESSION_ID}` in SKILL.md text

**What I did** (2026-11-20, Claude Code CLI 2.1.328, `claude-haiku-5-5`): added
`skills/session/SKILL.md` to the spike plugin. It prints `TEXT-SESSION=${CLAUDE_SESSION_ID}`, then
runs `bash "${CLAUDE_PLUGIN_ROOT}/scripts/session.sh" "${CLAUDE_SESSION_ID}"`, the same form as the
`task-state.sh` call. Ran it once with
`claude -p "/dcspike:session" --plugin-dir ./_spikes/dc-spike --output-format json`.

**Result:** pass, in the CLI.

| Where | Session ID seen | Evidence |
| --- | --- | --- |
| Skill text (`TEXT-SESSION=`) | `3cff0dac-…-44393373b425` | CLI JSON `result` |
| Script argument | the same ID, as one argument | `.spike-log/index.log` (`session.sh arg=[…]`) |
| `UserPromptSubmit` and `PreToolUse` payloads | the same ID in `session_id` | `125424-47930-UserPromptSubmit.json`, `125426-47937-PreToolUse.json` |
| `CLAUDE_SESSION_ID` environment variable in the script | **not set** | `ENV-CLAUDE_SESSION_ID=[<unset>]` |

The command again ran through the `PowerShell` tool, as in S2.

**Decision:**

- Skills pass `"${CLAUDE_SESSION_ID}"` as an argument, as contracts §4.1 planned. Scripts must not
  read it from the environment: it isn't set there.
- The ID in the skill equals the hooks' `session_id`, so `planSession` (written by `task-state.sh`)
  and the approvals' `session` (written by `approval-capture.sh`) are the same kind of value.
- `session-recorder.sh` is not needed in v0.
- Not checked here: that the ID changes after `/clear` inside a skill. S1 already showed that
  `/clear` gives a new `session_id`, and the substitution is done per skill run.

## Still to do

- [ ] **S8:** repeat `/dcspike:session` in the desktop app (Code tab).
- [ ] **S5:** run once the repo is in Azure DevOps.
- [ ] **S3:** repeat the paste case in the CLI and in the pilot developers' clients.
- [X] **S2:** add a `doctor.sh` check that `bash` run from PowerShell is Git's, and document the
      PATH requirement in `docs/onboarding.md`.
- [ ] **S6:** test BOM input with jq 1.7, or raise the minimum to 1.8.
- [ ] **Client:** confirm which client the payloads were recorded in.
- [ ] **Fixtures:** copy the payloads quoted above into `tests/fixtures/hooks/`. Replace the user
      name in `transcript_path`, `cwd` and `scratchpad_dir` first: `tests/` is committed.
