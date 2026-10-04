# AeroTab

A cmd-tab style window switcher for the [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager,
with live previews. It has two modes:

- **`alt-tab`:** the windows of the focused AeroSpace workspace.
- **`cmd-tab`:** every window in every workspace, grouped one row per workspace. It replaces the macOS app switcher.

| Key | Action |
| --- | --- |
| `alt-tab` / `cmd-tab` | Open the switcher, or move the selection to the next window |
| `alt-shift-tab` / `cmd-shift-tab` | Same, in the opposite direction |
| `←` / `→` (modifier held) | Move the selection |
| `` ` `` or `↓` (cmd held) | Jump to the first window of the next workspace |
| `` shift-` `` or `↑` (cmd held) | Jump to the last window of the previous workspace |
| `w` (modifier held) | Close the selected window |
| `q` (modifier held) | Quit the selected window's app |
| `esc` (modifier held) | Cancel |
| release the modifier | Switch to the selected window |

If you release the modifier within 100 ms the switch happens without showing the popup. With no windows nothing
happens; with one window the popup still appears.

## Ordering

- **`alt-tab`:** most recently used first. The first tap selects the window you used before the current one.
- **`cmd-tab`:** the focused workspace's row comes first. Other rows follow in order of their most recently used
  window, and windows inside a row are most recently used first. Each window is its own entry, even when several
  belong to the same app. The first tap selects the window you used before the current one, wherever it is.
  The selected window's row is lit and its workspace name turns bold white. Empty workspaces are not shown.

While AeroTab runs it turns off the macOS cmd-tab and cmd-shift-tab shortcuts. It uses the private
`CGSSetSymbolicHotKeyEnabled`, the same call AltTab uses, and turns them back on when it exits.

## What happens when you release the modifier

- **Selected window is in another workspace** (cmd-tab only): that workspace is brought to the focused monitor
  with `aerospace summon-workspace`, even if it was showing on another monitor, and the window gets focus.
- **Selected window is already focused:** nothing happens.
- **Selected window is visible on screen** (at least half of it is uncovered): it gets focus.
- **Selected window is hidden:** it is brought into view and focused, without hiding the window that had focus before.
  - If it is stacked behind the previously focused window in the same accordion, it moves into the nearest other
    visible column and goes in front there. If that column is a single window, the two become a `v_accordion`.
  - If there is nowhere else to put it (for example, a single full-screen accordion), it simply comes forward.
  - If it is hidden somewhere else (for example, behind another window in the other column), focusing it brings it
    forward. The previously focused window is not affected.

Before asking AeroSpace to focus a window, AeroTab focuses that exact window itself. It uses the same private SkyLight
calls as AltTab (`_SLPSSetFrontProcessWithOptions` plus a key-window event), followed by an Accessibility raise.
Without this step, focusing one window of an app that has another window visible on a different monitor (for
example, two Chrome windows) lets macOS activate the app's other window, and AeroSpace follows it there.

## How it is fast

- **Long-running agent:** a single process with no Dock icon and no menu bar item. No shell scripts or processes are
  started per key press.
- **Direct AeroSpace socket:** talks to `/tmp/bobko.aerospace-$USER.sock` using AeroSpace's own protocol (version 1),
  instead of running the `aerospace` CLI. One `eval` gets the focused window, the focused workspace and the window
  list (about 6 ms for one workspace), and one `eval` makes the switch.
- **Event tap:** a `CGEventTap` intercepts alt-tab and cmd-tab and sees the modifier being released in the same
  process.
- **Recently-used order:** a persistent `aerospace subscribe focus-changed` connection keeps the order up to date.
- **Previews:** ScreenCaptureKit captures thumbnails in parallel. Cached ones are shown immediately and fresh ones
  replace them as they arrive.

## Install

Requires AeroSpace ≥ 0.21 and macOS 14 or later. Xcode Command Line Tools are enough to build.

```sh
make cert      # once: create the self-signed 'aerotab-dev' code-signing certificate in the login keychain
make install   # build, sign, copy to ~/Applications/AeroTab.app, load the LaunchAgent local.aerotab
```

Then turn on AeroTab in System Settings › Privacy & Security, under both **Accessibility** and
**Screen & System Audio Recording**, and run `make restart`.
Because every build is signed with the same certificate, the permissions survive rebuilds.

Remove any `alt-tab` / `alt-shift-tab` bindings from `aerospace.toml`; AeroTab owns those keys.

Other targets: `make test`, `make restart`, `make uninstall`. Errors are logged to `~/Library/Logs/aerotab.log`.
