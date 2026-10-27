#!/bin/zsh
# Compiles Icon/AppIcon.icon (an Icon Composer file) with actool and writes:
#   Resources/Assets.car     the Liquid Glass icon (light, dark, tinted, clear)
#   Resources/AppIcon.icns   flat fallback for Finder views that read .icns
# build.sh runs this when the .icon changed. Run it by hand to check errors.
set -euo pipefail
here=${0:A:h}
repo=${here:h}
icon="$repo/Icon/AppIcon.icon"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$repo/Resources"

# Without Xcode there is no actool: write only a flat AppIcon.icns.
if ! xcrun --find actool >/dev/null 2>&1; then
  swift "$here/flat_icon.swift" "$icon" "$work/AppIcon.png"
  mkdir "$work/AppIcon.iconset"
  for px in 16 32 128 256 512; do
    sips -z $px $px "$work/AppIcon.png" --out "$work/AppIcon.iconset/icon_${px}x${px}.png" >/dev/null
    sips -z $((px * 2)) $((px * 2)) "$work/AppIcon.png" --out "$work/AppIcon.iconset/icon_${px}x${px}@2x.png" >/dev/null
  done
  iconutil -c icns "$work/AppIcon.iconset" -o "$repo/Resources/AppIcon.icns"
  rm -f "$repo/Resources/Assets.car"
  echo "wrote Resources/AppIcon.icns (flat: no actool, so no Liquid Glass)"
  exit 0
fi

# actool fails on a missing layer image, so it doubles as the validator.
# The .icon must be named AppIcon.icon to match --app-icon, or actool
# writes nothing and still exits 0. Check the output to catch that.
xcrun actool "$icon" --compile "$work" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon AppIcon \
  --output-partial-info-plist "$work/partial.plist" \
  --output-format human-readable-text --errors --warnings >"$work/log" 2>&1 || { cat "$work/log"; exit 1; }
[[ -f "$work/Assets.car" && -f "$work/AppIcon.icns" ]] || { cat "$work/log"; echo "actool wrote no icon"; exit 1; }
cp "$work/Assets.car" "$work/AppIcon.icns" "$repo/Resources/"
echo "wrote Resources/Assets.car and Resources/AppIcon.icns"
