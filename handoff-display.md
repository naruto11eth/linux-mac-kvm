# Handoff: Monitor Input Switching (Mac side)

**Context date:** 2026-09-28
**Written by:** Claude Code on the Linux machine, after completing the Linux half.
**For:** Claude running on the Mac.

---

## 1. The goal

Two monitors are shared between a Linux desktop and a work Mac. There is no KVM.
The user wants to flip the shared monitors between machines **with a keyboard
shortcut** instead of pressing the monitors' physical input buttons.

The mechanism is DDC/CI: writing **VCP feature `0x60` (Input Source)** over the
display cable tells a monitor to change its input, exactly like using its OSD.

**The Linux half is already built, tested and working.** Your job is the Mac half.
Read section 7 for your task, but read sections 3–5 first — they contain hard-won
findings that will waste hours if you rediscover them.

---

## 2. Hardware inventory

### Linux machine
| | |
|---|---|
| OS | Ubuntu 26.04.1, kernel 7.0.0-34-generic |
| Desktop | GNOME 50, **Wayland** |
| Board | ASUSTeK ROG CROSSHAIR VIII HERO (WI-FI), X570/AM4 |
| CPU | AMD Ryzen 9 5950X (**no integrated graphics**) |
| GPU | NVIDIA RTX 3090, driver 595.91.07 (open kernel module) |
| DDC tool | `ddcutil` 2.2.5 |

### Mac
Apple Silicon. `m1ddc` is installed. `m1ddc display list` reports:

```
[1] (null)      (37D8832A-2D66-02CA-B9F7-8F30A301B230)
[2] Sceptre P30 (52976285-E9F5-4697-9C27-C7AEAA14362D)
[3] Sceptre T32 (4516869C-E7F0-4C1D-A8A5-A06B7B8A10CB)
[4] C27F390     (BA210CA7-438C-45E9-9A94-558FB912803B)
```

---

## 3. Cabling topology (confirmed by the user)

| Monitor | Size / native res | To Linux | To Mac |
|---|---|---|---|
| **Acer SB220Q** | 21.5", 1920x1080 | HDMI (GPU `HDMI-A-1`) | *not connected* |
| **Sceptre T32** | 32", 1920x1080 | DisplayPort (`DP-1`) | HDMI-to-USB-C |
| **Sceptre P30** | ultrawide, 2560x1080 | DisplayPort (`DP-2`) | HDMI-to-USB-C |
| **Samsung C27F390** | — | *not connected* | HDMI-to-HDMI |

The Acer is **Linux-only and must never be switched** — it guarantees the user
always has a working Linux screen to trigger a hotkey from.

A Dell WD25 dock is attached to the Linux box but carries **USB and ethernet only**.
It cannot carry video: the 5950X has no iGPU, X570/AM4 has no DP-in header, the
board's USB-C is data-only, and there is no Thunderbolt. Do not suggest routing
video through it.

---

## 4. Per-monitor DDC findings (all empirically verified)

### Sceptre T32 — WORKS, fully switchable
- Linux: `/dev/i2c-4`, connector `DP-1`. Mac: `m1ddc display 3`.
- EDID: `SPT:Sceptre T32:`, product code 3275 (0x0ccb), made 2019 wk43. MCCS 2.1.
- **Its capabilities string is wrong.** It advertises only `0x01 VGA-1` and
  `0x03 DVI-1` — neither of which is a port it actually uses. Ignore it.
- **Report values differ from accept values.** This is the critical quirk:

  | | Value |
  |---|---|
  | Reports when on DisplayPort | `0x04` ("DVI-2") |
  | Reports when on HDMI | `0x00` ("Invalid value") |
  | **Accepts** to go to DisplayPort/Linux | **`0x0f`** (15 decimal) |
  | **Accepts** to go to HDMI/Mac | **`0x11`** (17 decimal) |

  Writing `0x04` does nothing. Only `0x0f` and `0x11` move it.
- **It answers DDC on inputs it is NOT currently displaying.** Linux can talk to it
  over DisplayPort while it shows the Mac. This is why the Linux side alone is
  sufficient for this monitor.
- From the Mac, `m1ddc display 3 get input` returned **`96`**. Communication works.
  `96` (0x60) is not a meaningful input value — consistent with this panel's junk
  reporting. **Do not use reads to verify a switch on this monitor; verify visually.**

