#!/usr/bin/env bash
# Installs zsh + Oh My Zsh + autosuggestions + syntax highlighting,
# sets theme to dpoggi, enables plugins in .zshrc, sets default shell to zsh,
# and configures Chromium to avoid crashes when moving between desktops.

set -euo pipefail

info() { printf "\033[1;32m[INFO]\033[0m %s\n" "$*"; }
warn() { printf "\033[1;33m[WARN]\033[0m %s\n" "$*"; }
err()  { printf "\033[1;31m[ERR ]\033[0m %s\n" "$*" >&2; }

# 1) Install prerequisites and zsh
install_packages() {
  local pkgs=("zsh" "git" "curl")
  if command -v pacman >/dev/null 2>&1; then
    info "Detected Arch/Omarchy. Installing packages with pacman."
    sudo pacman -Sy --needed --noconfirm "${pkgs[@]}"
  elif command -v apt-get >/dev/null 2>&1; then
    info "Detected Debian/Ubuntu. Installing packages with apt."
    sudo apt-get update -y
    sudo apt-get install -y "${pkgs[@]}"
  elif command -v dnf >/dev/null 2>&1; then
    info "Detected Fedora. Installing packages with dnf."
    sudo dnf install -y "${pkgs[@]}"
  elif command -v zypper >/dev/null 2>&1; then
    info "Detected openSUSE. Installing packages with zypper."
    sudo zypper install -y "${pkgs[@]}"
  else
    warn "Could not detect a known package manager. Ensure zsh, git, and curl are installed."
  fi
}

# 2) Install Oh My Zsh (non-interactive)
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

# 3) Ensure a base .zshrc exists and back it up
ensure_zshrc() {
  if [ -f "${HOME}/.zshrc" ]; then
    cp -a "${HOME}/.zshrc" "${HOME}/.zshrc.pre-omz-$(date +%Y%m%d%H%M%S).bak"
    info "Backed up existing .zshrc"
  else
    cp "${HOME}/.oh-my-zsh/templates/zshrc.zsh-template" "${HOME}/.zshrc"
    info "Created new .zshrc from template"
  fi
}

# 4) Install plugins into $ZSH_CUSTOM
install_plugins() {
  local ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
  mkdir -p "${ZSH_CUSTOM}/plugins"

  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-autosuggestions" ]; then
    info "Installing zsh-autosuggestions plugin."
    git clone https://github.com/zsh-users/zsh-autosuggestions "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
  else
    info "zsh-autosuggestions already present."
  fi

  if [ ! -d "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting" ]; then
    info "Installing zsh-syntax-highlighting plugin."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
  else
    info "zsh-syntax-highlighting already present."
  fi
}

# 5) Edit .zshrc: theme and plugins
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

# 6) Change default shell to zsh
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

# 7) Configure Chromium to avoid workspace-move crashes
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
  info "Cleaning Chromium caches and singletons."
  killall -9 chromium chrome 2>/dev/null || true
  rm -f "${HOME}/.config/chromium/Singleton"* 2>/dev/null || true
  rm -rf "${HOME}/.config/chromium/GPUCache" "${HOME}/.config/chromium/ShaderCache" 2>/dev/null || true

  info "Chromium configured. Log out and back in once so GUI PATH takes effect."
}

# 8) Install Visual Studio Code (Microsoft build) + Vim keybindings
install_vscode_with_vim() {
  if ! command -v pacman >/dev/null 2>&1; then
    warn "Not an Arch/Omarchy system. Skipping VS Code install."
    return 0
  fi

  # Ensure yay exists (install yay-bin from AUR if needed)
  if ! command -v yay >/dev/null 2>&1; then
    info "yay not found. Installing yay-bin from AUR."
    sudo pacman -Sy --needed --noconfirm base-devel git || {
      err "Failed to install base-devel/git needed for AUR builds."
      return 1
    }
    local _tmp
    _tmp="$(mktemp -d)"
    pushd "$_tmp" >/dev/null
    git clone https://aur.archlinux.org/yay-bin.git
    pushd yay-bin >/dev/null
    makepkg -si --noconfirm
    popd >/dev/null
    popd >/dev/null
    rm -rf "$_tmp"
  fi

  info "Installing Visual Studio Code (visual-studio-code-bin) with yay."
  yay -S --noconfirm --needed visual-studio-code-bin || {
    err "Failed to install visual-studio-code-bin."
    return 1
  }

  # Install Vim keybindings extension
  if command -v code >/dev/null 2>&1; then
    info "Installing Vim keybindings extension for VS Code."
    # Official extension ID:
    #   Publisher: vscodevim, Extension name: vim  ->  "vscodevim.vim"
    code --install-extension vscodevim.vim --force || warn "Could not install vscodevim.vim extension."
  else
    warn "'code' CLI not found on PATH after install. You may need to re-login."
  fi
}

# Installs Python and LaTeX extensions for VS Code
install_vscode_extensions() {
  info "Installing VS Code extensions: Python Extension Pack and LaTeX Workshop..."

  # Determine which code binary to use (vscode, code, or codium)
  local code_bin=""
  for bin in code visual-studio-code codium vscodium; do
    if command -v "$bin" &>/dev/null; then
      code_bin="$bin"
      break
    fi
  done

  if [[ -z "$code_bin" ]]; then
    err "VS Code not found. Please install it first with install_vscode."
    return 1
  fi

  # Install extensions
  "$code_bin" --install-extension donjayamanne.python-extension-pack
  "$code_bin" --install-extension james-yu.latex-workshop

  info "VS Code extensions installed successfully."
}

