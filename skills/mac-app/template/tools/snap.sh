#!/bin/zsh
# Snapshots of every page in light and dark, with seed data, on a fresh test store.
# Usage: tools/snap.sh            all pages, behind your windows (inactive look)
#        tools/snap.sh --front    in front and active: takes the keyboard while it runs
#        APP_SNAPSHOT_PAGES=starred,settings tools/snap.sh   (page ids, plus settings)
set -euo pipefail
app=~/Applications/__APP_NAME__.app/Contents/MacOS/__APP_NAME__
store=/tmp/__APP_NAME__-test.store
shots=/tmp/__APP_NAME__-shots
# Seed data only fills an empty store, so start from nothing.
rm -f "$store" "$store-shm" "$store-wal"
if [[ -e "$shots" || -L "$shots" ]]; then
  if [[ -L "$shots" || ! -O "$shots" ]]; then
    print -u2 "Refusing to remove snapshot path not owned by this user: $shots"
    exit 1
  fi
  rm -rf "$shots"
fi
mkdir -m 700 "$shots"
# Test runs neither restore nor save window state, so the real app's state stays as it was.
front=0; [[ " $* " == *" --front "* ]] && front=1
log=$(mktemp /tmp/__APP_NAME__-snap.XXXXXX)
trap 'rm -f "$log"' EXIT
APP_SNAPSHOT_FRONT=$front APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots "$app" -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO | tee "$log"
grep -Fxq "SNAPSHOT done $shots" "$log" || { print -u2 "Snapshot run did not finish"; exit 1; }
expected=(${(f)"$(sed -n 's/^SNAPSHOT expected //p' "$log")"})
(( ${#expected} > 0 )) || { print -u2 "No expected snapshots"; exit 1; }
for shot in "${expected[@]}"; do
  dimensions=$(sips -g pixelWidth -g pixelHeight "$shot" 2>/dev/null)
  print -r -- "$dimensions" | grep -Eq 'pixelWidth: [1-9][0-9]*' &&
    print -r -- "$dimensions" | grep -Eq 'pixelHeight: [1-9][0-9]*' || { print -u2 "Invalid snapshot: $shot"; exit 1; }
done