### Sceptre P30 — DEAD END, do not spend time on it
- Linux: `/dev/i2c-6`, connector `DP-2`. Mac: `m1ddc display 2`.
- EDID: `SPT:Sceptre P30:0000000000000`, product code 3020 (0x0bcc), 2019 wk24.
  MCCS 2.1. Scaler controller: **MStar**.
- **It only answers DDC on the input it is actively displaying.** This caused a long
  false trail — it looked completely dead until it was switched to DisplayPort.
- Over DisplayPort while displaying DisplayPort, it behaves *perfectly*:
  - reports `0x60` correctly as `0x0f`
  - capabilities are honest: `0x0f DisplayPort-1`, `0x11 HDMI-1`, `0x12 HDMI-2`
  - general writes work — brightness 80 -> 60 -> 80 verified by read-back
- **But writes to `0x60` are silently discarded.** `0x11` and `0x12` both leave it
  on `0x0f`. No error, no movement. Firmware accepts and ignores.
- From the Mac over HDMI while actively displaying the Mac:
  `DDC communication failure: (iokit/?) unknown subsystem error`.
  This test was **valid** — Linux simultaneously confirmed it could not reach the
  panel, proving it really was on the Mac's input at the time.
- Vendor range `0xE0`–`0xFF` scanned read-only for a hidden input control. Only
  responders: `0xE3` and `0xED` (max `0x0001` — too small to address 3 inputs),
  and raw 16-bit registers `0xFA`, `0xFD` (=`0x63`), `0xFF`. **No input selector exists.**
- **Verdict: not software-switchable from either machine.** The user presses its
  `E` button. Do not re-investigate. Do not write to vendor registers.

### Acer SB220Q — excluded on purpose
- Linux `/dev/i2c-5`, `HDMI-A-1`. DDC fully functional (`0x01 VGA-1`,
  `0x11 HDMI-1`, `0x12 HDMI-2`; currently `0x11`). Deliberately left out of all
  automation because it is the user's guaranteed-visible Linux screen.

### Samsung C27F390 — unknown
- Mac-only, `m1ddc display 4`. `m1ddc display 4 get input` returned **nothing**.
  Never investigated. Not part of the switching setup.

---

## 5. Traps that already cost time — do not repeat these

1. **`m1ddc` with no display argument targets the default display**, not the one you
   mean. `m1ddc set input 15` silently acted on `[1] (null)`. Always write
   `m1ddc display N <command>`.
2. **A monitor showing another input may be deaf to DDC.** Before concluding a panel
   is broken, confirm which input it is displaying. The P30 is deaf off-input; the
   T32 is not. This differs per monitor.
3. ~~**The HDMI-to-USB-C adapters are NOT a problem.** The T32 answers through one.
   Any DDC failure is the monitor, not the adapter.~~ **RETRACTED (see sections 9 and 10):**
   the adapters do not pass DDC at all. The T32's "96" was the adapter echoing the opcode.
4. **Never trust a capabilities string.** The T32's is actively wrong. Determine
   accepted values by writing and observing, not by reading.
5. **Read-back is not proof of success on the T32** — its reported values are junk.

---

## 6. What already exists on the Linux side

- `~/.local/bin/display-switch` — bash, handles detection, matching, locking,
  notifications, and per-monitor error reporting. Runs `ddcutil` at
  `--sleep-multiplier 4` (these budget panels need slow bus timing) and uses
  `--noverify` (a monitor that switches away cannot confirm the write).
- `~/.config/display-switch/config` — one line per monitor per target:
  `<monitor-id-glob>  <target>  <vcp-value>`. Currently:
  ```
  SPT:Sceptre T32:    pc    0x0f
  SPT:Sceptre T32:    mac   0x11
  ```
- GNOME hotkeys: `Super+Alt+M` -> `display-switch mac`, `Super+Alt+P` -> `display-switch pc`.
- `ddcutil` runs unprivileged — systemd `uaccess` already grants ACLs on `/dev/i2c-*`.
  No i2c group membership or udev rule was needed.

Both directions are verified working for the T32 from Linux.

---

## 7. YOUR TASK on the Mac

The Linux side already covers the T32 in both directions, so this is **symmetry and
convenience, not a gap**. Build the Mac-side equivalent:

1. **Verify the T32 accepts input writes from the Mac.** This is *not yet tested* —
   only reads were confirmed. Run, while watching the T32:
   ```bash
   m1ddc display 3 set input 15    # 0x0f -> should send it to Linux/DisplayPort
   ```
   If it moves, the Mac can drive it. Recovery if anything goes wrong: the Linux box
   can always pull it back with `Super+Alt+P`, so nothing is unrecoverable.

2. **If that works, bind two hotkeys** using whatever the user already has —
   Raycast, Karabiner-Elements, Hammerspoon, or `skhd`:
   | Action | Command |
   |---|---|
   | Send T32 to Linux | `m1ddc display 3 set input 15` |
   | Bring T32 to Mac | `m1ddc display 3 set input 17` |

   Mirror the Linux bindings if the user's Mac allows it (`Super+Alt+M` / `Super+Alt+P`
   map to `Cmd+Opt+M` / `Cmd+Opt+P`). Ask before overriding existing shortcuts.

3. **Address the P30 by identity, not index, if you script anything further.**
   `m1ddc` display numbers can reorder. Prefer the UUIDs in section 2.

4. **Do not attempt anything for the P30.** It is closed. If the user asks, the only
   remaining option is a hardware 2:1 display switch on its input (~$30–60), or
   continuing to press its `E` button.

### Out of scope
Keyboard and mouse sharing. The user is handling that separately — switching displays
does not move input devices. (If asked: Input Leap / Deskflow over the network is the
obvious software option.)

---

## 8. Quick reference

```bash
# Mac
m1ddc display list
m1ddc display 3 get input          # T32  (returns junk: 96)
m1ddc display 3 set input 15       # T32 -> Linux  (0x0f)
m1ddc display 3 set input 17       # T32 -> Mac    (0x11)
m1ddc display 2 get input          # P30  -> DDC communication failure. Expected.

# Linux (for reference)
display-switch status              # current input of every reachable monitor
display-switch probe               # monitor ids + advertised input values
display-switch pc                  # T32 -> Linux
display-switch mac                 # T32 -> Mac
```

| Monitor | Linux bus | Mac id | Linux code | Mac code | Switchable |
|---|---|---|---|---|---|
| Acer SB220Q | 5 | — | — | — | excluded (Linux-only) |
| Sceptre T32 | 4 | `display 3` | `0x0f` / 15 | `0x11` / 17 | **yes** |
| Sceptre P30 | 6 | `display 2` | — | — | **no (firmware)** |
| Samsung C27F390 | — | `display 4` | — | — | unknown |

---

## 9. Mac-side findings and Linux follow-up (written on the Mac, 2026-09-28)

### DDC from the Mac is a dead end — for both Sceptres
- **The T32's HDMI-to-USB-C adapter does not pass DDC/CI.** Every `m1ddc get` returns
  the VCP opcode itself as the "value": input `0x60` -> 96, luminance `0x10` -> 16,
  contrast `0x12` -> 18, volume `0x62` -> 98. The adapter echoes the request.
  `m1ddc display 3 set input 15` and `set input 17` both returned exit 0 and did
  nothing. **Section 5, trap 3 is wrong**: the adapter *is* the problem. The "96"
  read was never real communication.
- **The P30's adapter fails hard** (`DDC communication failure`) even while the P30
  is actively displaying the Mac, so that test in section 4 also reflects the adapter,
  not only the panel.
- BetterDisplay is installed on the Mac; it uses the same DDC path, so it cannot help.

### What works instead: signal-drop auto-detect (both monitors, both directions)
Both Sceptres hunt for a live input when their current one disappears, even though
the P30's OSD exposes no auto-source option. Verified by the user:

| Direction | Command that triggers it | Result |
|---|---|---|
| To Linux | Mac: `pmset displaysleepnow` | P30 **and** T32 moved to Linux |
| To Mac | Linux: `busctl --user set-property org.gnome.Mutter.DisplayConfig /org/gnome/Mutter/DisplayConfig org.gnome.Mutter.DisplayConfig PowerSaveMode i 1` | P30 **and** T32 moved to Mac |

Key facts:
- The machine that gave up the monitors must **wake itself afterwards** and keep
  outputting. The Mac still lists both Sceptres as online while they show Linux, so
  a later Linux signal-drop finds the Mac. The same must hold in reverse.
- The Acer (Linux-only) and Samsung (Mac-only) just blank and return.
- Monitors need several seconds of no-signal before they scan. The Mac holds for 10 s.

