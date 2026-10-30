---
name: agent-cli
description: Gives a macOS app a command line and an MCP server that drive the running app, so agents can list, add, change, and search its data. Use when the user wants agents or scripts to work with their app, asks for a CLI, MCP server, or automation for an app, or says "Claude should be able to use my app".
argument-hint: "<cli-name, like tasks or mail>"
---

# Agent CLI

The app binary is the CLI. `tasks items add --title "Call the dentist"` sends the
command over a private socket to the running app. The app runs it like a button
press, saves, and redraws the window. Agents and people use the same commands.

```text
Terminal or agent --> tasks items add ... --socket--> App (runs the command, saves, redraws)
MCP client        --> tasks mcp           --socket--> same commands, same app
```

## When to add it

Add it when an agent should do what a person does in the window. Skip it for an
app that only shows data, or one whose data an agent never needs.

Use the CLI for agents with a shell. Add the MCP server only for clients with no
shell, such as Claude Desktop. The MCP server is a thin layer over the same commands.

## Steps

1. List the commands. Turn each thing a person does into `<noun> <verb>`, and mark it
   `read`, `write`, or `destructive`. Add `status` and `open <page>` so an agent can
   see and steer the app.
2. Run `scripts/add-agent-cli.sh <app-folder> <cli-name>` from this skill's folder.
   It copies `Agent/` and `Main.swift` into the app, moves `@main` to `Main.swift`,
   starts the socket from the main view's `.task`, and links `~/.local/bin/<cli-name>`
   in `build.sh`. It refuses a name that another command already uses.
3. Replace the example commands in `Sources/<App>/Agent/AgentCommands.swift`. Each
   command calls the same model code as the window's buttons. Never copy the logic.
4. Run `./build.sh`, then `<cli-name> help` (add `~/.local/bin` to `PATH` first).
5. Run this skill's `scripts/check-agent-cli.sh <cli-name>`. It starts a test copy
   on a `/tmp` database and must print `PASS agent CLI`.
   If the test copy crashes, macOS shows a crash alert that takes focus; fix the crash,
   don't rerun it while someone is working.

## Command contract

- Names are `<noun> <verb>`: `items list`, `items add`, `items update`, `items delete`.
  Use the same verbs everywhere. App-wide commands are one word: `status`, `open`.
- `--json` prints exactly one JSON object on stdout. Without it, short plain lines.
  Notes and progress go to stderr.
- Exit codes: 0 ok, 1 error, 2 usage, 3 not found, 4 app not running.
- With `--json`, an error is `{"ok":false,"error":{"code":"...","message":"..."}}`.
  Each message says what to do next, for example "no item with id 3f2a. Run `tasks items list`".
- Read commands mark `readOnly`. Write commands change data.
- Commands requiring confirmation (delete, send, empty) mark `requiresConfirmation` and change nothing without `--yes`. They
  return what they would do and the hint "add --yes".
- Commands replacing or removing data mark `destructive`; ordinary edits need no confirmation.
- Ids are full UUIDs; `shortId` is for display. Any unique prefix works.
- Lists take `--limit` and `--offset`, and return `total` and, when more exist, `nextOffset`.
- Every option has a flag. No command asks a question, because an agent cannot answer one.
- `help` lists every command. `help <command>` shows its options and an example.
  `help --json` returns every command as a schema.
- The app is not running? The CLI opens it in the background and waits up to 10
  seconds. `--no-launch` fails with exit 4 instead.

## What not to build

- **Direct database access.** Two processes writing one store skip the app's checks,
  and the window does not see the change.
- **An XPC service.** Command-line tools cannot use one without a launch agent.
- **AppleScript or URL schemes as the main channel.** URL schemes return no result,
  and Apple Events trigger permission prompts. Keep URL schemes for links.
- **An MCP server without the CLI.** Agents with a shell do better with the CLI.

## Teach agents to use it

Agents learn a CLI from three places: a short skill file, `<cli> help`, and the
error messages. Write the skill file, and keep the rest in `help`.

- Write a skill file for the CLI, for example `~/.claude/skills/<cli>/SKILL.md` for
  Claude Code or `~/.codex/skills/<cli>/SKILL.md` for Codex. Keep it short. Say what
  the app is, the safety rule (show the `--yes` report, then ask), the five most used
  commands, and "run `<cli> help` for the rest". Use `--json` in examples.
- Add read-only commands to the agent's allow list, and leave write and destructive
  commands out, so the user approves each one.
- Register the MCP server with the full path to the app binary. MCP clients do not read `PATH`.

Claude Code:

```bash
claude mcp add --scope user <cli> -- ~/Applications/<App>.app/Contents/MacOS/<App> mcp
claude mcp list
```

Codex:

```bash
codex mcp add <cli> -- ~/Applications/<App>.app/Contents/MacOS/<App> mcp
```

Claude Desktop: add this to `~/Library/Application Support/Claude/claude_desktop_config.json`,
with the full path, then restart Claude Desktop:

```json
{ "mcpServers": { "<cli>": { "command": "/Users/<you>/Applications/<App>.app/Contents/MacOS/<App>", "args": ["mcp"] } } }
```

Tools take the command name with `_` for spaces (`items_add`). Each carries
`readOnlyHint` and `destructiveHint`.
