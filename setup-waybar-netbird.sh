#!/usr/bin/env bash
set -euo pipefail

# Paths
CFG="$HOME/.config/waybar/config.jsonc"
CSS="$HOME/.config/waybar/style.css"
BIN="$HOME/.local/bin"
WRAP="$BIN/waybar-netbird"
NBUP="$BIN/nb-up"
NBDOWN="$BIN/nb-down"

# Colors (for echo)
ok()  { printf "\033[1;32m[ok]\033[0m %s\n" "$*"; }
doit(){ printf "\033[1;34m[do]\033[0m %s\n" "$*"; }
warn(){ printf "\033[1;33m[!!]\033[0m %s\n" "$*"; }

mkdir -p "$BIN" "$HOME/.config/waybar"

############################################
# 1) Wrapper that outputs JSON for Waybar  #
############################################
doit "Install/update $WRAP"
cat > "$WRAP" <<'EOF'
#!/usr/bin/env bash
# Always output JSON Waybar understands.
# We check for "Signal: Connected" to avoid false positives like "0/0 Connected".
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

NB="$(command -v netbird || true)"
if [[ -z "$NB" ]]; then
  echo '{"text":"󰌿","class":"disconnected"}'
  exit 0
fi

if "$NB" status 2>/dev/null | grep -q 'Signal: Connected'; then
  echo '{"text":"󰌾","class":"connected"}'
else
  echo '{"text":"󰌿","class":"disconnected"}'
fi
EOF
chmod +x "$WRAP"
ok "Wrapper ready"

############################################
# 2) nb-up / nb-down helpers (signal 5)    #
############################################
doit "Install/update $NBUP and $NBDOWN to refresh Waybar immediately"
cat > "$NBUP" <<'EOF'
#!/usr/bin/env bash
netbird up "$@"
pkill -RTMIN+5 waybar 2>/dev/null || true
EOF
chmod +x "$NBUP"

cat > "$NBDOWN" <<'EOF'
#!/usr/bin/env bash
netbird down "$@"
pkill -RTMIN+5 waybar 2>/dev/null || true
EOF
chmod +x "$NBDOWN"
ok "Helpers ready"

############################################
# 3) Safe backup of config.jsonc (once)    #
############################################
if [[ -f "$CFG" && ! -f "$CFG.bak_netbird" ]]; then
  cp -a "$CFG" "$CFG.bak_netbird"
  ok "Backed up config to $CFG.bak_netbird"
fi
if [[ ! -f "$CFG" ]]; then
  doit "Create initial Waybar config at $CFG"
  cat > "$CFG" <<'JSON'
{
  "layer": "top",
  "position": "top",
  "modules-right": ["clock"]
}
JSON
fi

############################################
# 4) Insert or update tagged module block  #
############################################
MODULE_BEGIN='// BEGIN NETBIRD MODULE (managed)'
MODULE_END='// END NETBIRD MODULE (managed)'

MODULE_BLOCK=$(cat <<'JSON'
  // BEGIN NETBIRD MODULE (managed)
  "custom/netbird": {
    "exec": "~/.local/bin/waybar-netbird",
    "return-type": "json",
    "format": "{text}",
    "interval": 10,
    "signal": 5
  }
  // END NETBIRD MODULE (managed)
JSON
)

# If exists, replace; else append near end before final }
if grep -q "$MODULE_BEGIN" "$CFG"; then
  doit "Update existing NetBird module block in config"
  # Replace between markers
  awk -v RS= -v ORS= '
    {
      gsub(/\/\/ BEGIN NETBIRD MODULE \(managed\)[\s\S]*?\/\/ END NETBIRD MODULE \(managed\)/,
"  // BEGIN NETBIRD MODULE (managed)\n  \"custom/netbird\": {\n    \"exec\": \"~/.local/bin/waybar-netbird\",\n    \"return-type\": \"json\",\n    \"format\": \"{text}\",\n    \"interval\": 10,\n    \"signal\": 5\n  }\n  // END NETBIRD MODULE (managed)")
      print
    }' "$CFG" > "$CFG.tmp"
  mv "$CFG.tmp" "$CFG"