### Mac side (done) — UPDATED: per-display detach, no more display sleep
The Mac no longer sleeps its displays. `display-detach/` (this repo, Swift, built
with `./build.sh`) disables just the P30 and T32 via the private
`CGSConfigureDisplayEnabled` call, holds 3 s, re-enables them by numeric id. (3 s
is enough: the Sceptres take ~8 s on their own to notice and switch; the hold only
has to avoid interrupting that. Try 3 s on the Linux side too instead of 10.) The
MacBook screen stays on, so the MDM lock never fires. Verified 2026-09-28 14:25:
both Sceptres moved to Linux, Mac re-listed both afterwards. The Raycast script
calls it and falls back to `pmset displaysleepnow` if the tool errors. It also restores the Sceptres' display mode/arrangement after re-enabling. Windows
are saved, then left on the MacBook screen (usable while the monitors show Linux);
a second Mac hotkey, **Ctrl+Shift+M = "Windows Back to Monitors"**, moves them home
after the monitors physically return. So the Mac's Ctrl+Shift+M is *not* a signal
switch; the return trip is still triggered from Linux. Read
`display-detach/README.md` before touching it. The paragraph below describes the
original sleep-based version, kept as `display-detach/displays-to-linux.sleep-fallback.sh`.

`~/raycast-scripts/displays-to-linux.sh` (Raycast script command): `pmset displaysleepnow; sleep 10;
caffeinate -u -t 2`. Bound in Raycast to **Ctrl+Shift+L**. **Verified end to end 2026-09-28**: both
Sceptres moved to Linux, Mac self-woke after 10 s. Each run appends a line to
`~/Library/Logs/display-switch.log`. The Mac locks on every run because its
lock-after-display-off policy is MDM-enforced (work Mac); accepted for now. There is deliberately no
Mac-side "bring to Mac" hotkey: the Mac cannot make Linux drop its signal without
SSH, which the user declined. The return trip is triggered from the Linux keyboard.

### YOUR TASK on Linux

> **SUPERSEDED, see section 10.** This was done on Linux, but not as written here.
> `PowerSaveMode` is a global DPMS switch and it blanked the Acer, which must never
> sleep. Linux disables only DP-1/DP-2 instead. Kept below for history.

1. Create `~/.local/bin/displays-to-mac`:
   ```bash
   #!/bin/bash
   set -euo pipefail
   DC=org.gnome.Mutter.DisplayConfig
   busctl --user set-property $DC /org/gnome/Mutter/DisplayConfig $DC PowerSaveMode i 1
   sleep 3   # 10 was the first guess; 3 s proved enough on the Mac, verify here
   busctl --user set-property $DC /org/gnome/Mutter/DisplayConfig $DC PowerSaveMode i 0
   ```
   Verify the second call actually re-lights the Acer without user input. **Observed
   2026-09-28:** when the user ran only the `PowerSaveMode i 1` call by hand, both
   Sceptres moved to the Mac as intended, but the Acer stayed dark until a key was
   pressed on the Linux keyboard. The wake step is therefore mandatory, not optional. If mutter
   ignores `PowerSaveMode 0` while idle, fall back to synthesizing input (e.g. `ydotool`
   or `wtype`), and confirm Linux keeps outputting on DP-1/DP-2 while the Sceptres
   show the Mac.
2. Bind it to **Ctrl+Shift+M** in GNOME keyboard shortcuts, mirroring the Mac's
   Ctrl+Shift+L (Ctrl and Shift are the same physical keys on both machines). Ask before overriding anything.
3. Leave `display-switch` and its `Super+Alt+M/P` bindings in place. The DDC path
   still works for the T32 from Linux and is a useful fallback; the new script is
   the one that also moves the P30.
4. Check whether GNOME's "lock screen after blank" fires on this brief blank and
   relax it if it does. The Mac has the same issue with its lock-after-display-off
   setting.

---

## 10. Linux follow-up (written on Linux, 2026-09-28, updated 2026-09-29)

### Section 9's correction is accepted
The adapter-echo evidence is conclusive (`0x60`->96, `0x10`->16, `0x12`->18, `0x62`->98;
every read returns the opcode in decimal). Section 5, trap 3 was wrong and is retracted:
the HDMI-to-USB-C adapters don't pass DDC, and the "96" read from the T32 was never real
communication.

