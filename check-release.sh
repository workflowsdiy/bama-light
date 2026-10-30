#!/bin/zsh
# Compare the working tree with the commit distributed in the previous release.
set -euo pipefail
cd "${0:A:h}"
base=${1:?usage: check-release.sh <previous-release-commit>}
git rev-parse --verify "$base^{commit}" >/dev/null
if git diff --quiet "$base" -- skills; then
  echo "PASS release: no shipped skill changes"
  exit 0
fi
python3 -I -c '
import json, re, subprocess, sys
base = json.loads(subprocess.check_output(["git", "show", sys.argv[1] + ":.claude-plugin/plugin.json"]))["version"]
with open(".claude-plugin/plugin.json") as f:
    current = json.load(f)["version"]
def version(value):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value):
        sys.exit("FAIL release: expected a numeric major.minor.patch version")
    return tuple(map(int, value.split(".")))
if version(current) <= version(base):
    sys.exit("FAIL release: shipped skill changes need a version newer than " + base)
print("PASS release: " + base + " -> " + current)
' "$base"
