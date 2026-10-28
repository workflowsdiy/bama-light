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
APP_SNAPSHOT_FRONT=$front APP_STORE=$store APP_SEED=1 APP_SNAPSHOT=$shots "$app" -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO
