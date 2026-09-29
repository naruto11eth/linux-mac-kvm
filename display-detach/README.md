# display-detach

Disables and re-enables individual external displays on an Apple Silicon Mac so
their monitors lose signal and auto-detect another input. Built for the shared
Sceptre P30 / T32 setup described in `../handoff-display.md` (section 9).

It uses the private CoreGraphics call `CGSConfigureDisplayEnabled`, the same
mechanism BetterDisplay's Pro "Disconnect" uses. Changes are session-scoped: a
logout or reboot restores every display regardless of what this tool did.

## Build

```bash
./build.sh            # needs Xcode Command Line Tools (swiftc); outputs bin/display-detach
```

## Use

```bash
bin/display-detach list                              # ids, UUIDs, active/disabled
bin/display-detach windows                           # diagnostic: Accessibility status + windows it would save
bin/display-detach off <uuid>...                     # cut the Mac's signal
bin/display-detach on  <uuid|id>...                  # restore it
bin/display-detach switch [--hold SECONDS] <uuid>... # save windows, off, wait (default 10 s), on
bin/display-detach save-windows                      # snapshot window frames only
bin/display-detach restore-windows                   # move saved windows back (after the monitors return)
```

## Things learned the hard way

- After `off`, macOS drops the display from its online list and forgets its
  UUID. Re-enable by the numeric id printed by `off` or `list`. `switch` does
  this for you.
- Enabling an already-enabled display fails with CGError 1001. Harmless.
- The built-in display is refused, and `off` refuses to leave zero active
  displays.
- Re-enabling while the monitor shows Linux is fine: the Mac sees it again but
  the monitor keeps showing Linux until Linux drops its signal.
- `switch` restores the disabled displays' mode and arrangement after
  re-enabling. Windows are handled differently on purpose: `switch` saves every
  visible window's frame to `~/Library/Application Support/display-detach/windows.json`
  and, after re-enabling the outputs, parks every window that lived on a
  disabled monitor onto the MacBook screen (relative placement kept, shrunk to
  fit), so they stay usable while the monitors show Linux. macOS is not relied
  on for this: with a 3 s hold it puts windows straight back on the invisible
  monitors. When the monitors are physically back on the
  Mac, `restore-windows` matches each saved window by app and title (then by
  order) and moves it home. The Mac cannot detect the monitors' return itself,
  hence the separate command. Both need the Accessibility permission of the
  launching app; Raycast has it.
- The Sceptres take about 8 s on their own to notice a lost signal and switch.
  A 3 s hold is enough; the rest is the monitors' time and cannot be shortened.

## Hotkey

The two Raycast script commands are in `raycast/`; copy or symlink them into a
folder registered under Raycast > Extensions > Script Commands and bind the hotkeys there.

`~/raycast-scripts/displays-to-linux.sh` (Raycast, Ctrl+Shift+L) calls
`switch` on both Sceptres and falls back to `pmset displaysleepnow` if the tool
fails. `~/raycast-scripts/windows-back.sh` (Raycast, Ctrl+Shift+M) calls
`restore-windows`; press it after the monitors have come back to the Mac. `displays-to-linux.sleep-fallback.sh` here is the original sleep-only
version.