# Creates or updates VS Code settings.json with Vim key handling config
setup_vscode_settings() {
  info "Configuring VS Code user settings..."

  local settings_dir="$HOME/.config/Code/User"
  local settings_file="$settings_dir/settings.json"

  mkdir -p "$settings_dir"

  # Desired JSON content
  local desired_content='{
    "vim.handleKeys": {
        "<C-c>": false,
        "<C-v>": false,
        "<C-a>": false,
        "<C-x>": false,
        "<C-p>": false,
        "<C-f>": false,
        "<C-z>": false
    },
    "keyboard.dispatch": "keyCode"
}'

  # If file doesn't exist, create it
  if [[ ! -f "$settings_file" ]]; then
    info "Creating new VS Code settings.json"
    echo "$desired_content" > "$settings_file"
    return 0
  fi

  # If file exists but missing our keys, merge them in
  if ! grep -q '"vim.handleKeys"' "$settings_file"; then
    warn "VS Code settings.json exists but missing vim.handleKeys; merging..."
    tmp_file="$(mktemp)"
    jq '. + {
      "vim.handleKeys": {
        "<C-c>": false,
        "<C-v>": false,
        "<C-a>": false,
        "<C-x>": false,
        "<C-p>": false,
        "<C-f>": false,
        "<C-z>": false
      },
      "keyboard.dispatch": "keyCode"
    }' "$settings_file" > "$tmp_file" && mv "$tmp_file" "$settings_file"
  else
    info "VS Code settings.json already contains vim.handleKeys — no changes made."
  fi
}

# 9) Install uv (Rust-based Python package manager)
install_uv() {
  info "Installing uv (Python package manager)."

  # Prefer pacman/yay for Arch/Omarchy
  if command -v pacman >/dev/null 2>&1; then
    if command -v yay >/dev/null 2>&1; then
      yay -S --noconfirm --needed uv || true
    else
      sudo pacman -Sy --needed --noconfirm uv || {
        warn "uv not in official repos; installing via curl fallback."
        curl -LsSf https://astral.sh/uv/install.sh | sh
      }
    fi
  # Fallback for other distros (Fedora, Ubuntu, etc.)
  elif command -v dnf >/dev/null 2>&1; then
    if ! sudo dnf install -y uv 2>/dev/null; then
      warn "uv not in Fedora repos; using official install script."
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    if ! sudo apt-get install -y uv 2>/dev/null; then
      warn "uv not in Debian/Ubuntu repos; using official install script."
      curl -LsSf https://astral.sh/uv/install.sh | sh
    fi
  else
    warn "Unknown distro. Installing uv using official script."
    curl -LsSf https://astral.sh/uv/install.sh | sh
  fi

  # Ensure uv is on PATH for GUI and CLI
  mkdir -p "${HOME}/.config/environment.d"
  cat > "${HOME}/.config/environment.d/uv-path.conf" <<'EOF'
PATH=$HOME/.cargo/bin:$PATH
EOF
  systemctl --user import-environment PATH || true

  if command -v uv >/dev/null 2>&1; then
    info "uv installed successfully: $(uv --version)"
  else
    warn "uv installation may require re-login to update PATH."
  fi
}

# Installs TeX Live from official Arch repositories (recommended)
install_texlive() {
  info "Installing TeX Live from official Arch repositories..."

  # Check for yay or fall back to pacman
  local pkgmgr="pacman"
  if command -v yay &>/dev/null; then
    pkgmgr="yay"
  fi

  # Install TeX Live split packages from official repos
  sudo "$pkgmgr" -Syu --needed --noconfirm \
    texlive-basic texlive-latex texlive-latexrecommended texlive-latexextra \
    texlive-bibtexextra texlive-fontsrecommended texlive-pictures \
    texlive-bin texlive-binextra dvisvgm

  # Verify binaries
  if command -v pdflatex &>/dev/null && command -v latexmk &>/dev/null; then
    info "TeX Live installation complete and binaries are in PATH."
  else
    warn "TeX Live installed, but binaries not found in PATH."
    warn "You may need to log out and back in, or add /usr/bin explicitly to PATH."
  fi
}

install_packages_from_list() {
  local repo_dir="$HOME/repos/omarchy-setup"
  local list_file="$repo_dir/packages.list"

  info "Installing packages from $list_file"

  if [[ ! -f "$list_file" ]]; then
    warn "No packages.list found at $list_file"
    return 0
  fi

  # Read list, ignore blanks and comments
  mapfile -t all_pkgs < <(sed -e 's/#.*$//' -e '/^\s*$/d' "$list_file")

  if [[ ${#all_pkgs[@]} -eq 0 ]]; then
    info "No packages listed. Skipping."
    return 0
  fi

  if [[ ${#all_pkgs[@]} -gt 0 ]]; then
    info "Installing packages: ${all_pkgs[*]}"
    yay -S --needed --noconfirm "${all_pkgs[@]}"
  fi
}

main() {
  install_packages
  install_oh_my_zsh
  ensure_zshrc
  install_plugins
  configure_zshrc
  make_default_shell
  setup_chromium_workspace_fix
  install_vscode_with_vim
  install_vscode_extensions
  setup_vscode_settings
  install_uv
  install_packages_from_list
  install_texlive
  info "All done."
}

main "$@"

