#!/bin/bash
# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Windows Back to Monitors
# @raycast.mode silent
#
# Optional parameters:
# @raycast.icon 🪟
# @raycast.packageName Display Switch
# @raycast.description After the Sceptres return to the Mac, move every window back to where it was before the last "Displays to Linux".

set -euo pipefail

DETACH="$HOME/Desktop/web3_projects/display-work/display-detach/bin/display-detach"
LOG="$HOME/Library/Logs/display-switch.log"

result="$("$DETACH" restore-windows 2>&1 | tee -a "$LOG")"
echo "$(date '+%F %T') windows back: $result" >>"$LOG"
echo "$result"
