#!/usr/bin/env bash
# Installs preferred Omarchy configuration
# Includes fixes for Nvidia, package installs, and application configuration

set -euo pipefail

info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

install_oh_my_zsh() {
  if [ -d "${HOME}/.oh-my-zsh" ]; then
    info "Oh My Zsh already installed at ~/.oh-my-zsh"
    return
  fi
  info "Installing Oh My Zsh (non-interactive)."
  export RUNZSH=no
  export CHSH=no
  export KEEP_ZSHRC=yes
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
}

ensure_zshrc() {
  local sentinel="${HOME}/.zshrc.omz_backed_up"
  if [ -f "${HOME}/.zshrc" ]; then
    if [ ! -f "$sentinel" ]; then
      cp -a "${HOME}/.zshrc" "${HOME}/.zshrc.pre-omz-$(date +%Y%m%d%H%M%S).bak"
      : > "$sentinel"
      info "Backed up existing .zshrc"
    else
      info ".zshrc already backed up previously. Skipping backup."
    fi
  else
    cp "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" "${HOME}/.zshrc"
    info "Created new .zshrc from template"
  fi
}

install_plugins() {
  local ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
  mkdir -p "${ZSH_CUSTOM}/plugins"

  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions/.git" ]; then
    info "Installing zsh-autosuggestions plugin."
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  else
    info "Updating zsh-autosuggestions plugin."
    git -C "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" pull --ff-only || warn "autosuggestions update failed"
  fi

  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting/.git" ]; then
    info "Installing zsh-syntax-highlighting plugin."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  else
    info "Updating zsh-syntax-highlighting plugin."
    git -C "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" pull --ff-only || warn "syntax-highlighting update failed"
  fi
}


