#!/bin/bash
# Installs CoE5SE (its latest release, from github.com/musical-pianist/coe5se), the Jazzy mods
# (the main branch of github.com/musical-pianist/coe5se-mods-suite), or both, on a Mac. It asks which.
# Run it with:
#   curl -fsSL https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.sh | bash
# It puts each mod folder in ~/.coe5/mods (replacing an older copy) and, with CoE5SE,
# coe5se.dylib in the game folder, next to coe5_mac. It changes nothing else.
# COE5_INSTALL_CHOICE=1, 2 or 3 answers the question without asking (tests).
set -euo pipefail

ARCHIVE_URL="${COE5_SUITE_ZIP_URL:-https://github.com/musical-pianist/coe5se-mods-suite/archive/refs/heads/main.zip}"
LATEST_URL="https://api.github.com/repos/musical-pianist/coe5se/releases/latest"
MODS_DIR="${COE5_MODS_DIR:-$HOME/.coe5/mods}"
STEAM_DIR="$HOME/Library/Application Support/Steam"
APP_ID=1606340
ALL_MODS=(JazzyGamePresets JazzyHotkeys JazzyRestart JazzyUITweaks JazzyCheats)
LAUNCH_OPTIONS='/usr/bin/env DYLD_INSERT_LIBRARIES=coe5se.dylib %command%'

fail() {
  echo "Install stopped: $1" >&2
  exit 1
}
# Anything not caught below still ends with one plain line.
trap 'fail "something unexpected went wrong. Nothing more was changed. Try again, or report it on github.com/musical-pianist/coe5se-installer."' ERR

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

# The script itself arrives on standard input (curl | bash), so the answer is read from the terminal.
CHOICE="${COE5_INSTALL_CHOICE:-}"
while [[ "$CHOICE" != 1 && "$CHOICE" != 2 && "$CHOICE" != 3 ]]; do
  echo "What do you want to install?"
  echo "  1) Script Extender and all mods"
  echo "  2) Script Extender only"
  echo "  3) Mods only"
  printf "Type 1, 2 or 3, then press Return: "
  read -r CHOICE < /dev/tty || fail "no answer. Paste the command into Terminal again."
  [[ "$CHOICE" = 1 || "$CHOICE" = 2 || "$CHOICE" = 3 ]] || echo "That's not 1, 2 or 3."
done
WITH_CORE=yes
MODS=("${ALL_MODS[@]}")
[[ "$CHOICE" = 2 ]] && MODS=()
[[ "$CHOICE" = 3 ]] && WITH_CORE=""
INSTALL=()
[[ -n "$WITH_CORE" ]] && INSTALL+=(CoE5SE)
INSTALL+=(${MODS[@]+"${MODS[@]}"})

WORK_DIR=$(mktemp -d)
trap 'rm -rf -- "$WORK_DIR"' EXIT

echo "Downloading..."
if [[ -n "$WITH_CORE" ]]; then
  CORE_URL="${COE5SE_ZIP_URL:-}"
  if [[ -z "$CORE_URL" ]]; then
    CORE_URL=$(curl -fsL "$LATEST_URL" | grep -o '"browser_download_url": *"[^"]*/CoE5SE-[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/') || true
  fi
  [[ -n "$CORE_URL" ]] || fail "couldn't find CoE5SE's latest release. Check your internet connection and try again."
  curl -fsL -o "$WORK_DIR/coe5se.zip" "$CORE_URL" || fail "the download failed. Check your internet connection and try again."
  unzip -q "$WORK_DIR/coe5se.zip" -d "$WORK_DIR/coe5se" || fail "the download was damaged. Try again."
  [[ -f "$WORK_DIR/coe5se/CoE5SE/coe5se.dylib" ]] || fail "the download has no coe5se.dylib. Try again later."
fi
# CoE5SE's zip holds its CoE5SE folder; the suite's archive holds one folder with every Jazzy mod in it.
SUITE_DIR=""
if [[ ${#MODS[@]} -gt 0 ]]; then
  curl -fsL -o "$WORK_DIR/suite.zip" "$ARCHIVE_URL" || fail "the download failed. Check your internet connection and try again."
  unzip -q "$WORK_DIR/suite.zip" -d "$WORK_DIR/suite" || fail "the download was damaged. Try again."
  SUITE_DIR=$(find "$WORK_DIR/suite" -mindepth 1 -maxdepth 1 -type d -print -quit)
fi
sourceOf() {
  if [[ "$1" = CoE5SE ]]; then echo "$WORK_DIR/coe5se/CoE5SE"; else echo "$SUITE_DIR/$1"; fi
}
for mod in "${INSTALL[@]}"; do
  [[ -f "$(sourceOf "$mod")/$mod.c5m" ]] || fail "the download has no $mod folder. Try again later."
done

mkdir -p "$MODS_DIR" 2>/dev/null || fail "couldn't create the mods folder $MODS_DIR."
for mod in "${INSTALL[@]}"; do
  # Copy next to the old folder first, so a failed copy leaves the old one in place.
  rm -rf -- "$MODS_DIR/.$mod.installing"
  cp -R "$(sourceOf "$mod")" "$MODS_DIR/.$mod.installing" 2>/dev/null || fail "couldn't copy $mod into $MODS_DIR. Is the disk full?"
  # Each folder's README.md is for the repo's page; the game never reads it.
  rm -f -- "$MODS_DIR/.$mod.installing/README.md"
  rm -rf -- "${MODS_DIR:?}/$mod" 2>/dev/null || fail "couldn't replace the old $mod folder in $MODS_DIR."
  mv "$MODS_DIR/.$mod.installing" "$MODS_DIR/$mod" || fail "couldn't replace the old $mod folder in $MODS_DIR."
  echo "Installed $mod in $MODS_DIR/$mod"
done

if [[ -n "$WITH_CORE" ]]; then
  { cp "$WORK_DIR/coe5se/CoE5SE/coe5se.dylib" "$GAME_DIR/.coe5se.dylib.installing" &&
    mv -f "$GAME_DIR/.coe5se.dylib.installing" "$GAME_DIR/coe5se.dylib"; } 2>/dev/null ||
    fail "couldn't copy coe5se.dylib into the game folder $GAME_DIR."
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
else
  echo
  [[ -f "$MODS_DIR/CoE5SE/CoE5SE.c5m" ]] || echo "These mods need CoE5SE. Run the command again and pick 2 to install it."
  echo "Then start the game."
fi
if [[ ${#MODS[@]} -gt 0 ]]; then echo "Turn on the Jazzy mods you want on the Mods screen."; fi
