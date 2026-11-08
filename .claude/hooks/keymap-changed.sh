#!/usr/bin/env bash
# PostToolUse hook (registered in .claude/settings.json).
# After an edit or shell command, redraw the keymap picture if config/corne.keymap (or the
# drawing config) changed, and ask Claude to bring the prose in CLAUDE.md / README.md in line.
# Changes are detected by content hash (scripts/draw-keymap.sh --check), so edits made with
# sed, by hand outside Claude, or by git are all picked up at the next tool call.
set -uo pipefail

cat >/dev/null # the tool payload is not needed

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}" || exit 0
draw=scripts/draw-keymap.sh
[[ -x "$draw" ]] || exit 0
"$draw" --check && exit 0

# Report a failing redraw once per input state instead of after every tool call.
failed_marker="${TMPDIR:-/tmp}/zmk-config-keymap-draw-failed-$("$draw" --hash 2>/dev/null)"
[[ -e "$failed_marker" ]] && exit 0

if out=$("$draw" 2>&1); then
  msg="config/corne.keymap changed, so keymap-drawer/corne.yaml and keymap-drawer/corne.svg were regenerated (README.md shows the SVG). If the change affects anything CLAUDE.md or README.md describe in prose (layer names and how each layer is reached, thumb keys, Bluetooth keys and their hold time, the tap-dance), update those files now, along with the hard-coded legends in raw_binding_map of keymap_drawer.config.yaml; otherwise nothing else is needed."
else
  touch "$failed_marker"
  msg="config/corne.keymap changed, but scripts/draw-keymap.sh failed, so keymap-drawer/* is stale. Fix the cause and run the script again. Output (tail):
$(tail -n 40 <<<"$out")"
fi

python3 -c 'import json, sys; print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": sys.argv[1]}}))' "$msg"
exit 0
