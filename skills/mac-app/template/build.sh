#!/bin/zsh
# Builds __APP_NAME__ and installs it to ~/Applications/__APP_NAME__.app.
# Build products live in ~/Library/Developer/__APP_NAME__, outside the repo
# (and outside Dropbox or iCloud, which would try to sync them).
#
# Usage: ./build.sh            release build, install
#        ./build.sh --debug    debug build, install
#        ./build.sh --open     install, then quit the running copy and open the new one
set -euo pipefail
here=${0:A:h}
name="__APP_NAME__"
scratch="$HOME/Library/Developer/$name/build"
config=release
[[ " $* " == *" --debug "* ]] && config=debug

# Sign with your Apple Development certificate when you have one (Xcode >
# Settings > Accounts). Otherwise sign ad hoc, which is fine for your own Mac.
identity="${SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identities=$(security find-identity -v -p codesigning 2>/dev/null || true)
  # An Apple Development certificate, else any code signing certificate
  # (a self-signed one from Keychain Access works and needs no Xcode).
  identity=$(print -r -- "$identities" | grep -m1 -o '"Apple Development: [^"]*"' | tr -d '"' || true)
  [[ -n "$identity" ]] || identity=$(print -r -- "$identities" | grep -m1 -o '"[^"]*"' | tr -d '"' || true)
fi
[[ -n "$identity" ]] || identity=-

if ! output=$(swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1); then
  print -r -- "$output" | grep -E "error|warning" | grep -v "^\[" | head -40
  echo "build failed"
  exit 1
fi
print -r -- "$output" | grep -E "error|warning|Build complete" | grep -v "^\[" || true
bin="$scratch/$config/$name"
[[ -x "$bin" ]] || { echo "build failed"; exit 1; }
# swift build can report success while an edited file failed to compile. Catch that.
stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
if [[ -n "$stale" ]]; then
  # Only the modification time changed (a touch, a checkout): SwiftPM keeps the
  # binary as it is. Relink it once and check again.
  rm -f "$bin"
  if ! output=$(swift build -c $config --package-path "$here" --scratch-path "$scratch" 2>&1); then
    print -r -- "$output" | grep -E "error" | head -20
    echo "build failed"
    exit 1
  fi
  stale=$(find "$here/Sources" -name '*.swift' -newer "$bin" | head -1)
  [[ -x "$bin" && -z "$stale" ]] || { echo "build failed: binary is older than $stale"; exit 1; }
fi

app="$HOME/Applications/$name.app"
mkdir -p "$HOME/Applications"
# Replace only this app: another app with the same name stays.
bundle_id=$(plutil -extract CFBundleIdentifier raw "$here/Info.plist.in")
if [[ -e "$app" ]] && [[ "$(plutil -extract CFBundleIdentifier raw "$app/Contents/Info.plist" 2>/dev/null)" != "$bundle_id" ]]; then
  echo "$app is another app (not $bundle_id). Move it, or rename this one."
  exit 1
fi
# Assemble and sign beside it; the installed app is replaced only when that worked.
final=$app
app="$HOME/Applications/.$name-building.app"
rm -rf "${app:?}"
trap 'rm -rf "$HOME/Applications/.$name-building.app"' EXIT
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/$name"
sed -e "s/__BUILD__/$(date +%Y%m%d%H%M)/" "$here/Info.plist.in" > "$app/Contents/Info.plist"
# The icon: Icon/AppIcon.icon -> Resources/Assets.car + AppIcon.icns, rebuilt when it changed.
if [[ -d "$here/Icon/AppIcon.icon" ]]; then
  icns="$here/Resources/AppIcon.icns"
  # Also rebuild once Xcode's actool appears, to get the Liquid Glass Assets.car.
  if [[ ! -f "$icns" || -n "$(find "$here/Icon/AppIcon.icon" -newer "$icns" | head -1)" ]] ||
     { [[ ! -f "$here/Resources/Assets.car" ]] && xcrun --find actool >/dev/null 2>&1; }; then
    "$here/tools/make_icon.sh"
  fi
  # Assets.car (Liquid Glass) exists only when actool did the build.
  cp -X "$icns" "$app/Contents/Resources/"
  [[ -f "$here/Resources/Assets.car" ]] && cp -X "$here/Resources/Assets.car" "$app/Contents/Resources/"
fi
xattr -cr "$app"
if ! signed=$(codesign --force --sign "$identity" "$app" 2>&1); then
  print -r -- "$signed"
  echo "signing failed"
  exit 1
fi
print -r -- "$signed" | grep -v "replacing existing signature" || true
rm -rf "${final:?}"
mv "$app" "$final"
app=$final
echo "installed $app (signed: ${identity})"

if [[ " $* " == *" --open "* ]]; then
  osascript -e "quit app \"$name\"" 2>/dev/null || true
  # Wait for the old copy to exit, or open would bring it back to the front.
  for _ in {1..50}; do pgrep -xq "$name" || break; sleep 0.1; done
  open "$app"
fi
