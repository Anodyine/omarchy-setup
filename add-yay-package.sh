#!/usr/bin/env bash
# add-yay-package.sh
# Usage: add-yay-package.sh <package> [--run]
# - Installs <package> with yay.
# - Adds an idempotent install_<pkg> function to ~/repos/omarchy-setup/setup-omarchy.
# - Commits and pushes the change with a descriptive message.

set -euo pipefail

PKG="${1:-}"
RUN_AFTER="${2:-}"

if [[ -z "$PKG" ]]; then
  echo "Usage: $0 <package> [--run]" >&2
  exit 1
fi

# Where your setup script lives
REPO_DIR="$HOME/repos/omarchy-setup"
SETUP_SCRIPT="$REPO_DIR/setup-omarchy"

# Simple helpers (only echo if absent from setup script)
info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

# Sanity checks
command -v yay >/dev/null || { err "yay not found. Install yay first."; exit 1; }
[[ -d "$REPO_DIR" ]] || { err "Repo not found: $REPO_DIR"; exit 1; }
[[ -f "$SETUP_SCRIPT" ]] || { err "Setup script not found: $SETUP_SCRIPT"; exit 1; }

# Create function name: install_<pkg>, replacing non-alnum with underscores
FUNC_NAME="install_$(echo "$PKG" | tr -c '[:alnum:]' '_' )"

# 1) Install the package now (idempotent via --needed)
info "Installing '$PKG' with yay..."
yay -S --needed --noconfirm "$PKG"

# 2) Add an idempotent function to setup-omarchy if it doesn't exist
if grep -qE "^[[:space:]]*$FUNC_NAME\(\)" "$SETUP_SCRIPT"; then
  info "Function $FUNC_NAME already exists in setup script — skipping append."
else
  info "Appending idempotent installer function $FUNC_NAME to setup script..."
  {
    echo ""
    echo "# BEGIN AUTO: $FUNC_NAME"
    echo "# Idempotent installer for '$PKG' (added by add-yay-installer.sh)"
    cat <<EOF
$FUNC_NAME() {
  # Local helpers mirror your script's style if present; otherwise fall back to echo
  info() { command -v info >/dev/null 2>&1 && info "\$@" || printf "[INFO] %s\\n" "\$*"; }
  warn() { command -v warn >/dev/null 2>&1 && warn "\$@" || printf "[WARN] %s\\n" "\$*"; }
  err()  { command -v err  >/dev/null 2>&1 && err  "\$@" || printf "[ERR ] %s\\n" "\$*" >&2; }

  if ! command -v yay >/dev/null 2>&1; then
    err "yay is not installed. Please install yay first."
    return 1
  fi

  # Idempotent check: if already installed, skip; otherwise install.
  if yay -Qi "$PKG" >/dev/null 2>&1; then
    info "'$PKG' already installed — skipping."
  else
    info "Installing '$PKG'..."
    yay -S --needed --noconfirm "$PKG" || {
      err "Failed to install '$PKG'."
      return 1
    }
  fi

  info "'$PKG' installation verified."
}
EOF
    echo "# END AUTO: $FUNC_NAME"
  } >> "$SETUP_SCRIPT"
fi

# 3) Optionally run the function now
if [[ "${RUN_AFTER:-}" == "--run" ]]; then
  info "Executing $FUNC_NAME from $SETUP_SCRIPT..."
  # shellcheck disable=SC1090
  source "$SETUP_SCRIPT"
  if declare -f "$FUNC_NAME" >/dev/null 2>&1; then
    "$FUNC_NAME"
  else
    warn "Function $FUNC_NAME not found after sourcing — skipping run."
  fi
fi

# 4) Commit and push the change
info "Committing and pushing changes to GitHub..."
git -C "$REPO_DIR" add "$SETUP_SCRIPT"

# Build a descriptive commit message
COMMIT_MSG="setup: add ${FUNC_NAME} for '${PKG}' via yay --needed"
COMMIT_BODY=$(
  cat <<EOT
Adds idempotent installer function ${FUNC_NAME}:
- Uses yay -S --needed for safe re-runs
- Skips if package already installed (yay -Qi)
- Matches setup-omarchy function style

Also installs '${PKG}' immediately.
EOT
)

# If there is nothing to commit, don't fail
if git -C "$REPO_DIR" diff --cached --quiet; then
  warn "No changes to commit (function likely already present)."
else
  git -C "$REPO_DIR" commit -m "$COMMIT_MSG" -m "$COMMIT_BODY"
fi

# Check remote and push
if git -C "$REPO_DIR" remote >/dev/null 2>&1 | grep -q '^origin$'; then
  git -C "$REPO_DIR" push origin HEAD
  info "Pushed to origin."
else
  warn "No 'origin' remote configured. Skipping push."
  warn "Tip: cd $REPO_DIR && git remote add origin <your-repo-url>"
fi

info "Done. Added function: $FUNC_NAME for package '$PKG'."
