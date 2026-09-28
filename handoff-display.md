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
3. **The HDMI-to-USB-C adapters are NOT a problem.** The T32 answers through one.
   Any DDC failure is the monitor, not the adapter.
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
