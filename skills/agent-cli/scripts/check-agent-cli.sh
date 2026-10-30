#!/bin/zsh
# Checks an app's agent CLI against the agent-cli rules, on a test database.
# Usage: check-agent-cli.sh <cli>        the CLI name or a path to the app binary
#   check-agent-cli.sh tasks
#   check-agent-cli.sh ~/Applications/Tasks.app/Contents/MacOS/Tasks
# Starts a test copy of the app (APP_STORE in /tmp), never the real one, and
# quits it at the end. Prints PASS or FAIL lines, and exits 1 on any FAIL.
set -uo pipefail
cli=${1:?usage: check-agent-cli.sh <cli>}
export APP_STORE="/tmp/agent-cli-check-$$.store"
export APP_AGENT_SOCKET="$APP_STORE.sock"
fails=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; fails=$((fails + 1)); }

out=$("$cli" help 2>&1); [[ $? == 0 && -n "$out" ]] && pass "help" || fail "help exits 0 and prints the commands"

schema=$("$cli" help --json 2>/dev/null)
python3 -I -c '
import json, sys
s = json.loads(sys.argv[1])
cmds = s["commands"]
assert cmds, "no commands"
for c in cmds:
    assert c["description"] and "Example:" in c["description"], c["name"] + ": summary and example"
    assert c["inputSchema"]["type"] == "object", c["name"]
' "$schema" 2>/dev/null && pass "help --json: every command has a summary, an example, and a schema" || fail "help --json lists every command with a summary, example, and schema"

"$cli" no-such-command >/dev/null 2>&1; [[ $? == 2 ]] && pass "unknown command exits 2" || fail "unknown command exits 2"
err=$("$cli" no-such-command --json 2>/dev/null)
python3 -I -c 'import json,sys; e=json.loads(sys.argv[1])["error"]; assert e["code"] and e["message"]' "$err" 2>/dev/null \
  && pass "errors with --json are {\"error\":{code,message}} on stdout" || fail "errors with --json are {\"error\":{code,message}} on stdout"

# Every read-only command without required params runs and prints JSON.
for name in ${(f)"$(python3 -I -c '
import json, sys
for c in json.loads(sys.argv[1])["commands"]:
    if c["inputSchema"].get("required") == [] and c.get("readOnly"):
        print(c["name"])
' "$schema" 2>/dev/null)"}; do
  res=$("$cli" ${=name} --json 2>/dev/null); code=$?
  python3 -I -c 'import json,sys; json.loads(sys.argv[1])' "$res" 2>/dev/null && [[ $code == 0 ]] \
    && pass "$name --json" || fail "$name --json exits 0 with one JSON object (got exit $code)"
done

mcp=$(printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"check","version":"1"}}}' \
  '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | "$cli" mcp 2>/dev/null)
python3 -I -c '
import json, re, sys
lines = [json.loads(l) for l in sys.argv[1].splitlines() if l.strip()]
assert lines[0]["result"]["capabilities"]["tools"] is not None
tools = lines[1]["result"]["tools"]
assert len(tools) == len(json.loads(sys.argv[2])["commands"])
for t in tools:
    assert re.fullmatch(r"[A-Za-z0-9_-]{1,64}", t["name"]), t["name"]
    assert "readOnlyHint" in t["annotations"]
' "$mcp" "$schema" 2>/dev/null && pass "mcp: initialize and tools/list, one tool per command" || fail "mcp answers initialize and tools/list with one tool per command"

# A write round trip: add, show, delete with --yes, for the app's own noun (the commands
# ending in " add", " show" and " delete"). Every required param of add gets a test value.
# The test copy must keep the same pid, so a crash (which the CLI hides by relaunching
# the app) still fails the check.
pid_before=$(lsof -t "$APP_AGENT_SOCKET" 2>/dev/null | head -1)
python3 -I -c '
import json, subprocess, sys
cli = sys.argv[1]
cmds = {c["name"]: c for c in json.loads(sys.argv[2])["commands"]}

def command(name, args, code=0):
    words = ["--%s=%s" % (key, str(value).lower() if isinstance(value, bool) else value) for key, value in args.items()]
    result = subprocess.run([cli, *name.split(), *words, "--json"], capture_output=True, text=True, timeout=30)
    assert result.returncode == code, (name, result.returncode, result.stdout, result.stderr)
    return json.loads(result.stdout)

