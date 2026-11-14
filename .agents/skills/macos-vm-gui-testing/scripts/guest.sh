#!/bin/bash
# Execute only INSIDE the explicitly identified macOS VM.
set -euo pipefail
base=${3:-"$HOME/utm-ui-isolation"}
export PATH="$base/bin:/usr/bin:/bin:/usr/sbin:/sbin"
expected_uuid=${1:?expected VM hardware UUID required}
stage=${2:?baseline, background, or minimized required}
case "$stage" in pinyin|product) rounds=0;; baseline) rounds=3;; background|minimized) rounds=30;; *) exit 64;; esac
actual_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F '"' '/IOPlatformUUID/ {print $(NF-1)}')
[[ "$actual_uuid" == "$expected_uuid" ]] || { echo 'REFUSED: guest identity mismatch' >&2; exit 65; }
model=$(sysctl -n hw.model)
[[ "$model" == VirtualMac* ]] || { echo 'REFUSED: not a VirtualMac' >&2; exit 65; }
[[ $(stat -f %Su /dev/console) == "$(id -un)" ]] || { echo 'No console session for SSH user' >&2; exit 66; }
[[ $(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -) == false ]] || { echo 'BLOCKED: guest is locked' >&2; exit 66; }
if [[ "$stage" == pinyin ]]; then exec /bin/bash "$base/pinyin.sh" "$expected_uuid" "$base"; fi
if [[ "$stage" == product ]]; then exec /bin/bash "$base/product.sh" "$expected_uuid" "$base"; fi
cliclick=$(command -v cliclick) || { echo 'cliclick is not installed in guest' >&2; exit 69; }
mkdir -p "$base/runs"
lock="$base/active.lock"
mkdir "$lock" || { echo 'Another run is active; inspect active.lock' >&2; exit 67; }
printf '%s\n' "$$" > "$lock/pid"
run="$base/runs/$(date -u +%Y%m%dT%H%M%SZ)-$stage-$$"
mkdir "$run"
printf '%s\n' "$run" > "$base/latest-run"
exec > >(tee "$run/run.log") 2>&1
watchdog=''
active_child=''
run_command() {
    "$@" <&0 &
    active_child=$!
    local result=0
    wait "$active_child" || result=$?
    active_child=''
    return "$result"
}
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    [[ -z "$watchdog" ]] || kill "$watchdog" 2>/dev/null || true
    [[ -z "$watchdog" ]] || wait "$watchdog" 2>/dev/null || true
    [[ -z "$active_child" ]] || kill -TERM "$active_child" 2>/dev/null || true
    "$base/bin/key-input" reset >/dev/null 2>&1 || true
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || true
    printf '%s exit=%s\n' "$(date -u +%FT%TZ)" "$rc"
    printf '%s\n' "$rc" > "$run/exit-code"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
runner_pid=$$
(sleep 150; kill -TERM "$runner_pid" 2>/dev/null) &
watchdog=$!
sw_vers > "$run/environment.txt"
printf 'model=%s\nuuid=%s\nuser=%s\nstage=%s\n' "$model" "$actual_uuid" "$(id -un)" "$stage" >> "$run/environment.txt"
csrutil status >> "$run/environment.txt"
run_command system_profiler SPDisplaysDataType >> "$run/environment.txt"
"$cliclick" -V >> "$run/environment.txt"
# Open an empty plain-text file via LaunchServices. All test content comes from keys.
doc="$run/probe-$stage-$$.txt"
: > "$doc"
run_command open -a TextEdit "$doc"
run_command "$base/bin/place-window" "$doc"
run_command "$base/bin/key-input" reset
run_command "$base/bin/key-input" escape
sleep 1
run_command screencapture -x "$run/start.png"
for ((i=1; i<=rounds; i++)); do
    # Fixed point is inside the configured document window, in guest coordinates.
    run_command "$base/bin/place-window" "$doc"
    run_command "$cliclick" -w 50 c:350,250
    run_command "$base/pinyin-bin/ime-inspect" "$doc" > "$run/focus-$i.json"
    run_command "$base/bin/key-input" end
    line=$(printf 'VM-%s-%03d' "$stage" "$i")
    run_command "$base/bin/key-input" type "$line"
    run_command "$base/bin/key-input" return
    printf '%s sent=%s\n' "$(date -u +%FT%TZ)" "$line"
    printf '%s\n' "$line" >> "$run/expected.txt"
    if ((i == (rounds+1)/2)); then run_command screencapture -x "$run/middle.png"; fi
    sleep 2
done
run_command screencapture -x "$run/end.png"
# Save through a real keyboard shortcut; inspect the actual saved file.
run_command "$base/bin/key-input" save
sleep 1
cp "$doc" "$run/actual.txt"
tr '\r' '\n' < "$run/actual.txt" > "$run/actual-normalized.txt"
diff -u "$run/expected.txt" "$run/actual-normalized.txt" > "$run/text.diff" || { cat "$run/text.diff"; exit 1; }
echo 'GUEST_TEXT_PASS (host input isolation still requires user observation)'
