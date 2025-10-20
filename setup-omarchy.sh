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

  info "Reverting old Omarchy Chromium workspace setup."

  # Clean up any previous configuration
  rm -f \
    "${HOME}/.local/share/omarchy/bin/chromium-stable" \
    "${HOME}/.config/chromium-flags.conf" \
    "${HOME}/.config/environment.d/omarchy-path.conf" \
    "${HOME}/.local/share/applications/chromium.desktop" 2>/dev/null || true
  systemctl --user import-environment PATH || true

  info "Configuring Chromium workspace crash fix (Wayland flag)."

  # a) Wrapper with the new working flag
  mkdir -p "${HOME}/.local/share/omarchy/bin"
  cat > "${HOME}/.local/share/omarchy/bin/chromium-stable" <<'EOF'
#!/usr/bin/env bash
exec chromium \
  --disable-features=WaylandWpColorManagerV1 \
  "$@"
EOF
  chmod +x "${HOME}/.local/share/omarchy/bin/chromium-stable"

  # b) Add wrapper path to environment
  mkdir -p "${HOME}/.config/environment.d"
  cat > "${HOME}/.config/environment.d/omarchy-path.conf" <<'EOF'
PATH=$HOME/.local/share/omarchy/bin:$PATH
EOF
  systemctl --user import-environment PATH || true

  # c) Chromium global flags file (optional persistence)
  mkdir -p "${HOME}/.config"
  cat > "${HOME}/.config/chromium-flags.conf" <<'EOF'
--disable-features=WaylandWpColorManagerV1
EOF

  # d) Override desktop launcher to use our wrapper
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

  # e) Patch Omarchy webapp launcher if it exists
  if [ -f "${HOME}/.local/share/omarchy/bin/omarchy-launch-webapp" ]; then
    mkdir -p "${HOME}/.local/share/omarchy/logs"
    sed -i "s|^\s*exec\s*chromium|exec ${HOME}/.local/share/omarchy/bin/chromium-stable --enable-logging=stderr --v=1 2>>${HOME}/.local/share/omarchy/logs/chromium.log|" \
      "${HOME}/.local/share/omarchy/bin/omarchy-launch-webapp" || true
  else
    warn "omarchy-launch-webapp not found. Skipping webapp launcher patch."
  fi

  info "Chromium Wayland workspace fix applied. Log out and back in for PATH changes to take effect."
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

remap_capslock_to_escape_in_user_input_conf() {
  info "Setting Caps Lock → Escape in ~/.config/hypr/input.conf"

  local user_conf="$HOME/.config/hypr/input.conf"
  local modified=false

  mkdir -p "$(dirname "$user_conf")"

  if [[ -f "$user_conf" ]]; then
    # If already set correctly, skip
    if grep -qE '^\s*kb_options\s*=\s*caps:escape' "$user_conf"; then
      info "Caps Lock already remapped to Escape. No changes needed."
      return
    fi

    # Replace existing kb_options line, or append inside input block
    if grep -qE '^\s*kb_options\s*=' "$user_conf"; then
      sed -i 's/^\s*kb_options\s*=.*/    kb_options = caps:escape/' "$user_conf"
    else
      awk '
        /^input\s*\{/ { print; print "    kb_options = caps:escape"; next }
        { print }
      ' "$user_conf" > "${user_conf}.tmp" && mv "${user_conf}.tmp" "$user_conf"
    fi
    modified=true
  else
    cat > "$user_conf" <<'EOF'
input {
    kb_options = caps:escape
}
EOF
    modified=true
  fi

  if [[ "$modified" == true ]]; then
    info "Updated $user_conf to remap Caps Lock → Escape."
    warn "Reload Hyprland manually with: hyprctl reload  — or log out/in for this to take effect."
  else
    info "No modifications required."
  fi
}

set_looknfeel_gaps() {
  local conf="$HOME/.config/hypr/looknfeel.conf"
  [[ -f "$conf" ]] || { echo "[ERR] $conf not found"; return 1; }

  cp -a "$conf" "${conf}.bak"

  # Substitute commented gap lines to active =2 versions
  sed -i \
    -e 's/^[[:space:]]*#*[[:space:]]*gaps_in.*/    gaps_in = 2/' \
    -e 's/^[[:space:]]*#*[[:space:]]*gaps_out.*/    gaps_out = 2/' \
    "$conf"

  echo "[OK] Updated $conf (backup at ${conf}.bak)"
}

# set_plymouth_theme_bgrt() {
#   local current_theme
#   current_theme="$(sudo plymouth-set-default-theme 2>/dev/null || echo unknown)"

#   if [[ "$current_theme" == "bgrt" ]]; then
#     echo "[INFO] Plymouth theme is already set to 'bgrt'. Nothing to do."
#     return 0
#   fi

#   echo "[INFO] Changing Plymouth theme from '$current_theme' to 'bgrt'..."
#   sudo plymouth-set-default-theme bgrt
#   echo "[INFO] Rebuilding initramfs for Limine..."
#   sudo limine-mkinitcpio -P
#   echo "[INFO] Plymouth theme set to 'bgrt' and Limine initramfs rebuilt."
# }

ensure_no_hardware_cursor() {
  local config_file="$HOME/.config/hypr/hyprland.conf"

  # Create config if it doesn't exist
  [[ -f "$config_file" ]] || {
    mkdir -p "$(dirname "$config_file")"
    touch "$config_file"
  }

  # If the file already contains a cursor block with no_hardware_cursors=true, skip
  if awk '
    BEGIN { inside_cursor = 0 }
    /^\s*cursor\s*\{/ { inside_cursor = 1; next }
    /^\s*\}/ { inside_cursor = 0; next }
    inside_cursor && /^\s*no_hardware_cursors\s*=\s*true/ { found = 1 }
    END { exit !found }
  ' "$config_file"; then
    echo "[INFO] Cursor setting already present in $config_file"
  else
    echo "[INFO] Adding cursor { no_hardware_cursors = true } to $config_file"
    printf "\n%s\n" "cursor {
    no_hardware_cursors = true
}" >>"$config_file"
  fi
}