else
  doit "Insert NetBird module block into config"
  # Insert before last closing brace, with a preceding comma if needed
  # Ensure there is at least one newline before }
  awk -v block="$MODULE_BLOCK" '
    BEGIN{inserted=0}
    {
      if (!inserted && $0 ~ /}\s*$/) {
        # Try to see if the object already had trailing comma
        # Add comma if previous char before } is not { or , 
        # We’ll more simply ensure there is a comma above if needed later.
        # Safer approach: inject with a comma if the previous non-space line ends with }
        print ",";
        print block;
        inserted=1
      }
      print $0
    }
    END{ if(!inserted) print block }' "$CFG" > "$CFG.tmp"
  # Fix possible double commas and trailing commas with simple passes
  sed -i 's/,\s*,/,/g' "$CFG.tmp"
  # Remove comma that could appear right before the closing brace (rare)
  sed -i 's/,\s*}$/\n}/' "$CFG.tmp"
  mv "$CFG.tmp" "$CFG"
fi
ok "Module block ensured"

############################################
# 5) Ensure it’s listed in modules-right   #
############################################
if grep -q '"modules-right"' "$CFG"; then
  if grep -q '"modules-right".*custom/netbird' "$CFG"; then
    ok "modules-right already contains custom/netbird"
  else
    doit "Add custom/netbird to beginning of modules-right"
    # Insert right after the opening [ of the modules-right array
    awk '
      BEGIN{inmr=0}
      /"modules-right"\s*:/ {inmr=1}
      {
        if (inmr && /\[/) {
          # After the opening bracket, insert the entry (with comma if not empty)
          sub(/\[/, "[ \"custom\\/netbird\",")
          inmr=0
        }
        print
      }' "$CFG" > "$CFG.tmp"
    mv "$CFG.tmp" "$CFG"
    ok "Inserted custom/netbird at beginning of modules-right"
  fi
else
  warn "No modules-right found; adding a default modules-right with custom/netbird"
  sed -i '1s|{|\{\n  "modules-right": ["custom/netbird"],|' "$CFG"
fi

############################################
# 6) Style: connected green, disconnected red
############################################
if [[ -f "$CSS" && ! -f "$CSS.bak_netbird" ]]; then
  cp -a "$CSS" "$CSS.bak_netbird"
  ok "Backed up CSS to $CSS.bak_netbird"
fi
touch "$CSS"

CSS_BEGIN='/* BEGIN NETBIRD STYLES (managed) */'
CSS_END='/* END NETBIRD STYLES (managed) */'

CSS_BLOCK=$(cat <<'EOF'
/* BEGIN NETBIRD STYLES (managed) */
#custom-netbird.connected {
  padding: 0 20px;
}
#custom-netbird.connected {
  color: #8ec07c;   /* green */
}
#custom-netbird.disconnected {
  color: #fb4934;   /* red */
}
/* END NETBIRD STYLES (managed) */
EOF
)

if grep -qF "$CSS_BEGIN" "$CSS"; then
  doit "Update NetBird CSS block"
  awk -v RS= -v ORS= '
    {
      gsub(/\/\* BEGIN NETBIRD STYLES \(managed\) \*\/[\s\S]*?\/\* END NETBIRD STYLES \(managed\) \*\//,
"#custom-netbird.connected {\n  color: #8ec07c;\n}\n#custom-netbird.disconnected {\n  color: #fb4934;\n}")
      print
    }' "$CSS" > "$CSS.tmp"
  # Re-wrap with markers
  awk -v block="$CSS_BLOCK" 'BEGIN{print block}' > "$CSS.header"
  cat "$CSS.tmp" > "$CSS.body"
  # Remove duplicates of the block markers (keep one block at the end)
  sed -i '/BEGIN NETBIRD STYLES (managed)/,/END NETBIRD STYLES (managed)/d' "$CSS.body"
  cat "$CSS.header" "$CSS.body" > "$CSS"
  rm -f "$CSS.tmp" "$CSS.header" "$CSS.body"
else
  doit "Append NetBird CSS block"
  printf "\n%s\n" "$CSS_BLOCK" >> "$CSS"
fi
ok "CSS ensured"

############################################
# 7) Reload Waybar
############################################
doit "Reload Waybar"
pkill -SIGUSR2 waybar 2>/dev/null || true
ok "Done. If nothing changed, the script left files as-is."
