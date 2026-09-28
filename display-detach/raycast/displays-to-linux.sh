#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Displays to Linux
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🖥️
# @raycast.packageName Display Switch
# @raycast.description Cut the Mac's signal to the shared Sceptre P30 and T32 so they auto-detect Linux, then restore the outputs. The MacBook screen stays on, so no lock.

set -euo pipefail

DETACH="$HOME/Desktop/web3_projects/display-work/display-detach/bin/display-detach"
P30=52976285-E9F5-4697-9C27-C7AEAA14362D
T32=4516869C-E7F0-4C1D-A8A5-A06B7B8A10CB
# Seconds the outputs stay off. 3 s is enough: the Sceptres notice the lost
# signal and switch on their own (~8 s total) once the Mac has let go.
HOLD="${DISPLAY_SWITCH_HOLD:-3}"
LOG="$HOME/Library/Logs/display-switch.log"

if "$DETACH" switch --hold "$HOLD" "$P30" "$T32" >>"$LOG" 2>&1; then
  echo "$(date '+%F %T') displays handed to Linux (detach)" >>"$LOG"
  echo "Displays handed to Linux"
else
  # Fall back to sleeping every display: cruder and it locks the Mac, but it
  # never leaves a monitor stuck disabled.
  echo "$(date '+%F %T') detach failed, falling back to display sleep" >>"$LOG"
  pmset displaysleepnow
  sleep "$HOLD"
  caffeinate -u -t 2
  echo "Displays handed to Linux (fallback: display sleep)"
fi