sync_background() {
  local THEME="ristretto"
  local SRC="$HOME/repos/omarchy-setup/reference-files/wallpapers/Fantasy-Landscape3.png"
  local DEST_DIR="$HOME/.config/omarchy/themes/$THEME/backgrounds"
  local TARGET_BASENAME
  local TARGET

  TARGET_BASENAME="$(basename "$SRC")"
  TARGET="$DEST_DIR/$TARGET_BASENAME"

  # Sanity check
  if [[ ! -f "$SRC" ]]; then
    printf "\033[1;31m[ERR ]\033[0m Source image not found: %s\n" "$SRC" >&2
    return 1
  fi

  # Ensure destination directory exists
  mkdir -p "$DEST_DIR"

  # Copy only if different or missing
  if [[ -f "$TARGET" ]]; then
    if cmp -s "$SRC" "$TARGET"; then
      printf "\033[1;32m[INFO]\033[0m Target already up to date: %s\n" "$TARGET"
    else
      cp -f -- "$SRC" "$TARGET"
      printf "\033[1;32m[INFO]\033[0m Updated background: %s\n" "$TARGET"
    fi
  else
    cp -f -- "$SRC" "$TARGET"
    printf "\033[1;32m[INFO]\033[0m Installed background: %s\n" "$TARGET"
  fi

  # Remove all other PNG and JPG files in the destination directory
  shopt -s nullglob nocaseglob
  local f removed_any=false
  for f in "$DEST_DIR"/*.{png,jpg,jpeg}; do
    [[ "$(basename "$f")" == "$TARGET_BASENAME" ]] && continue
    rm -f -- "$f"
    removed_any=true
    printf "\033[1;33m[WARN]\033[0m Removed extra image: %s\n" "$f"
  done
  shopt -u nullglob nocaseglob

  if [[ "$removed_any" == false ]]; then
    printf "\033[1;32m[INFO]\033[0m No extra PNG/JPGs to remove in %s\n" "$DEST_DIR"
  fi

  omarchy-theme-set "$THEME"
}

install_omarchy_screensaver() {
  local src="${HOME}/repos/omarchy-setup/reference-files/screensaver.txt"
  local dest="${HOME}/.config/omarchy/branding/screensaver.txt"

  info "Installing Omarchy screensaver text..."

  if [[ ! -f "$src" ]]; then
    warn "Source file not found: $src"
    return 1
  fi

  mkdir -p "$(dirname "$dest")"

  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    info "Screensaver already up to date."
  else
    if [[ -f "$dest" ]]; then
      cp "$dest" "${dest}.bak.$(date +%Y%m%d-%H%M%S)"
      info "Backed up existing screensaver.txt"
    fi
    cp "$src" "$dest"
    info "Installed new screensaver.txt"
  fi
}

install_omarchy_splash_logo() {
  local src="${HOME}/repos/omarchy-setup/reference-files/logo.png"
  local dest="/usr/share/plymouth/themes/omarchy/logo.png"

  info "Installing Omarchy splash logo..."

  if [[ ! -f "$src" ]]; then
    warn "Source file not found: $src"
    return 1
  fi

  if [[ -f "$dest" ]] && sudo cmp -s "$src" "$dest"; then
    info "Logo already up to date."
  else
    if [[ -f "$dest" ]]; then
      sudo cp "$dest" "${dest}.bak.$(date +%Y%m%d-%H%M%S)"
      info "Backed up existing logo.png"
    fi
    sudo cp "$src" "$dest"
    sudo plymouth-set-default-theme omarchy
    info "Installed new logo.png rebuilding initramfs"
    sudo limine-mkinitcpio -P
    #sudo mkinitcpio -P
    info "Installed new logo.png."
  fi
}

setup_tmux_tpm() {
  local tpm_dir="${HOME}/.tmux/plugins/tpm"
  local tmux_conf_src="${HOME}/repos/omarchy-setup/reference-files/.tmux.conf"
  local tmux_conf_dest="${HOME}/.tmux.conf"

  info "Setting up tmux and TPM..."

  # Clone TPM only if it doesn’t already exist
  if [ ! -d "${tpm_dir}/.git" ]; then
    git clone https://github.com/tmux-plugins/tpm "${tpm_dir}"
  else
    (
      cd "${tpm_dir}" && git pull --ff-only >/dev/null 2>&1
    )
  fi

  # Copy tmux.conf if it differs
  if ! cmp -s "${tmux_conf_src}" "${tmux_conf_dest}"; then
    cp "${tmux_conf_src}" "${tmux_conf_dest}"
    info "Updated ~/.tmux.conf from reference-files."
  else
    info "~/.tmux.conf is already up to date."
  fi
}
setup_snapper_system_backups() {
  set -Eeuo pipefail
  trap 'echo "[ERROR] snapper setup failed at line $LINENO: $BASH_COMMAND" >&2' ERR

  log()  { printf "[INFO] %s\n" "$*"; }
  warn() { printf "[WARN] %s\n" "$*" >&2; }

  INVOKER="${SUDO_USER:-${USER:-root}}"

  log "Preflight: ensure snapper present and root is Btrfs"
  command -v snapper >/dev/null 2>&1 || sudo pacman -S --noconfirm --needed snapper
  findmnt -n -o FSTYPE / | grep -q btrfs || { warn "Root is not Btrfs; skipping."; return 0; }

  log "Ensure /.snapshots & snapper config"
  sudo mkdir -p /etc/snapper/configs

  # Normalize /.snapshots into a good state for snapper
  EXISTING_IS_SUBVOL=false
  if mountpoint -q /.snapshots; then
    sudo umount /.snapshots || true
  fi
  if sudo btrfs subvolume show /.snapshots >/dev/null 2>&1; then
    # It's already a btrfs subvolume (good). We'll keep it and just write the config.
    EXISTING_IS_SUBVOL=true
  elif [ -d /.snapshots ]; then
    # Not a subvol; directory may block create-config
    if [ -z "$(sudo ls -A /.snapshots 2>/dev/null)" ]; then
      sudo rmdir /.snapshots
    else
      TS="$(date +%s)"
      warn "/.snapshots exists and is not empty; moving to /.snapshots.pre-snapper.${TS}"
      sudo mv /.snapshots "/.snapshots.pre-snapper.${TS}"
    fi
  fi

  # Create config if missing. If subvolume already exists, snapper create-config would fail,
  # so in that case we skip it and write the config file by hand.
  if [ ! -f /etc/snapper/configs/root ]; then
    if [ "${EXISTING_IS_SUBVOL}" = false ]; then
      # Only safe to call when /.snapshots does not exist
      sudo snapper -c root create-config /
    fi
  fi

  log "Write snapper policy (7 daily, excludes, allow current user)"
  sudo tee /etc/snapper/configs/root >/dev/null <<EOF
SUBVOLUME="/"
FSTYPE="btrfs"
ALLOW_USERS="${INVOKER}"
SYNC_ACL="no"

# Timeline: keep 7 daily snapshots
TIMELINE_CREATE="yes"
TIMELINE_CLEANUP="yes"
TIMELINE_MIN_AGE="1800"
TIMELINE_LIMIT_HOURLY="0"
TIMELINE_LIMIT_DAILY="7"
TIMELINE_LIMIT_WEEKLY="0"
TIMELINE_LIMIT_MONTHLY="0"
TIMELINE_LIMIT_YEARLY="0"

# Exclude dev tiers and transient files
EXCLUDE="/opt/models-dev /var/lib/docker-dev /home/${INVOKER}/Downloads"
EOF
  sudo chown root:root /etc/snapper/configs/root
  sudo chmod 600 /etc/snapper/configs/root

  log "Register config for Arch timers (/etc/conf.d/snapper)"
  echo 'SNAPPER_CONFIGS="root"' | sudo tee /etc/conf.d/snapper >/dev/null

  log "Mount /.snapshots via fstab (subvol=@snapshots)"
  ROOT_SRC="$(findmnt -n -o SOURCE / || true)"
  SNAP_UUID="$( [ -n "$ROOT_SRC" ] && blkid -o value -s UUID "$ROOT_SRC" || echo )"
  sudo mkdir -p /.snapshots
  if [ -n "$SNAP_UUID" ] && ! grep -qE '^[^#].*\s/\.snapshots\s+btrfs\s+.*subvol=@snapshots' /etc/fstab; then
    echo "UUID=${SNAP_UUID} /.snapshots btrfs subvol=@snapshots,defaults,noatime 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi
  sudo mount -a || true

  log "Enable timers and ensure missed runs happen on boot (Persistent=true)"
  sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer || true
  sudo mkdir -p /etc/systemd/system/snapper-timeline.timer.d
  printf "[Timer]\nPersistent=true\n" | sudo tee /etc/systemd/system/snapper-timeline.timer.d/override.conf >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart snapper-timeline.timer snapper-cleanup.timer || true

  log "Create prod/dev subvolumes for models and docker (idempotent)"
  sudo mkdir -p /opt/models-prod /opt/models-dev /var/lib/docker-prod /var/lib/docker-dev
  sudo btrfs subvolume create /opt/models-prod 2>/dev/null || true
  sudo btrfs subvolume create /opt/models-dev  2>/dev/null || true
  sudo systemctl stop docker 2>/dev/null || true
  sudo btrfs subvolume create /var/lib/docker-prod 2>/dev/null || true
  sudo btrfs subvolume create /var/lib/docker-dev  2>/dev/null || true

  ensure_fstab_entry() {
    local subvol="$1" mountpoint="$2"
    [ -z "${SNAP_UUID:-}" ] && return 0
    if ! grep -qE "^[^#].*\\s${mountpoint//\//\\/}\\s+btrfs\\s+.*subvol=@${subvol}\\b" /etc/fstab; then
      echo "UUID=${SNAP_UUID} ${mountpoint} btrfs subvol=@${subvol},defaults,noatime 0 0" | sudo tee -a /etc/fstab >/dev/null
    fi
    sudo mkdir -p "$mountpoint"
  }
  ensure_fstab_entry "models-prod"   "/opt/models-prod"
  ensure_fstab_entry "models-dev"    "/opt/models-dev"
  ensure_fstab_entry "docker-prod"   "/var/lib/docker-prod"
  ensure_fstab_entry "docker-dev"    "/var/lib/docker-dev"
  sudo mount -a || true
  sudo systemctl start docker 2>/dev/null || true

  log "Install helper in /usr/local/bin (captures yay/paru/pacman command)"
  sudo install -d -m 0755 /usr/local/bin
  sudo tee /usr/local/bin/omarchy-snapper-hook >/dev/null <<'EOS'
#!/bin/sh
set -eu
PHASE="${1:-pre}"

normalize_cmd() {
  printf '%s\n' "$1" | sed 's/[[:space:]]\{1,\}/ /g; s|.*/\(yay\|paru\|pacman\)|\1|'
}
find_invoker_cmd() {
  pid="$PPID"; i=0; pacman_cmd=""
  while [ "$pid" -gt 1 ] 2>/dev/null && [ $i -lt 20 ]; do
    raw="$(tr '\0' ' ' </proc/"$pid"/cmdline 2>/dev/null || true)"
    [ -z "$raw" ] && raw="$(cat /proc/"$pid"/comm 2>/dev/null || true)"
    [ -z "$raw" ] && break
    base="$(printf '%s\n' "$raw" | awk '{print $1}' | sed 's|.*/||')"
    case "$base" in
      yay|paru) normalize_cmd "$raw"; return 0 ;;
      pacman)   pacman_cmd="$(normalize_cmd "$raw")" ;;
    esac
    pid="$(awk '{print $4}' /proc/"$pid"/stat 2>/dev/null || echo 1)"
    i=$((i+1))
  done
  [ -n "$pacman_cmd" ] && { printf '%s\n' "$pacman_cmd"; exit 0; }
  printf '%s\n' "pacman transaction"
}
CMD="$(find_invoker_cmd)"
exec /usr/bin/snapper --config root create --description "${PHASE} ${CMD}"
EOS
  sudo chmod 755 /usr/local/bin/omarchy-snapper-hook

  log "Write pacman hooks (pre/post) that call the helper"
  sudo mkdir -p /etc/pacman.d/hooks
  sudo tee /etc/pacman.d/hooks/50-pre-btrfs-snapper.hook >/dev/null <<'EOS'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Creating pre pacman snapshot...
