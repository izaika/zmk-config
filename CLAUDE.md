# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Personal [ZMK](https://zmk.dev) firmware config for a **Chocofi** split keyboard: 36 keys (5×3 + 3 thumbs per half), nice!nano v2 controllers, nice!view displays, macOS host. `README.md` is the human-facing description with the rendered keymap. It is not an altaFlow repo — the parent workspace `CLAUDE.md` conventions (Yarn/TypeScript tooling, Jira-keyed branches and commit scopes, PR/release flow, lint gates) don't apply here.

## Build and flash

Nothing builds locally (no west/Zephyr toolchain) and there are no tests or linters — the GitHub Actions build is the only check. `.github/workflows/build.yml` runs on every push to any branch, on PRs and on manual dispatch, and just calls ZMK's reusable `build-user-config.yml@main` with the matrix from `build.yaml`. A run takes ~5 min.

```bash
git push origin <branch>                       # triggers a build
gh workflow run build.yml --ref <branch>       # rebuild without a commit (e.g. to pick up newer ZMK)
gh run list --limit 5
gh run watch <run-id> --exit-status
gh run download <run-id> -n firmware -D <dir>  # use a dir outside the repo (there is no .gitignore)
```

The `firmware` artifact has one `.uf2` per `build.yaml` entry; the names contain spaces, so quote them:
- `corne_left nice_view_adapter nice_view-nice_nano__zmk-zmk.uf2`
- `corne_right nice_view_adapter nice_view-nice_nano__zmk-zmk.uf2`
- `settings_reset-nice_nano__zmk-zmk.uf2` — wipes BLE bonds and settings; flash the normal firmware again afterwards

Flashing: double-tap reset on a half → it mounts as `/Volumes/NICENANO` → `cp -X "<file>.uf2" /Volumes/NICENANO/` (`-X` skips macOS extended attributes). Flash both halves from the same run — ZMK isn't pinned, so two runs can contain different ZMK versions. The left half is the split central: it holds the host bonds, shows the layer and BT-profile widgets, and the right half talks only to it. Bonds survive a normal firmware update.

## How the files fit together

- `build.yaml` — CI matrix. `nice_nano//zmk` is the board id since ZMK's Zephyr 4.1 migration (formerly `nice_nano_v2`). The Chocofi is driven by ZMK's stock `corne` shield (`corne_left`/`corne_right`) plus `nice_view_adapter nice_view`.
- `config/corne.keymap`, `config/corne.conf` — ZMK finds these by shield name, so they must stay `corne.*`; under another name ZMK silently falls back to the stock Corne keymap/defaults. The build log confirms the pickup with `ZMK Config Kconfig: …/config/corne.conf` and `Using keymap file: …/config/corne.keymap`.
- `config/west.yml` — pulls ZMK at `main`, unpinned; CI also uses the workflow from `@main`. Upstream changes can break the build with no change here, so check the ZMK blog first (past breakages: the board id rename, https://zmk.dev/blog/2025/12/09/zephyr-4-1, and removal of `CONFIG_ZMK_DISPLAY_INVERT`).
- `zephyr/module.yml` + empty `boards/shields/` — make the repo a Zephyr module for custom shields/boards; unused so far.
- `scripts/draw-keymap.sh` + `keymap_drawer.config.yaml` — render the keymap with [keymap-drawer](https://github.com/caksoylar/keymap-drawer) (version pinned in the script, run through `uvx`) into `keymap-drawer/corne.yaml` (parsed layers — the quickest way to see what is on each key) and `keymap-drawer/corne.svg` (shown in README). Never edit `keymap-drawer/*` by hand; `keymap-drawer/.inputs.sha256` records the inputs they were made from (`--check` compares it). Legends for the BT keys and the tap-dance are hard-coded in `raw_binding_map` (including "hold 3s"), so update them together with those bindings.
- `.claude/settings.json` → `.claude/hooks/keymap-changed.sh` — PostToolUse hook on Edit/Write/Bash: when the inputs hash changes it redraws the keymap and asks Claude to update CLAUDE.md/README prose if the change affects it. It reports a failed redraw once per input state.

## Keymap structure

The keymap selects ZMK's 36-key Corne layout (`chosen { zmk,physical-layout = &foostan_corne_5col_layout; }`), so every layer has **36 bindings**: three rows of 10, then 6 thumbs (left outer, middle, inner, right inner, middle, outer). Without that `chosen`, ZMK falls back to the 42-key 6-column transform and every key shifts.

| # | Node (`display-name`) | Reached by |
|---|---|---|
| 0 | `default_layer` (Base) | — |
| 1 | `lower_layer` (Nav) | hold right middle thumb (`&mo 1`) |
| 2 | `raise_layer` (Num) | hold left middle thumb (`&mo 2`) |
| 3 | `layer_3` (Fn) | hold both middle thumbs (Nav and Num each map the other middle thumb to `&mo 3`) |

- `&mo N` refers to node order — reordering or inserting layers shifts the indices. Node names are historical; `display-name` is what the drawing and the nice!view show (the built-in widget fits ~9 characters).
- Bluetooth keys on Fn are hold-taps (`hold_bt`, `hold_bt_sel`: `flavor = "tap-preferred"`, `tapping-term-ms = <BT_HOLD_MS>` = 3000, tap = `&none`), so they fire only after a 3 s hold and a shorter press or any other key press cancels them. A hold-tap passes only its first parameter to the hold binding, so `BT_SEL n` goes through the one-param macro `bt_sel_m`, while `BT_CLR` (= `0 0`) works with `&bt` directly. Usage: `&hold_bt BT_CLR`, `&hold_bt_sel <profile> 0`.
- Right outer thumb is `td_alt_ctrl`: tap = Right Alt, double-tap = Left Ctrl.
- `LG(...)` / `LEFT_COMMAND` are Cmd on the macOS host.

## `config/corne.conf` notes

- `CONFIG_ZMK_DISPLAY_STATUS_SCREEN_BUILT_IN=y` replaces the nice!view's default custom screen with ZMK's stock widget screen; the `CONFIG_ZMK_WIDGET_*` lines only have an effect because of it. `CONFIG_ZMK_DISPLAY_WORK_QUEUE_SYSTEM=y` overrides the nice!view's dedicated queue, which causes a harmless `ZMK_DISPLAY_DEDICATED_THREAD_STACK_SIZE` Kconfig warning in every build.
- Don't add `CONFIG_ZMK_BLE_CLEAR_BONDS_ON_START=y`: it wiped bonds on every power-on, breaking host auto-reconnect and left↔right pairing.
- Don't re-add `CONFIG_ZMK_DISPLAY_INVERT=y`: it conflicts with ZMK's nice!view VCOM inversion.
- `CONFIG_ZMK_KEYBOARD_NAME="Chocofi"` is the Bluetooth name the Mac shows.

## Bluetooth recovery

If the Mac stops connecting (seen after a macOS upgrade): on Fn, Z/X/C/V/B select BT profiles 0–4 and A is `BT_CLR`, which clears the bond of the current profile only — each needs a 3 s hold. Hold A, forget "Chocofi" in macOS Bluetooth settings and pair again. If that fails, flash `settings_reset` to both halves, then the normal firmware to both.

## Git

Linear history on `main`, no PRs; push a branch when you want firmware built before merging. Conventional Commits with an area scope or none: `feat(keymap): …`, `fix(display): …`, `build: …`.
