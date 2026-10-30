#!/bin/zsh
# Runs the in-app self-test against a fresh store in /tmp. Exit code 0 when every check passed.
set -euo pipefail
store=/tmp/__APP_NAME__-self.store
rm -f $store $store-shm $store-wal
# Test runs neither restore nor save window state, so the real app's state stays as it was.
log=$(mktemp /tmp/__APP_NAME__-selftest.XXXXXX)
trap 'rm -f "$log"' EXIT
APP_STORE=$store ~/Applications/__APP_NAME__.app/Contents/MacOS/__APP_NAME__ \
  -ApplePersistenceIgnoreState YES -NSQuitAlwaysKeepsWindows NO --selftest | tee "$log"
grep -Eq '^SELFTEST PASS [1-9][0-9]* checks$' "$log" || { print -u2 "Self-test did not finish"; exit 1; }
