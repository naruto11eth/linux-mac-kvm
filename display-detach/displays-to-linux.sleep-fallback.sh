#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Displays to Linux
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Display Switch
# @raycast.description Sleep the Mac's displays so the shared monitors (Sceptre P30, T32) auto-detect the Linux signal, then wake the Mac so it keeps outputting for the return trip.

set -euo pipefail

# Seconds the displays stay asleep. Must exceed the monitors' no-signal
# timeout plus their input scan, otherwise they never leave the Mac.
HOLD="${DISPLAY_SWITCH_HOLD:-10}"

pmset displaysleepnow
sleep "$HOLD"
# Assert user activity so the Mac wakes without a key press. If the Mac is
# not outputting, the monitors have nothing to return to later.
caffeinate -u -t 2

echo "$(date "+%F %T") displays handed to Linux" >> ~/Library/Logs/display-switch.log
echo "Displays handed to Linux"