configure_zshrc() {
  local zshrc="${HOME}/.zshrc"

  # Set theme to dpoggi
  if grep -qE '^ZSH_THEME=' "$zshrc"; then
    sed -i 's/^ZSH_THEME=.*/ZSH_THEME="dpoggi"/' "$zshrc"
  else
    printf '\nZSH_THEME="dpoggi"\n' >> "$zshrc"
  fi
  info "Theme set to dpoggi."

  # Set plugins list. Keep syntax-highlighting last for correctness.
  local desired_plugins='plugins=(git zsh-autosuggestions zsh-syntax-highlighting)'
  if grep -qE '^\s*plugins=\(' "$zshrc"; then
    sed -i 's/^\s*plugins=.*$/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' "$zshrc"
  else
    printf '\n%s\n' "$desired_plugins" >> "$zshrc"
  fi
  info "Enabled plugins in .zshrc: git, zsh-autosuggestions, zsh-syntax-highlighting"

  # Ensure oh-my-zsh is sourced
  if ! grep -q 'source \$ZSH/oh-my-zsh.sh' "$zshrc"; then
    printf '\nexport ZSH="$HOME/.oh-my-zsh"\nsource $ZSH/oh-my-zsh.sh\n' >> "$zshrc"
  fi

  # Explicitly source syntax highlighting last
  if ! grep -q 'zsh-syntax-highlighting.zsh' "$zshrc"; then
    cat >> "$zshrc" <<'EOF'

# Ensure zsh-syntax-highlighting is sourced last
if [ -f "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
  source "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
EOF
  fi
}

make_default_shell() {
  local zsh_path
  zsh_path="$(command -v zsh || true)"
  if [ -z "$zsh_path" ]; then
    err "zsh not found on PATH. Aborting default shell change."
    return
  fi

  # Ensure /etc/shells contains zsh
  if ! grep -qx "$zsh_path" /etc/shells 2>/dev/null; then
    info "Adding ${zsh_path} to /etc/shells (requires sudo)."
    echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
  fi

  if [ "${SHELL:-}" = "$zsh_path" ]; then
    info "zsh is already the default shell."
  else
    info "Changing default shell to zsh for user ${USER}."
    chsh -s "$zsh_path"
    info "Default shell changed. Log out and back in, or start zsh now with: zsh"
  fi
}

setup_chromium_workspace_fix() {
  if ! command -v chromium >/dev/null 2>&1; then
    warn "chromium not found on PATH. Skipping Chromium setup."
    return 0
  fi

  info "Configuring Chromium wrapper and flags."

  # a) Wrapper with stable flags
  mkdir -p "${HOME}/.local/share/omarchy/bin"
  cat > "${HOME}/.local/share/omarchy/bin/chromium-stable" <<'EOF'
#!/usr/bin/env bash
exec chromium \
  --ozone-platform=x11 \
  --use-gl=egl-angle \
  --use-angle=opengl \
  "$@"
EOF
  chmod +x "${HOME}/.local/share/omarchy/bin/chromium-stable"

  # b) Ensure GUI apps see the wrapper directory
  mkdir -p "${HOME}/.config/environment.d"
  cat > "${HOME}/.config/environment.d/omarchy-path.conf" <<'EOF'
PATH=$HOME/.local/share/omarchy/bin:$PATH
EOF
  systemctl --user import-environment PATH || true

  # c) Global Chromium flags file
  mkdir -p "${HOME}/.config"
  cat > "${HOME}/.config/chromium-flags.conf" <<'EOF'
--ozone-platform=x11
--use-gl=egl-angle
--use-angle=opengl
EOF

  # d) Override desktop file to use wrapper
  mkdir -p "${HOME}/.local/share/applications"
  if [ -f /usr/share/applications/chromium.desktop ]; then
    cp /usr/share/applications/chromium.desktop "${HOME}/.local/share/applications/" 2>/dev/null || true
    sed -i -E "s|^Exec=.*|Exec=${HOME}/.local/share/omarchy/bin/chromium-stable %U|g" \
      "${HOME}/.local/share/applications/chromium.desktop" || true
    xdg-settings set default-web-browser chromium.desktop 2>/dev/null || true
    update-desktop-database "${HOME}/.local/share/applications" 2>/dev/null || true
  else
    warn "Could not find /usr/share/applications/chromium.desktop to override."
  fi

  # e) Make omarchy webapps use the same wrapper and log
  if [ -f "${HOME}/.local/share/omarchy/bin/omarchy-launch-webapp" ]; then
    mkdir -p "${HOME}/.local/share/omarchy/logs"
    sed -i "s|^\s*exec\s*chromium|exec ${HOME}/.local/share/omarchy/bin/chromium-stable --enable-logging=stderr --v=1 2>>${HOME}/.local/share/omarchy/logs/chromium.log|" \
      "${HOME}/.local/share/omarchy/bin/omarchy-launch-webapp" || true
  else
    warn "omarchy-launch-webapp not found. Skipping webapp launcher patch."
  fi

  # f) Clean stale singletons and GPU caches once
#   info "Cleaning Chromium caches and singletons."
#   killall -9 chromium chrome 2>/dev/null || true
#   rm -f "${HOME}/.config/chromium/Singleton"* 2>/dev/null || true
#   rm -rf "${HOME}/.config/chromium/GPUCache" "${HOME}/.config/chromium/ShaderCache" 2>/dev/null || true

  info "Chromium configured. Log out and back in once so GUI PATH takes effect."
}

install_packages_from_list() {
  local repo_dir="$HOME/repos/omarchy-setup"
  local list_file="${1:-$repo_dir/packages.list}"

  # Ensure yay is installed
  if ! command -v yay &>/dev/null; then
    err "yay is not installed. Please install yay first."
    return 1
  fi

  info "Installing packages from $list_file"

  if [[ ! -f "$list_file" ]]; then
    warn "No package list found at $list_file"
    return 0
  fi

  # Read list, ignoring comments and blank lines
  mapfile -t all_pkgs < <(sed -e 's/#.*$//' -e '/^\s*$/d' "$list_file")

  if [[ ${#all_pkgs[@]} -eq 0 ]]; then
    info "No packages listed in $list_file. Skipping."
    return 0
  fi

  info "Installing packages: ${all_pkgs[*]}"
  yay -S --needed --noconfirm "${all_pkgs[@]}"
}

# Detect a VS Code CLI (Visual Studio Code, Code - OSS, or VSCodium)
detect_code_cli() {
  local candidates=("code" "code-oss" "codium" "vscodium")
  for c in "${candidates[@]}"; do
    if command -v "$c" &>/dev/null; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

install_vscode_extensions_from_list() {
  local repo_dir="$HOME/repos/omarchy-setup"
  local list_file="${1:-$repo_dir/vscode-extensions.list}"

  local CODE_BIN
  if ! CODE_BIN="$(detect_code_cli)"; then
    err "VS Code CLI not found on PATH. Install Visual Studio Code (code), Code - OSS (code-oss), or VSCodium (codium)."
    return 1
  fi

  info "Installing VS Code extensions from $list_file using '$CODE_BIN'"

  if [[ ! -f "$list_file" ]]; then
    warn "No extensions list found at $list_file"
    return 0
  fi

  mapfile -t extensions < <(sed -e 's/#.*$//' -e '/^\s*$/d' "$list_file")
  if [[ ${#extensions[@]} -eq 0 ]]; then
    info "No extensions listed. Skipping."
    return 0
  fi

  # Build a set of installed extensions for O(1) checks
  mapfile -t installed < <("$CODE_BIN" --list-extensions 2>/dev/null || true)
  local tmp="$(mktemp)"; printf "%s\n" "${installed[@]}" | sort > "$tmp"

  local failed=()
  for ext in "${extensions[@]}"; do
    if grep -qx "$ext" "$tmp"; then
      info "Extension already installed: $ext"
      continue
    fi
    info "Installing extension: $ext"
    if ! "$CODE_BIN" --install-extension "$ext"; then
      warn "Failed to install extension: $ext"
      failed+=("$ext")
    fi
  done
  rm -f "$tmp"

  if [[ ${#failed[@]} -gt 0 ]]; then
    warn "These extensions failed to install: ${failed[*]}"
    return 2
  fi
  info "Finished installing VS Code extensions."
}

export_vscode_extensions() {
  local CODE_BIN
  if ! CODE_BIN="$(detect_code_cli)"; then
    err "VS Code CLI not found on PATH."
    return 1
  fi
  local out="${1:-$HOME/repos/omarchy-setup/vscode-extensions.list}"
  "$CODE_BIN" --list-extensions | sort > "$out"
  info "Wrote extensions to $out"
}

setup_vscode_settings() {
  info "Configuring VS Code user settings..."
  local settings_dir="$HOME/.config/Code/User"
  local settings_file="$settings_dir/settings.json"
  local source_file="$SCRIPT_DIR/vscode-settings.json"

  mkdir -p "$settings_dir"
  if [[ ! -f "$source_file" ]]; then
    warn "Source settings file not found at $source_file. Skipping."
    return 0
  fi

  # If target exists and is identical, do nothing
  if [[ -f "$settings_file" ]] && cmp -s "$source_file" "$settings_file"; then
    info "settings.json already matches source. No changes."
    return 0
  fi

  # Backup once per differing content write
  if [[ -f "$settings_file" ]]; then
    local backup_file="${settings_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp -a "$settings_file" "$backup_file"
    info "Backed up existing settings.json to $backup_file"
  fi

  cp -a "$source_file" "$settings_file"
  info "Copied VS Code settings from $source_file to $settings_file"

  if [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
    chown "$SUDO_USER":"$SUDO_USER" "$settings_file"
    info "Adjusted ownership of $settings_file for user $SUDO_USER"
  fi
}

main() {
  install_packages_from_list "$SCRIPT_DIR/packages.list"
  install_oh_my_zsh
  ensure_zshrc
  install_plugins
  configure_zshrc
  make_default_shell
  setup_chromium_workspace_fix
  install_vscode_extensions_from_list
  setup_vscode_settings
  install_packages_from_list "$SCRIPT_DIR/texlive-packages.list"

  # Install informant last so its hook doesn’t block anything else
  # If you run this, you will need to read the latest news before
  # updating or installing packages. That way, you won't miss required manual
  # interventions.
  yay -S --needed --noconfirm informant
  info "All done."
}

main "$@"