This doesn't change the P30 verdict. That came from Linux talking to the P30 directly
over DisplayPort from the GPU, with no adapter in the path. There it communicates fine
and simply discards `0x60` writes. The Mac-side P30 test is now uninformative rather than
confirming, but the conclusion still holds on the Linux evidence.

### Signal drop also confirmed from the Linux side
This was checked through DDC readings rather than by looking at the screens. After a
signal drop, the T32 reported `0x00` (its on-HDMI value) and the P30 stopped answering
on DP, which means both had moved to the Mac. The Acer stayed on `0x11`. **Both Sceptres
move, including the P30.**

### Linux implementation: per-output, not `PowerSaveMode`. Don't "fix" it back
Section 9 proposed `busctl ... PowerSaveMode i 1`. That was built first and **rejected
in testing: `PowerSaveMode` is a global DPMS switch with no per-output control, so it
also blanked the Acer.** The user's hard requirement is that the Acer never sleeps.

Current tool: `~/.local/bin/displays-to-mac` (Python). It calls
`org.gnome.Mutter.DisplayConfig.ApplyMonitorsConfig` to disable **only** `DP-1` and
`DP-2`, waits, then reapplies the original layout. This is the same idea as the Mac's
`display-detach`.
- Gotcha: mutter rejects any layout whose top-left isn't `(0,0)`
  (`InvalidArgs: Logical monitors positions are offset`). The Acer sits at `(369,0)`,
  so positions have to be normalised after the monitors are dropped. This cost one
  failed run.
- The restore runs from a `finally` block plus SIGINT/SIGTERM/SIGHUP handlers. A plain
  sequential script would leave the DP outputs dark for good if it died mid-hold.
- It refuses to run if `HDMI-1` isn't connected, so it can never blank the last screen.
- Hold is 10 s by default and can be overridden with `DISPLAYS_TO_MAC_HOLD`. The 3 s
  that works on the Mac hasn't been tested on Linux yet. Linux's DP signal comes back
  sooner than the monitors' ~8 s scan, so this needs checking here rather than assuming.
- Verified: the layout comes back exactly (positions and primary preserved).
- Bound to **Ctrl+Shift+M** (GNOME custom keybinding `custom4`).
- Logs to `~/.local/state/display-switch.log`.
- For now it lives only in `~/.local/bin`, not in this repo.

Status of section 9's Linux task: items 1 and 2 are done, per the implementation above.
Item 3 is done, with `display-switch` and `Super+Alt+M/P` kept as the DDC fallback for
the T32. Item 4 turned out not to be an issue: `idle-delay` is `0` and `LockedHint`
stayed `no` across runs, so the short blank never triggers the GNOME lock. No input
synthesis was needed, because the outputs come back on their own.

### Previously open: Mac must be awake. Probably fixed by `display-detach`
Signal drop only works if the other machine is actively driving those outputs. With the
old sleep-based Mac script, the user pressed Ctrl+Shift+M on Linux three times with no
effect, then woke the Mac by hand, and after that it worked immediately.
`display-detach` keeps the MacBook screen on, so the MDM lock-after-display-off
shouldn't fire, and the Mac should keep driving the Sceptres after handing them over.
**Expected to be fixed, but not yet confirmed from the Linux side.**

### Still to do on Linux
1. Test a 3 s hold, and make it the default if the Sceptres still switch reliably.
2. Move the Linux tools (`displays-to-mac`, `display-switch` and its config) into this repo.
3. Check what happens to Linux windows. mutter moves them onto the Acer while DP-1/DP-2
   are off, and it hasn't been verified whether they return. The Mac handles this
   explicitly (park, then restore with a second hotkey). Linux doesn't yet.

### Hotkey map, both machines
| Keys | Machine | Effect |
|---|---|---|
| `Ctrl+Shift+M` | Linux | Both Sceptres -> Mac (disables DP-1/DP-2; the Acer isn't touched) |
| `Ctrl+Shift+L` | Mac | Both Sceptres -> Linux (`display-detach switch`, `pmset` fallback) |
| `Ctrl+Shift+M` | Mac | Windows Back to Monitors (`restore-windows`). **Not** a signal switch |
| `Super+Alt+M` / `Super+Alt+P` | Linux | T32 only, via DDC. Kept as a fallback |

`Ctrl+Shift+M` does different things on each machine. They're separate keyboards, so
nothing collides, but keep it in mind if a shared keyboard is ever added.
