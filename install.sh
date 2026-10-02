#!/usr/bin/env bash

# install.sh - Build and install custom PKGBUILDs from this repository.
# Copyright (C) 2026 Thiago C. Silva <librefos@newliber.com>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.

set -euo pipefail

# Color codes are computed once, and only when stderr is a terminal that
# supports them. `|| true` guards keep `set -e` from silently killing the
# script when TERM is dumb/unset (ssh -T, cron, systemd, piped output) —
# without them, tput's failure propagates through the assignment and the
# script dies with no message at all, including inside info -e itself.
if [[ -t 2 ]] && command -v tput >/dev/null; then
  RED=$(tput setaf 1 2>/dev/null || true)
  GREEN=$(tput setaf 2 2>/dev/null || true)
  YELLOW=$(tput setaf 3 2>/dev/null || true)
  NC=$(tput sgr0 2>/dev/null || true) # reset to default rendition
else
  RED='' GREEN='' YELLOW='' NC=''
fi
readonly RED GREEN YELLOW NC

info()
{
  local red="$RED" green="$GREEN" yellow="$YELLOW" nc="$NC"
  local status="$1" message="$2"

  case $status in
    -w)
      printf '%b[WARN]%b %b\n' "$yellow" "$nc" "$message" >&2 
      ;;
    -e)
      printf '%b[ERROR]%b %b\n' "$red" "$nc" "$message" >&2 
      exit 1
      ;;
    -s)
      printf '\n%b==>%b %b\n' "$green" "$nc" "$message" >&2
      ;;
    *)
      printf '%b[INFO]%b %b\n' "$green" "$nc" "$message" >&2 
      ;;
  esac
}

# makepkg strictly forbids running as root to prevent malicious build scripts
# from damaging the host system.
[[ "$EUID" -eq 0 ]] && info -e 'Do not run this script as root.'

#--- Helper Functions ---------------------------------------------------------

parse_selection()
{
  local choices_string="$1"
  # Using a nameref ('local -n') allows this function to safely evaluate and
  # read the external array passed to it without relying on global variables.
  local -n reference_array="$2"
  local choice_token

  IFS=',' read -ra tokens <<< "$choices_string"
  for choice_token in "${tokens[@]}"; do
    # Strip any accidental whitespace the user might have typed.
    choice_token="${choice_token// /}"

    local is_valid_choice=false valid_item
    for valid_item in "${reference_array[@]}"; do
      if [[ "$choice_token" == "$valid_item" ]]; then
        is_valid_choice=true
        break
      fi
    done

    if $is_valid_choice; then
      printf '%s\n' "$choice_token"
    else
      info -w "Invalid selection ignored: $choice_token"
    fi
  done
}

#--------------------------------------------------------- Helper Functions ---
#--- Repository Parsing -------------------------------------------------------

# Resolve the absolute path of the directory containing this script.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_DIR

# Enable nullglob so the array remains completely empty if no subdirectories
# are found, rather than returning a literal '/*' string.
shopt -s nullglob
readonly all_dirs=("$REPO_DIR"/*/)
shopt -u nullglob

packages=()
for directory in "${all_dirs[@]}"; do
  if [[ -f "$directory/PKGBUILD" ]]; then
    packages+=("$(basename "$directory")")
  fi
done

[[ ${#packages[@]} -eq 0 ]] && info -e 'No PKGBUILDs found.'

readonly comma_separated_list="$(IFS=','; printf '%s' "${packages[*]}")"

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "$comma_separated_list"
  exit 0
fi

#------------------------------------------------------- Repository Parsing ---
#--- Interactive Selection ----------------------------------------------------

info -s 'Package Compilation Interactive Mode'

if [[ $# -eq 1 ]]; then
  user_choices="$1"
  info -- "Using provided selection: $user_choices"
else
  printf 'Available packages: %s\n' "$comma_separated_list"
  # Redirecting I/O directly to /dev/tty ensures the prompt works reliably even
  # if the script's output is being piped or redirected elsewhere.
  printf 'Enter names to build (comma-separated, or "all") ' >/dev/tty
  printf 'or press Enter to skip all: ' >/dev/tty
  read -r user_choices </dev/tty
fi

# Intercept "all" and expand it
if [[ "${user_choices,,}" == 'all' ]]; then
  user_choices="$comma_separated_list"
  info -- "Expanded 'all' to: $user_choices"
fi

# mapfile safely ingests the multiline output of parse_selection into a real array.
mapfile -t selected_packages < <(parse_selection "$user_choices" packages)

if [[ ${#selected_packages[@]} -eq 0 ]]; then
  info -- 'No packages selected. Exiting.'
  exit 0
fi

info -- "Selected for compilation: ${selected_packages[*]}"

#---------------------------------------------------- Interactive Selection ---
#--- Package Compilation ------------------------------------------------------

for package_name in "${selected_packages[@]}"; do
  package_dir="$REPO_DIR/$package_name"
  if [[ ! -f "$package_dir/PKGBUILD" ]]; then
    info -w "PKGBUILD not found for '$package_name'. Skipping."
    continue
  fi

  info -- "Building and installing $package_name..."

  # --syncdeps: Automatically resolves and installs missing dependencies.
  # --install: Installs the compiled package using pacman when finished.
  # --cleanbuild: Deletes the local $srcdir BEFORE building to ensure a fresh
  #   checkout. This is strictly required to prevent cache conflicts in -git packages.
  # --clean: Cleans up the leftover build files (src/, pkg/) AFTER a successful build.
  (cd "$package_dir" && makepkg --syncdeps --install --cleanbuild --clean --noconfirm)
done

info -- 'All selected packages built and installed successfully.'

#------------------------------------------------------ Package Compilation ---
