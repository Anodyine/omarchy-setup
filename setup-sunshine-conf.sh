#!/usr/bin/env bash
set -euo pipefail

CONF="${HOME}/.config/sunshine/sunshine.conf"
mkdir -p "$(dirname "$CONF")"
[[ -f "$CONF" ]] || : >"$CONF"

# 1) Collect all *connected* DRM connectors
mapfile -t CONNECTED < <(
  for st in /sys/class/drm/card*-*/status; do
    [[ -f "$st" ]] && grep -qx connected "$st" && dirname "$st"
  done
)

if ((${#CONNECTED[@]}==0)); then
  echo "No connected DRM connectors found." >&2
  exit 1
fi

# 2) Pick the first connected monitor by preference: HDMI -> DP -> DVI -> eDP -> anything
pick_conn=""
for pat in "HDMI-A-" "DP-" "DVI-" "eDP-" ""; do
  for d in "${CONNECTED[@]}"; do
    base="$(basename "$d")"   # e.g. card3-HDMI-A-3
    if [[ -z "$pat" || "$base" == *"$pat"* ]]; then
      pick_conn="$base"
      break 2
    fi
  done
done

CARD="${pick_conn%%-*}"       # e.g. card3
CONN="${pick_conn#*-}"        # e.g. HDMI-A-3 (informational)

KMS_DEV="/dev/dri/${CARD}"    # e.g. /dev/dri/card3

# 3) Map card -> its first render node (/dev/dri/renderD###)
RNODE_BN="$(readlink -f /sys/class/drm/${CARD}/device/drm/renderD* 2>/dev/null | head -n1 | xargs -r basename || true)"
if [[ -z "${RNODE_BN}" ]]; then
  echo "No render node found for ${CARD}" >&2
  exit 1
fi
RNODE="/dev/dri/${RNODE_BN}"  # e.g. /dev/dri/renderD130

# 4) Update sunshine.conf (idempotent)
awk -v cap="capture = kms" \
    -v enc="encoder = nvenc" \
    -v ada="adapter_name = ${RNODE}" \
    -v kmsdev="kms_device = ${KMS_DEV}" '
BEGIN{fc=fe=fa=fk=0}
{
  if ($0 ~ /^[[:space:]]*capture[[:space:]]*=/)         {$0=cap;    fc=1}
  else if ($0 ~ /^[[:space:]]*encoder[[:space:]]*=/)    {$0=enc;    fe=1}
  else if ($0 ~ /^[[:space:]]*adapter_name[[:space:]]*=/){$0=ada;    fa=1}
  else if ($0 ~ /^[[:space:]]*kms_device[[:space:]]*=/) {$0=kmsdev; fk=1}
  print
}
END{
  if (!fc) print cap
  if (!fe) print enc
  if (!fa) print ada
  if (!fk) print kmsdev
}' "$CONF" >"$CONF.tmp" && mv "$CONF.tmp" "$CONF"

echo "Bound Sunshine to:"
echo "  Monitor:   ${CONN}"
echo "  DRM card:  ${KMS_DEV}"
echo "  Render:    ${RNODE}"
echo "Updated ${CONF}"

# 5) Restart Sunshine (user service)
systemctl --user restart sunshine
echo "Sunshine restarted."
