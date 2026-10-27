#!/bin/zsh
# Creates a new macOS app from the template next to this script.
# Usage: new-app.sh <AppName> <bundle-id> [parent-folder]
#   new-app.sh Tasks com.yourname.tasks ~/Developer
# Creates <parent-folder>/<AppName>, which must be new or empty.
# AppName must be one word in UpperCamelCase (letters and digits only).
set -euo pipefail
name=${1:?usage: new-app.sh <AppName> <bundle-id> [parent-folder]}
bundle=${2:?usage: new-app.sh <AppName> <bundle-id> [parent-folder]}
parent=${3:-$PWD}
[[ "$name" =~ ^[A-Z][A-Za-z0-9]*$ ]] || { echo "AppName must be UpperCamelCase letters and digits, like Tasks or DailyLog"; exit 1; }
template=${0:A:h:h}/template
git var GIT_AUTHOR_IDENT >/dev/null 2>&1 || { echo "git needs your name and email first: git config --global user.name \"Your Name\"; git config --global user.email you@example.com"; exit 1; }
dest="$parent/$name"
# A new or empty folder only: the first commit then holds nothing but the template.
[[ ! -e "$dest" || -z "$(ls -A "$dest")" ]] || { echo "$dest exists and is not empty"; exit 1; }

mkdir -p "$dest"
cp -R -n "$template/" "$dest/"
mv "$dest/Sources/__APP_NAME__" "$dest/Sources/$name"
mv "$dest/Sources/__APP_NAME__Kit" "$dest/Sources/${name}Kit"
mv "$dest/Tests/__APP_NAME__KitTests" "$dest/Tests/${name}KitTests"
# The template's license notice travels with the code it covers.
license=${0:A:h:h:h:h}/LICENSE
[[ -f "$license" ]] && cp "$license" "$dest/LICENSE-bama-light"
# Replace the placeholders in every text file.
grep -rlI "__APP_NAME__\|__BUNDLE_ID__" "$dest" | while read -r f; do
  sed -i '' -e "s/__APP_NAME__/$name/g" -e "s/__BUNDLE_ID__/$bundle/g" "$f"
done
chmod +x "$dest/build.sh" "$dest"/tools/*.sh

cd "$dest"
[[ -d .git ]] || git init -q
git add -A
git commit -qm "Create $name from the macOS app template"
echo "created $dest"
echo "next: cd \"$dest\" && ./build.sh (--open also brings the app forward, taking focus)"
