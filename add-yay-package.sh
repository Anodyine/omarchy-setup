#!/usr/bin/env bash
# add-yay-package.sh
# Usage: add-yay-package.sh <package> [--run]
# - Appends <package> to packages.list (idempotent).
# - Commits and pushes the change.
# - If --run is given, installs that package immediately on this machine.

set -euo pipefail

PKG="${1:-}"
RUN_AFTER="${2:-}"

if [[ -z "$PKG" ]]; then
  echo "Usage: $0 <package> [--run]" >&2
  exit 1
fi

REPO_DIR="$HOME/repos/omarchy-setup"
LIST_FILE="$REPO_DIR/packages.list"

info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

[[ -d "$REPO_DIR" ]] || { err "Repo not found: $REPO_DIR"; exit 1; }
[[ -f "$LIST_FILE" ]] || { info "Creating $LIST_FILE"; : > "$LIST_FILE"; }

# Normalize whitespace
PKG="$(echo -n "$PKG" | tr -d '[:space:]')"
[[ -n "$PKG" ]] || { err "Package name empty after normalization."; exit 1; }

# Add package if not present (ignore comments and blanks)
if grep -vxqF "$PKG" <(sed -e 's/#.*$//' -e '/^\s*$/d' "$LIST_FILE"); then
  info "Adding '$PKG' to $LIST_FILE"
  echo "$PKG" >> "$LIST_FILE"
else
  info "'$PKG' already present in $LIST_FILE"
fi

# Optional: keep list tidy and unique (preserve comments by rebuilding non-comment block)
tmp="$(mktemp)"
{
  # Keep existing comments and their positions
  grep -E '^\s*#|^\s*$' "$LIST_FILE"
  # Re-add unique package lines sorted
  sed -e 's/#.*$//' -e '/^\s*$/d' "$LIST_FILE" | sort -u
} | awk 'NF{print}' > "$tmp"
mv "$tmp" "$LIST_FILE"

# Commit and push list change
info "Committing and pushing packages.list update..."
git -C "$REPO_DIR" add "$LIST_FILE"
if git -C "$REPO_DIR" diff --cached --quiet; then
  warn "No changes to commit."
else
  git -C "$REPO_DIR" commit -m "packages: add ${PKG} to packages.list"
fi

if git -C "$REPO_DIR" remote >/dev/null 2>&1 | grep -q '^origin$'; then
  git -C "$REPO_DIR" push origin HEAD
  info "Pushed to origin."
else
  warn "No 'origin' remote configured. Skipping push."
fi

# Install immediately if requested
if [[ "${RUN_AFTER:-}" == "--run" ]]; then
  if ! command -v yay >/dev/null 2>&1; then
    err "yay not found. Install yay first."
    exit 1
  fi
  info "Installing '$PKG' now with yay..."
  yay -S --needed --noconfirm "$PKG"
fi

info "Done. '$PKG' tracked in packages.list."
