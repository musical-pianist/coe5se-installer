#!/bin/bash
# Installs CoE5SE (its latest release, from github.com/musical-pianist/coe5se) and the Jazzy mods
# (the main branch of github.com/musical-pianist/coe5se-mods-suite) on a Mac.
# Run it with:
#   curl -fsSL https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.sh | bash
# or, for CoE5SE alone:
#   curl -fsSL https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.sh | COE5SE_ONLY=1 bash
# It puts each mod folder in ~/.coe5/mods (replacing an older copy) and
# coe5se.dylib in the game folder, next to coe5_mac. It changes nothing else.
set -euo pipefail

ARCHIVE_URL="${COE5_SUITE_ZIP_URL:-https://github.com/musical-pianist/coe5se-mods-suite/archive/refs/heads/main.zip}"
LATEST_URL="https://api.github.com/repos/musical-pianist/coe5se/releases/latest"
MODS_DIR="${COE5_MODS_DIR:-$HOME/.coe5/mods}"
STEAM_DIR="$HOME/Library/Application Support/Steam"
APP_ID=1606340
MODS=(JazzyGamePresets JazzyHotkeys JazzyRestart JazzyUITweaks JazzyCheats)
[[ -n "${COE5SE_ONLY:-}" ]] && MODS=()
LAUNCH_OPTIONS='/usr/bin/env DYLD_INSERT_LIBRARIES=coe5se.dylib %command%'

fail() {
  echo "Install stopped: $1" >&2
  exit 1
}

# Each Steam library holds the game if it has the game's app manifest.
findGameDir() {
  local libraries=("$STEAM_DIR")
  local line library manifest installDir
  if [[ -f "$STEAM_DIR/steamapps/libraryfolders.vdf" ]]; then
    while IFS= read -r line; do
      libraries+=("$line")
    done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$STEAM_DIR/steamapps/libraryfolders.vdf")
  fi
  for library in "${libraries[@]}"; do
    manifest="$library/steamapps/appmanifest_$APP_ID.acf"
    [[ -f "$manifest" ]] || continue
    installDir=$(sed -n '/"installdir"/{s/^[[:space:]]*"installdir"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p;q;}' "$manifest")
    if [[ -n "$installDir" && -f "$library/steamapps/common/$installDir/coe5_mac" ]]; then
      echo "$library/steamapps/common/$installDir"
      return 0
    fi
  done
  return 1
}

GAME_DIR="${COE5_GAME_DIR:-}"
if [[ -z "$GAME_DIR" ]]; then
  GAME_DIR=$(findGameDir) || fail "couldn't find Conquest of Elysium 5 in Steam. Is it installed?"
fi
[[ -f "$GAME_DIR/coe5_mac" ]] || fail "no coe5_mac in $GAME_DIR"

# ps's comm is the executable's path, so only this game folder's copy matches; pgrep -x would match any copy.
# shellcheck disable=SC2009
if ps -axo comm= | grep -Fx "$GAME_DIR/coe5_mac" >/dev/null; then
  fail "Conquest of Elysium 5 is running. Quit the game, then paste the command again."
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT

if [[ ${#MODS[@]} -gt 0 ]]; then echo "Downloading CoE5SE and the mods..."; else echo "Downloading CoE5SE..."; fi
CORE_URL="${COE5SE_ZIP_URL:-}"
if [[ -z "$CORE_URL" ]]; then
  CORE_URL=$(curl -fsSL "$LATEST_URL" | grep -o '"browser_download_url": *"[^"]*/CoE5SE-[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/') || true
fi
[[ -n "$CORE_URL" ]] || fail "the download failed. Check your internet connection and try again."
curl -fsSL -o "$WORK_DIR/coe5se.zip" "$CORE_URL" || fail "the download failed. Check your internet connection and try again."
unzip -q "$WORK_DIR/coe5se.zip" -d "$WORK_DIR/coe5se" || fail "the download was damaged. Try again."
# CoE5SE's zip holds its CoE5SE folder; the suite's archive holds one folder with every Jazzy mod in it.
SUITE_DIR=""
if [[ ${#MODS[@]} -gt 0 ]]; then
  curl -fsSL -o "$WORK_DIR/suite.zip" "$ARCHIVE_URL" || fail "the download failed. Check your internet connection and try again."
  unzip -q "$WORK_DIR/suite.zip" -d "$WORK_DIR/suite" || fail "the download was damaged. Try again."
  SUITE_DIR=$(find "$WORK_DIR/suite" -mindepth 1 -maxdepth 1 -type d -print -quit)
fi
sourceOf() {
  if [[ "$1" = CoE5SE ]]; then echo "$WORK_DIR/coe5se/CoE5SE"; else echo "$SUITE_DIR/$1"; fi
}
for mod in CoE5SE ${MODS[@]+"${MODS[@]}"}; do
  [[ -f "$(sourceOf "$mod")/$mod.c5m" ]] || fail "the download has no $mod folder. Try again later."
done
[[ -f "$WORK_DIR/coe5se/CoE5SE/coe5se.dylib" ]] || fail "the download has no coe5se.dylib. Try again later."

mkdir -p "$MODS_DIR"
for mod in CoE5SE ${MODS[@]+"${MODS[@]}"}; do
  # Copy next to the old folder first, so a failed copy leaves the old one in place.
  rm -rf -- "$MODS_DIR/.$mod.installing"
  cp -R "$(sourceOf "$mod")" "$MODS_DIR/.$mod.installing"
  # Each folder's README.md is for the repo's page; the game never reads it.
  rm -f -- "$MODS_DIR/.$mod.installing/README.md"
  rm -rf -- "${MODS_DIR:?}/$mod"
  mv "$MODS_DIR/.$mod.installing" "$MODS_DIR/$mod"
  echo "Installed $mod in $MODS_DIR/$mod"
done

cp "$WORK_DIR/coe5se/CoE5SE/coe5se.dylib" "$GAME_DIR/.coe5se.dylib.installing"
mv -f "$GAME_DIR/.coe5se.dylib.installing" "$GAME_DIR/coe5se.dylib"
echo "Installed coe5se.dylib in $GAME_DIR"

echo
if grep -Fqs 'DYLD_INSERT_LIBRARIES=coe5se.dylib' "$STEAM_DIR"/userdata/*/config/localconfig.vdf; then
  echo "Steam's Launch Options for the game are already set."
else
  echo "One step left. In Steam, click the gear on Conquest of Elysium 5's page,"
  echo "then Properties, General, and set Launch Options to:"
  echo
  echo "  $LAUNCH_OPTIONS"
fi
echo
echo "Then start the game. The first time, CoE5SE turns itself on and tells you so."
if [[ ${#MODS[@]} -gt 0 ]]; then echo "Turn on the Jazzy mods you want on the Mods screen."; fi
