#!/bin/bash
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
expected_uuid=${1:?VM UUID required}
actual_uuid=$(ioreg -rd1 -c IOPlatformExpertDevice | awk -F '"' '/IOPlatformUUID/ {print $(NF-1)}')
[[ "$actual_uuid" == "$expected_uuid" && $(sysctl -n hw.model) == VirtualMac* ]] || exit 65
base=${2:-"$HOME/utm-ui-isolation"}
bins="$base/pinyin-bin"
[[ $(stat -f %Su /dev/console) == "$(id -un)" ]] || exit 66
mkdir -p "$base/runs"
[[ $(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -) == false ]] || { echo 'BLOCKED: guest is locked' >&2; exit 66; }
mkdir "$base/active.lock"
echo $$ > "$base/active.lock/pid"
run="$base/runs/$(date -u +%Y%m%dT%H%M%SZ)-pinyin-$$"
mkdir "$run"
echo "$run" > "$base/latest-run"
exec > >(tee "$run/run.log") 2>&1
child=''; watchdog=''
run_command() {
    "$@" <&0 & child=$!
    local result=0
    wait "$child" || result=$?
    child=''
    return "$result"
}
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    [[ -z "$child" ]] || kill -TERM "$child" 2>/dev/null || true
    [[ -z "$watchdog" ]] || kill "$watchdog" 2>/dev/null || true
    [[ -z "$watchdog" ]] || wait "$watchdog" 2>/dev/null || true
    "$bins/key-input" reset >/dev/null 2>&1 || true
    rm -f "$base/active.lock/pid"; rmdir "$base/active.lock" 2>/dev/null || true
    echo "$rc" > "$run/exit-code"
    printf '%s exit=%s\n' "$(date -u +%FT%TZ)" "$rc"
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT
runner=$$
(sleep 300; kill -TERM "$runner" 2>/dev/null) & watchdog=$!
focus() { run_command "$bins/ime-inspect" "$doc" > "$run/$1.json"; }
source_id() { plutil -extract sourceID raw -o - "$run/$1.json"; }
switch_to() {
    wanted=$1
    label=$2
    run_command "$bins/key-input" switch
    sleep 0.5
    focus "$label"
    for attempt in 1 2 3; do
        current=$(source_id "$label")
        [[ "$current" != "$wanted" ]] || return 0
        run_command "$bins/key-input" next-source
        sleep 0.5
        focus "$label"
    done
    [[ $(source_id "$label") == "$wanted" ]]
}
review_gate() {
    gate=$1
    touch "$run/ready-$gate"
    printf '%s WAITING_FOR_PREEDIT_REVIEW=%s\n' "$(date -u +%FT%TZ)" "$gate"
    for ((i=0;i<120;i++)); do
        [[ ! -f "$run/commit-$gate" ]] || return 0
        sleep 1
    done
    echo 'BLOCKED: preedit review was not confirmed; no Save or forced commit.'
    exit 78
}
sw_vers > "$run/environment.txt"
defaults export com.apple.symbolichotkeys "$run/hotkeys.plist"
[[ $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:60:enabled' "$run/hotkeys.plist") == true &&
   $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:60:value:parameters:1' "$run/hotkeys.plist") == 49 &&
   $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:60:value:parameters:2' "$run/hotkeys.plist") == 262144 ]] || {
    echo 'BLOCKED: expected guest Control+Space binding; inspect guest hotkeys before adapting.'; exit 78;
}
csrutil status >> "$run/environment.txt"
[[ $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:61:enabled' "$run/hotkeys.plist") == true &&
   $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:61:value:parameters:1' "$run/hotkeys.plist") == 49 &&
   $(/usr/libexec/PlistBuddy -c 'Print :AppleSymbolicHotKeys:61:value:parameters:2' "$run/hotkeys.plist") == 786432 ]] || {
    echo 'BLOCKED: expected guest Control+Option+Space next-source binding'; exit 78;
}
defaults read com.apple.HIToolbox > "$run/input-preferences.txt"
doc="$run/probe-pinyin-$$.txt"
: > "$doc"
run_command open -a TextEdit "$doc"
run_command "$base/bin/place-window" "$doc"
run_command "$base/bin/cliclick" c:350,250
run_command "$bins/key-input" reset
focus initial
original=$(source_id initial)
case "$original" in com.apple.keylayout.US|com.apple.keylayout.ABC) ;; *) echo 'BLOCKED: initial input source is not Latin'; exit 78;; esac
run_command "$bins/key-input" type ABC
run_command "$bins/key-input" return
focus latin-before-switch
switch_to com.apple.inputmethod.SCIM.ITABC pinyin-first-switch
run_command "$bins/key-input" type zhongwen
sleep 0.5
focus zhongwen-preedit
run_command screencapture -x "$run/zhongwen-preedit.png"
review_gate zhongwen
focus zhongwen-before-commit
[[ $(plutil -extract text raw -o - "$run/zhongwen-preedit.json") == $(plutil -extract text raw -o - "$run/zhongwen-before-commit.json") ]] || exit 78
run_command "$bins/key-input" space
sleep 0.5
focus zhongwen-committed
run_command screencapture -x "$run/zhongwen-committed.png"
run_command "$bins/key-input" return
switch_to "$original" latin-return-switch
run_command "$bins/key-input" type ABC
run_command "$bins/key-input" return
focus latin-return-typed
switch_to com.apple.inputmethod.SCIM.ITABC pinyin-second-switch
run_command "$bins/key-input" type nihao
sleep 0.5
focus nihao-preedit
run_command screencapture -x "$run/nihao-preedit.png"
review_gate nihao
focus nihao-before-commit
[[ $(plutil -extract text raw -o - "$run/nihao-preedit.json") == $(plutil -extract text raw -o - "$run/nihao-before-commit.json") ]] || exit 78
run_command "$bins/key-input" space
sleep 0.5
focus nihao-committed
run_command screencapture -x "$run/nihao-committed.png"
run_command "$bins/key-input" return
switch_to "$original" restored-source
run_command "$bins/key-input" type ABC
run_command "$bins/key-input" return
focus final-text
run_command screencapture -x "$run/final.png"
run_command "$bins/key-input" save
sleep 1
cp "$doc" "$run/actual.txt"
printf 'ABC\n中文\nABC\n你好\nABC\n' > "$run/expected.txt"
diff -u "$run/expected.txt" "$run/actual.txt" > "$run/text.diff" || { cat "$run/text.diff"; exit 1; }
echo PINYIN_COMMIT_AND_PERSISTENCE_PASS
