#!/usr/bin/env bash
#
# Installs a launchd agent that re-runs install-devices.sh every Monday and
# Thursday at 09:30, because free-team signatures expire after 7 days and
# nobody remembers a weekly chore. Mon+Thu keeps the gap at 3-4 days, so even
# a missed run leaves margin before the cliff.
#
# launchd coalesces runs missed while the Mac was asleep or off: the job fires
# once on wake instead of silently skipping the week.
#
# Devices that are offline at run time are skipped by install-devices.sh
# itself and picked up at the next run. Output goes to
# ~/Library/Logs/blml-resign.log.
#
# Rerun this script after moving the repo; remove with:
#   launchctl bootout gui/$UID/app.blml.resign
#
set -euo pipefail
cd "$(dirname "$0")"

LABEL="app.blml.resign"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="$PWD/install-devices.sh"
LOG="$HOME/Library/Logs/blml-resign.log"

[ -x "$SCRIPT" ] || { echo "ERROR: $SCRIPT not found or not executable" >&2; exit 1; }

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$PWD</string>
    <key>StartCalendarInterval</key>
    <array>
        <dict>
            <key>Weekday</key><integer>1</integer>
            <key>Hour</key><integer>9</integer>
            <key>Minute</key><integer>30</integer>
        </dict>
        <dict>
            <key>Weekday</key><integer>4</integer>
            <key>Hour</key><integer>9</integer>
            <key>Minute</key><integer>30</integer>
        </dict>
    </array>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

# Replace any previous registration so path changes take effect.
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$PLIST"

echo "installed: $LABEL (Mon & Thu 09:30, log: $LOG)"
launchctl list | grep "$LABEL" || true
