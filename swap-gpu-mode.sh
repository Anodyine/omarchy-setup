#!/usr/bin/env bash
# gpu-mode: switch EnvyControl mode and set VA-API driver accordingly
# Usage: gpu-mode integrated|nvidia|hybrid
set -euo pipefail

MODE="${1:-}"; [[ -z "$MODE" ]] && { echo "Usage: $(basename "$0") integrated|nvidia|hybrid" >&2; exit 2; }
case "$MODE" in integrated|nvidia|hybrid) ;; *) echo "Invalid mode: $MODE" >&2; exit 2;; esac

ENV_DIR="${HOME}/.config/environment.d"
ENV_FILE="${ENV_DIR}/10-gpu-vaapi.conf"

echo "[INFO] Switching GPU mode to: $MODE"
sudo envycontrol -s "$MODE"

ACTIVE="$(sudo envycontrol -q | awk '{print tolower($0)}')"
if [[ "$ACTIVE" != "$MODE" ]]; then
  echo "[ERROR] EnvyControl reports '$ACTIVE' (expected '$MODE'). Aborting." >&2
  exit 1
fi

mkdir -p "$ENV_DIR"

# Remove any current shell override first
unset LIBVA_DRIVER_NAME || true

case "$MODE" in
  integrated)
    # Alder Lake iGPU uses iHD
    printf 'LIBVA_DRIVER_NAME=iHD\n' > "$ENV_FILE"
    export LIBVA_DRIVER_NAME=iHD
    echo "[INFO] VA-API set to Intel iHD (user env + current shell)"
    ;;
  nvidia)
    printf 'LIBVA_DRIVER_NAME=nvidia\n' > "$ENV_FILE"
    export LIBVA_DRIVER_NAME=nvidia
    echo "[INFO] VA-API set to NVIDIA (user env + current shell)"
    ;;
  hybrid)
    # Let VA-API auto-select. Remove per-user override.
    [[ -f "$ENV_FILE" ]] && rm -f "$ENV_FILE"
    echo "[INFO] Removed per-user VA-API override for hybrid"
    # Nothing exported in current shell for hybrid
    ;;
esac

# Make new GUI apps pick it up
systemctl --user import-environment LIBVA_DRIVER_NAME || true

# Sanity hints
if [[ "$MODE" == "integrated" ]]; then
  if ! ldconfig -p 2>/dev/null | grep -q 'iHD_drv_video'; then
    echo "[WARN] intel-media-driver missing. Install: sudo pacman -S intel-media-driver libva-utils"
  fi
fi

# Warn if a system-wide override exists that could fight this
if grep -Rqs 'LIBVA_DRIVER_NAME' /etc/environment /etc/environment.d 2>/dev/null; then
  echo "[WARN] System-wide LIBVA_DRIVER_NAME detected under /etc. That can override per-user on login."
  echo "[WARN] Consider removing it from /etc/* if you want this script to fully control the setting."
fi

echo "[INFO] Done. Current mode: $ACTIVE"
echo "[HINT] Test: vainfo | grep -E 'Driver version|VAProfile(H264|HEVC)'"
