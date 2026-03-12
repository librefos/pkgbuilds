#!/usr/bin/env bash

# install.sh - Build and install custom PKGBUILDs from this repository.
# Copyright (C) 2026 Thiago C Silva <librefos@hotmail.com>
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

readonly RED='\033[1;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

info()  { printf "${GREEN}[INFO]${NC} %b\n"  "$1" >&2; }
warn()  { printf "${YELLOW}[WARN]${NC} %b\n" "$1" >&2; }
error() { printf "${RED}[ERROR]${NC} %b\n"   "$1" >&2; exit 1; }

# Parse a comma-separated string of 1-based indices against a reference.
parse_selection()
{
  local choices_string="$1"
  local -n reference_array="$2"
  local choice_token

  IFS=',' read -ra tokens <<< "$choices_string"
  for choice_token in "${tokens[@]}"; do
    choice_token="${choice_token// /}"

    local is_positive_integer=false
    if [[ "$choice_token" =~ ^[0-9]+$ ]]; then
      is_positive_integer=true
    fi

    local is_within_bounds=false
    if (( choice_token > 0 && choice_token <= ${#reference_array[@]} )); then
      is_within_bounds=true
    fi

    if $is_positive_integer && $is_within_bounds; then
      printf '%s\n' "${reference_array[$((choice_token-1))]}"
    else
      warn "Invalid selection ignored: $choice_token"
    fi
  done
}

[[ "$EUID" -eq 0 ]] && error 'Do not run this script as root.'

readonly REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

shopt -s nullglob
readonly all_dirs=("$REPO_DIR"/*/)
shopt -u nullglob

packages=()
for directory in "${all_dirs[@]}"; do
  if [[ -f "$directory/PKGBUILD" ]]; then
    packages+=("$(basename "$directory")")
  fi
done

[[ ${#packages[@]} -eq 0 ]] && error 'No PKGBUILDs found.'

printf 'Available packages:\n'
for i in "${!packages[@]}"; do
  printf '[%d] %s\n' "$((i+1))" "${packages[i]}"
done

printf 'Enter numbers to build (comma-separated) ' >/dev/tty
printf 'or press Enter to skip all: ' >/dev/tty
read -r user_choices </dev/tty

mapfile -t selected_packages < <(
  parse_selection "$user_choices" packages
)

if [[ ${#selected_packages[@]} -eq 0 ]]; then
  info 'No packages selected. Exiting.'
  exit 0
fi

info "Selected for compilation: ${selected_packages[*]}"

for package_name in "${selected_packages[@]}"; do
  package_dir="$REPO_DIR/$package_name"
  if [[ ! -f "$package_dir/PKGBUILD" ]]; then
    warn "PKGBUILD not found for '$package_name'. Skipping."
    continue
  fi

  info "Building and installing $package_name..."

  (cd "$package_dir" && makepkg -si --noconfirm)
done

info 'All selected packages built and installed successfully.'