When = PreTransaction
Exec = /usr/local/bin/omarchy-snapper-hook pre
EOS

  sudo tee /etc/pacman.d/hooks/60-post-btrfs-snapper.hook >/dev/null <<'EOS'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Creating post pacman snapshot...
When = PostTransaction
Exec = /usr/local/bin/omarchy-snapper-hook post
EOS
  sudo chmod 644 /etc/pacman.d/hooks/*-btrfs-snapper.hook

  log "Kick timeline once and create a test snapshot"
  sudo systemctl start snapper-timeline.service || true
  sudo snapper -c root create --description "omarchy setup test" || true
  sudo snapper list-configs || true
  sudo snapper -c root list | tail -n 5 || true

  log "Snapper system backups configured."
}

update_ghostty_font_size() {
  local config="$HOME/.config/ghostty/config"
  local target_size=12

  # Ensure config exists
  if [[ ! -f "$config" ]]; then
    echo "Error: Ghostty config not found at $config"
    return 1
  fi

  # Check current value
  local current_size
  current_size=$(grep -E '^font-size[[:space:]]*=' "$config" | awk -F= '{print $2}' | xargs)

  # If the size is already correct, do nothing
  if [[ "$current_size" == "$target_size" ]]; then
    echo "Font size already set to $target_size"
    return 0
  fi

  # Make a backup before modifying
  cp "$config" "${config}.bak.$(date +%Y%m%d%H%M%S)"

  # Replace or append the font-size setting
  if grep -qE '^font-size[[:space:]]*=' "$config"; then
    sed -i "s/^font-size[[:space:]]*=.*/font-size = $target_size/" "$config"
  else
    echo "font-size = $target_size" >> "$config"
  fi

  echo "Updated Ghostty font size to $target_size"
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
  # To install more packages run: "sudo informant read --all"
  yay -S --needed --noconfirm informant

  setup_tmux_tpm
 #git  clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
 # cp ${HOME}/repos/omarchy-setup/reference-files/.tmux.conf ~/.tmux.conf

  systemctl --user enable --now pipewire.service pipewire-pulse.service wireplumber.service
  systemctl --user enable --now sunshine.service
  sudo systemctl enable --now sshd.service
  ensure_no_hardware_cursor
  remap_capslock_to_escape_in_user_input_conf
  set_looknfeel_gaps
  install_omarchy_screensaver
  install_omarchy_splash_logo
  sync_background
  update_ghostty_font_size
  setup_snapper_system_backups
  #set_plymouth_theme_bgrt
  info "All done."
}

main "$@"

