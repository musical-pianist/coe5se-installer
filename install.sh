#!/bin/bash
# Installs CoE5SE (its latest release, from github.com/musical-pianist/coe5se), the Jazzy mods
# (the main branch of github.com/musical-pianist/coe5se-mods-suite), or both, on a Mac. It asks which.
# Run it with:
#   curl -fsSL https://raw.githubusercontent.com/musical-pianist/coe5se-installer/main/install.sh | bash
# It puts each mod folder in ~/.coe5/mods (replacing an older copy) and, with CoE5SE,
# coe5se.dylib in the game folder, next to coe5_mac. It changes nothing else.
# COE5_INSTALL_CHOICE=1, 2 or 3 answers the question without asking (tests, scripts).
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

OPTIONS=("Script Extender and all mods" "Script Extender only" "Mods only")

# An arrow-key menu on the terminal. The script itself arrives on standard input (curl | bash), so the keys
# are read from /dev/tty. 1, 2 or 3 picks directly. It sets CHOICE to 1, 2 or 3.
pickChoice() {
  local selected=0 key rest i on="" off=""
  exec 3</dev/tty 2>/dev/null || fail "this needs a terminal to ask what to install. Paste the command into Terminal."
  if [[ -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then on=$'\033[1;36m'; off=$'\033[0m'; fi
  # Keys pressed while the menu redraws are never echoed; the terminal is put back however the script ends.
  local saved
  saved=$(stty -g <&3)
  stty -echo <&3
  trap 'stty "$saved" </dev/tty 2>/dev/null; printf "\033[?25h"' EXIT
  printf '\033[?25l'
  echo "What do you want to install?"
  echo
  while true; do
    for i in 0 1 2; do
      if [[ $i -eq $selected ]]; then printf '\r\033[K%s> %s%s\n' "$on" "${OPTIONS[$i]}" "$off"
      else printf '\r\033[K  %s\n' "${OPTIONS[$i]}"; fi
    done
    printf '\n\033[KUp and Down to move, Enter to pick, Ctrl-C to quit'
    IFS= read -rsn1 key <&3 || fail "no answer. Paste the command into Terminal again."
    case "$key" in
      $'\033') IFS= read -rsn2 -t 1 rest <&3 || rest=""
               [[ "$rest" = "[A" && $selected -gt 0 ]] && selected=$((selected - 1))
               [[ "$rest" = "[B" && $selected -lt 2 ]] && selected=$((selected + 1)) ;;
      [123]) selected=$((key - 1)); break ;;
      "") break ;;
    esac
    printf '\r\033[4A'
  done
  printf '\r\033[4A'
  for i in 0 1 2; do
    if [[ $i -eq $selected ]]; then printf '\r\033[K%s> %s%s\n' "$on" "${OPTIONS[$i]}" "$off"; else printf '\r\033[K  %s\n' "${OPTIONS[$i]}"; fi
  done
  printf '\r\033[K\n\r\033[K\033[?25h'
  stty "$saved" <&3
  exec 3<&-
  CHOICE=$((selected + 1))
}

CHOICE="${COE5_INSTALL_CHOICE:-}"
case "$CHOICE" in
  1|2|3) ;;
  "") pickChoice ;;
  *) fail "COE5_INSTALL_CHOICE must be 1, 2 or 3." ;;
esac
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
fi

# The ending: what was installed is done; the steps left are numbered, the last one the player's.
green="" reset=""
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]]; then green=$'\033[1;32m'; reset=$'\033[0m'; fi
echo
echo "${green}Install finished!${reset}"
echo
step=1
if [[ -n "$WITH_CORE" ]] && ! grep -Fqs 'DYLD_INSERT_LIBRARIES=coe5se.dylib' "$STEAM_DIR"/userdata/*/config/localconfig.vdf; then
  echo "$step. If you haven't installed CoE5SE before: in Steam, click the gear on"
  echo "   Conquest of Elysium 5's page, then Properties, General, and set Launch"
  echo "   Options to:"
  echo
  echo "     $LAUNCH_OPTIONS"
  echo
  step=$((step + 1))
fi
if [[ -n "$WITH_CORE" ]]; then
  echo "$step. Start the game. The first time, CoE5SE turns itself on and tells you so."
else
  echo "$step. Start the game."
fi
step=$((step + 1))
if [[ ${#MODS[@]} -gt 0 ]]; then echo "$step. Turn on the mods you want on the Mods screen."; fi
