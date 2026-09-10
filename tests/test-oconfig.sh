#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$ROOT/bin/oconfig"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

export HOME="$WORKDIR/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_DATA_HOME="$HOME/.local/share"
export OMARCHY_PATH="$WORKDIR/omarchy"
mkdir -p "$HOME/.config/hypr" "$HOME/.config/omarchy" "$HOME/.config/chromium/Default" \
  "$OMARCHY_PATH/config/hypr" "$OMARCHY_PATH/config/omarchy" "$OMARCHY_PATH/config/chromium/Default"

echo 'stock bindings' > "$OMARCHY_PATH/config/hypr/bindings.lua"
echo 'stock hyprland' > "$OMARCHY_PATH/config/hypr/hyprland.lua"
echo 'stock monitors' > "$OMARCHY_PATH/config/hypr/monitors.lua"
echo '{"bar":{}}' > "$OMARCHY_PATH/config/omarchy/shell.json"
echo '{}' > "$OMARCHY_PATH/config/chromium/Default/Preferences"
cp "$OMARCHY_PATH/config/hypr/bindings.lua" "$HOME/.config/hypr/bindings.lua"
cp "$OMARCHY_PATH/config/hypr/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
cp "$OMARCHY_PATH/config/hypr/monitors.lua" "$HOME/.config/hypr/monitors.lua"

echo 'my bindings' > "$HOME/.config/hypr/bindings.lua"
echo 'hdmi layout' > "$HOME/.config/hypr/monitors.lua"
echo '{"version":1}' > "$HOME/.config/omarchy/shell.json"
echo 'cookies-and-secrets' > "$HOME/.config/chromium/Default/Preferences"

fail() { echo "FAIL: $*" >&2; exit 1; }

"$CLI" init >/dev/null
"$CLI" status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["initialized"]'

check="$("$CLI" check)"
echo "$check" | grep -q '.config/hypr/bindings.lua' || fail "check missed bindings.lua"
echo "$check" | grep -q '.config/omarchy/shell.json' || fail "check missed shell.json"
echo "$check" | grep -q monitors.lua && fail "check listed ignored monitors.lua"
echo "$check" | grep -q chromium && fail "check listed chromium profile"

"$CLI" save >/dev/null
"$CLI" check | grep -q 'no untracked' || fail "check not clean after save"

repo="$(python3 -c 'import json,os; print(json.load(open(os.path.expanduser("~/.config/oconfig/config.json")))["repo"])')"
[[ -f "$repo/.config/hypr/bindings.lua" ]] || fail "store missing bindings.lua"
[[ -f "$repo/.config/hypr/monitors.lua" ]] && fail "store adopted monitors.lua"

echo 'stock bindings' > "$HOME/.config/hypr/bindings.lua"
"$CLI" restore >/dev/null
grep -q 'my bindings' "$HOME/.config/hypr/bindings.lua" || fail "restore did not write bindings.lua"
[[ -L "$HOME/.config/hypr/bindings.lua" ]] && fail "restore left a symlink"

echo "ok  tests passed"