def rpc(messages):
    initialize = {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2999-01-01", "capabilities": {}, "clientInfo": {"name": "check", "version": "1"}}}
    lines = [json.dumps(initialize), json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"})]
    lines += [m if isinstance(m, str) else json.dumps(m) for m in messages]
    result = subprocess.run([cli, "mcp"], input="\n".join(lines) + "\n", capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    replies = [json.loads(line) for line in result.stdout.splitlines()]
    assert len(replies) == len(messages) + 1, replies
    assert replies[0]["result"]["protocolVersion"] == "2025-06-18", replies[0]
    return replies[1:]

def call_message(name, args, ident=2):
    return {"jsonrpc": "2.0", "id": ident, "method": "tools/call", "params": {"name": name.replace(" ", "_"), "arguments": args}}

def tool(name, args):
    reply = rpc([call_message(name, args)])[0]
    result = reply["result"]
    assert result.get("isError") is False, reply
    return json.loads(result["content"][0]["text"])

def same_item(item, ident, values):
    assert item["id"] == ident, item
    for key, value in values.items():
        assert item[key] == value, (key, value, item)

try:
    nouns = [n[:-4] for n in cmds if n.endswith(" add") and n[:-4] + " show" in cmds and n[:-4] + " delete" in cmds]
    assert nouns, "need <noun> add, show and delete commands"
    noun = nouns[0]
    add, show, delete = (noun + " " + action for action in ["add", "show", "delete"])
    add_schema = cmds[add]["inputSchema"]
    key = lambda name: (cmds[name]["inputSchema"].get("required") or ["id"])[0]
    values = {}
    for name, prop in add_schema["properties"].items():
        if name not in add_schema.get("required", []) and name not in ("notes", "starred"):
            continue
        values[name] = prop.get("enum", [True if prop["type"] == "boolean" else 1 if prop["type"] in ("integer", "number") else "Check round trip"])[0]

    for source in ["CLI", "MCP"]:
        added = command(add, values) if source == "CLI" else tool(add, values)
        ident = added["id"]
        assert isinstance(ident, str) and ident, added
        same_item(added, ident, values)
        same_item(command(show, {key(show): ident}), ident, values)
        if source == "MCP":
            same_item(tool(show, {key(show): ident}), ident, values)
        print("PASS " + source + ": created values survive independent lookup")
        delete_args = {key(delete): ident}
        preview = command(delete, delete_args) if source == "CLI" else tool(delete, delete_args)
        assert preview["deleted"] is False, preview
        same_item(preview["wouldDelete"], ident, values)
        same_item(command(show, {key(show): ident}), ident, values)
        print("PASS " + source + ": deletion preview leaves the item unchanged")
        confirmed = dict(delete_args, yes=True)
        deleted = command(delete, confirmed) if source == "CLI" else tool(delete, confirmed)
        assert deleted["deleted"] is True and deleted["item"]["id"] == ident, deleted
        missing = command(show, {key(show): ident}, code=3)
        assert missing["error"]["code"] == "not_found", missing
        print("PASS " + source + ": confirmed deletion makes lookup return not_found")

    invalid = dict(values)
    invalid[next(iter(add_schema["properties"]), "unknown_argument")] = {}
    replies = rpc([
        "{",
        {"jsonrpc": "1.0", "id": 3, "method": "ping"},
        call_message("no such tool", {}, 4),
        call_message(add, invalid, 5),
        call_message(delete, dict(delete_args, yes="true"), 6),
        call_message(add, dict(values, unknown_argument=True), 7),
        call_message(show, {key(show): ident}, 8),
    ])
    assert [r["error"]["code"] for r in replies[:6]] == [-32700, -32600, -32602, -32602, -32602, -32602], replies
    assert replies[6]["result"]["isError"] is True, replies[6]
    error = json.loads(replies[6]["result"]["content"][0]["text"])
    assert error.get("error", error)["code"] == "not_found", error
    print("PASS mcp: version negotiation, malformed requests, typed arguments and execution errors")
except Exception as error:
    print("FAIL round trip: " + str(error), file=sys.stderr)
    sys.exit(1)
' "$cli" "$schema" && pass "CLI and MCP write round trips" || fail "CLI and MCP write round trips"
sleep 1
pid_after=$(lsof -t "$APP_AGENT_SOCKET" 2>/dev/null | head -1)
[[ -n "$pid_before" && "$pid_after" == "$pid_before" ]] && kill -0 "$pid_after" 2>/dev/null \
  && pass "test copy survives the round trips (same pid, alive)" || fail "test copy survives the round trips (pid $pid_before -> ${pid_after:-none})"

# Quit the test copy only: the process that owns the test socket.
[[ -n "$pid_after" ]] && kill "$pid_after" 2>/dev/null
rm -f -- "$APP_STORE" "$APP_STORE-shm" "$APP_STORE-wal" "$APP_AGENT_SOCKET"

[[ $fails == 0 ]] && { echo "PASS agent CLI"; exit 0; }
echo "FAIL agent CLI: $fails checks"; exit 1
