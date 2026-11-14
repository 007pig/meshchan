#!/bin/bash
# Stop only the active test runner for this exact VM and test root.
set -euo pipefail
expected_uuid=${1:?expected VM hardware UUID required}
base=${2:-"$HOME/utm-ui-isolation"}
actual_uuid=$(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F '"' '/IOPlatformUUID/ {print $(NF-1)}')
[[ "$actual_uuid" == "$expected_uuid" && $(/usr/sbin/sysctl -n hw.model) == VirtualMac* ]] || exit 65
[[ -f "$base/active.lock/pid" ]] || { echo IDLE; exit 0; }
pid=$(cat "$base/active.lock/pid")
case "$pid" in ''|*[!0-9]*) exit 64;; esac
command_line=$(ps -p "$pid" -o command=)
[[ ( "$command_line" == *"$base/guest.sh"* || "$command_line" == *"$base/pinyin.sh"* ) && "$command_line" == *"$expected_uuid"* ]] || exit 65
kill -TERM "$pid"
for attempt in {1..100}; do
    [[ -d "$base/active.lock" ]] || { echo STOPPED; exit 0; }
    sleep 0.1
done
echo 'Stop requested; cleanup still pending' >&2
exit 75
