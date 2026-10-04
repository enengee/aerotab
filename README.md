# AeroTab

A cmd-tab style window switcher for the [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager.
It cycles through the windows of the focused AeroSpace workspace and shows live previews.

| Key | Action |
| --- | --- |
| `alt-tab` | Open the switcher, or move the selection to the next window (most recently used first) |
| `alt-shift-tab` | Same, in the opposite direction |
| `←` / `→` (alt held) | Move the selection |
| `w` (alt held) | Close the selected window |
| `q` (alt held) | Quit the selected window's app |
| `esc` (alt held) | Cancel |
| release `alt` | Switch to the selected window |

If you release alt within 100 ms the switch happens without showing the popup. A workspace with no windows does nothing.
With one window the popup still appears.

## What happens when you release alt

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
  instead of running the `aerospace` CLI. One `eval` gets the focused window and the workspace's windows (about 6 ms),
  and one `eval` makes the switch.
- **Event tap:** a `CGEventTap` intercepts alt-tab and sees alt being released in the same process.
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
