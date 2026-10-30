#!/bin/zsh
# Adds the agent CLI and MCP server to an app made from the mac-app template.
# Usage: add-agent-cli.sh <app-folder> <cli-name>
#   add-agent-cli.sh ~/Developer/Tasks tasks
# Copies Sources/<App>/Agent/*.swift and Sources/<App>/Main.swift, moves @main
# from App.swift to Main.swift, and makes build.sh link ~/.local/bin/<cli-name>.
# The example commands in Agent/AgentCommands.swift fit the template's Item
# model. Replace them with the app's own (agent-cli skill, step 3).
set -euo pipefail
app_dir=${1:?usage: add-agent-cli.sh <app-folder> <cli-name>}
cli=${2:?usage: add-agent-cli.sh <app-folder> <cli-name>}
[[ "$cli" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "cli-name must be lowercase letters, digits, and dashes, like tasks or mail"; exit 1; }
here=${0:A:h}
template=${here:h}/template
name=$(basename "$(dirname "$(find "$app_dir/Sources" -mindepth 2 -maxdepth 2 -name App.swift | head -1)")")
src="$app_dir/Sources/$name"
[[ -f "$src/App.swift" ]] || { echo "no $src/App.swift: is this an app from the mac-app template?"; exit 1; }
[[ ! -e "$src/Agent" ]] || { echo "$src/Agent already exists"; exit 1; }
[[ ! -e "$src/Main.swift" ]] || { echo "$src/Main.swift already exists"; exit 1; }
# The name must not hide another command or replace a file that is not ours.
link="$HOME/.local/bin/$cli"
if [[ -e "$link" || -L "$link" ]] && [[ "$(readlink "$link")" != "$HOME/Applications/$name.app/Contents/MacOS/$name" ]]; then
  echo "$link already exists and is not $name's CLI link. Pick another cli-name."; exit 1
fi
other=$(path=(${path:#$HOME/.local/bin}); whence -p "$cli" || true)
[[ -z "$other" ]] || { echo "\`$cli\` is already a command ($other). Pick another cli-name."; exit 1; }

mkdir -p "$src/Agent"
license=${here:h:h:h}/LICENSE
[[ -f "$app_dir/LICENSE-bama-light" || ! -f "$license" ]] || cp "$license" "$app_dir/LICENSE-bama-light"
for f in "$template"/Agent/*.swift; do
  sed -e "s/__APP_NAME__/$name/g" -e "s/__CLI_NAME__/$cli/g" "$f" > "$src/Agent/${f:t}"
done
sed -e "s/__APP_NAME__/$name/g" "$template/Main.swift" > "$src/Main.swift"

# Main.swift has @main now: it starts the CLI or the app.
perl -0pi -e "s/\@main\s*\n(struct ${name}App\s*:\s*App)/\$1/" "$src/App.swift"
grep -q "^@main" "$src/App.swift" && { echo "could not remove @main from App.swift: remove it by hand"; exit 1; }

# Start the socket first in the main view's .task block, where the template
# starts seed data, the self-test, and snapshot mode.
if ! grep -q "AgentSocket.listen" "$src/ContentView.swift" && grep -qE '^\s*\.task \{$' "$src/ContentView.swift"; then
  perl -0pi -e 's/^(\s*)\.task \{\n/$1.task {\n$1    AgentRouter.model = model\n$1    AgentSocket.listen { AgentRouter.handle(\$0) }\n/m' "$src/ContentView.swift"
  grep -q "AgentSocket.listen" "$src/ContentView.swift" && started=1
fi

# build.sh puts the CLI on PATH.
if ! grep -q "local/bin/$cli" "$app_dir/build.sh"; then
  hook=$(printf '%s\n' \
    '# The CLI link is created only when absent; an existing command stays.' \
    'mkdir -p "$HOME/.local/bin"' \
    "link=\"\$HOME/.local/bin/$cli\"" \
    'target="$app/Contents/MacOS/$name"' \
    'if [[ -e "$link" || -L "$link" ]]; then' \
    '  [[ -L "$link" && "$(readlink "$link")" == "$target" ]] || { echo "$link belongs to another command; leaving it unchanged."; exit 1; }' \
    'else' \
    '  ln -s "$target" "$link"' \
    'fi')
  CLI_BUILD_HOOK="$hook" perl -0pi -e 's/^(echo "installed \$app[^\n]*\n)/$ENV{CLI_BUILD_HOOK}\n$1/m' "$app_dir/build.sh"
  grep -q "local/bin/$cli" "$app_dir/build.sh" || echo "note: add the ~/.local/bin/$cli link to build.sh by hand"
fi

echo "added the agent CLI to $name as \`$cli\`. Next (agent-cli skill):"
echo "  3. replace the example commands in $src/Agent/AgentCommands.swift"
[[ -n "${started:-}" ]] || echo "  4. start the socket in the main view's .task: AgentRouter.model = model; AgentSocket.listen { AgentRouter.handle(\$0) }"
echo "  5. ./build.sh, then $cli help"
[[ ":$PATH:" == *":$HOME/.local/bin:"* ]] || echo "note: ~/.local/bin is not on PATH. Add it (echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zprofile), or run ~/.local/bin/$cli"
