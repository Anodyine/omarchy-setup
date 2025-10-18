#!/usr/bin/env bash
# lib/pkg.sh — shared helpers for installing packages from a list

# Simple logs (defined here so the lib works even if caller doesn't define them)
info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*"; }

# install_packages_from_list <path-to-list> [additional yay args...]
# Reads lines, ignoring blanks and comments starting with #
install_packages_from_list() {
  local list_file="${1:-}"; shift || true

  if [[ -z "$list_file" ]]; then
    err "usage: install_packages_from_list <path-to-list> [extra yay args]"
    return 2
  fi

  if ! command -v yay &>/dev/null; then
    err "yay is not installed. Please install yay first."
    return 1
  fi

  if [[ ! -f "$list_file" ]]; then
    warn "No package list found at $list_file"
    return 0
  fi

  mapfile -t all_pkgs < <(sed -e 's/#.*$//' -e '/^\s*$/d' "$list_file")

  if [[ ${#all_pkgs[@]} -eq 0 ]]; then
    info "No packages listed in $list_file. Skipping."
    return 0
  fi

  info "Installing packages from $list_file: ${all_pkgs[*]}"
  # Allow callers to pass extra yay flags after the list file
  yay -S --needed --noconfirm "$@" "${all_pkgs[@]}"
}
