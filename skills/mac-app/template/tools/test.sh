#!/bin/zsh
# Runs the Kit unit tests. Without Xcode, Swift Testing lives in the Command
# Line Tools' framework folder, which swift test does not search on its own.
set -euo pipefail
repo=${0:A:h:h}
args=(--package-path "$repo" --scratch-path ~/Library/Developer/__APP_NAME__/test-build)
if [[ $(xcode-select -p) == /Library/Developer/CommandLineTools ]]; then
  frameworks=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  libs=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  args+=(-Xswiftc -F -Xswiftc $frameworks -Xlinker -F -Xlinker $frameworks
         -Xlinker -rpath -Xlinker $frameworks -Xlinker -rpath -Xlinker $libs)
fi
swift test "${args[@]}" "$@"
