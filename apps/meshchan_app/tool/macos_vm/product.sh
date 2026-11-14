#!/bin/bash
# GUI-session child of the existing authorized UTMUIProbe, never a host executor.
set -euo pipefail
expected_uuid=${1:?}
base=${2:?}
[[ $(/usr/sbin/sysctl -n hw.model) == VirtualMac* ]] || exit 65
[[ $(/usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F '"' '/IOPlatformUUID/ {print $(NF-1)}') == "$expected_uuid" ]] || exit 65
[[ $(stat -f %Su /dev/console) == "$(id -un)" ]] || exit 66
[[ $(/usr/sbin/ioreg -a -n Root -d1 | /usr/bin/plutil -extract IOConsoleLocked raw -o - -) == false ]] || exit 66
lock="$base/active.lock"
mkdir "$lock"
printf '%s\n' "$$" > "$lock/pid"
run="$base/runs/$(date -u +%Y%m%dT%H%M%SZ)-product-$$"
mkdir -p "$run/queue" "$run/replies"
printf '%s\n' "$run" > "$base/latest-run"
exec > >(tee "$run/run.log") 2>&1
child=''
cleanup() {
    rc=$?
    trap - EXIT INT TERM
    [[ -z "$child" ]] || kill -TERM "$child" 2>/dev/null || true
    "$base/bin/key-input" reset >/dev/null 2>&1 || true
    rm -f "$lock/pid"
    rmdir "$lock" 2>/dev/null || true
    printf '%s\n' "$rc" > "$run/exit-code"
    # A product owner is never killed to pretend that its shutdown succeeded.
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
sw_vers > "$run/environment.txt"
printf 'uuid=%s\nconsole=%s\n' "$expected_uuid" "$(id -un)" >> "$run/environment.txt"
echo 'PRODUCT_READY: awaiting explicit owned-fixture commands'
deadline=$((SECONDS + 1800))
while ((SECONDS < deadline)); do
    [[ ! -f "$run/finish" ]] || exit 0
    for job in "$run"/queue/*.sh; do
        [[ -f "$job" ]] || continue
        name=${job##*/}; name=${name%.sh}
        rc=0
        /bin/bash "$job" > "$run/replies/$name.stdout" 2> "$run/replies/$name.stderr" &
        child=$!
        wait "$child" || rc=$?
        child=''
        rm "$job"
        printf '%s\n' "$rc" > "$run/replies/$name.exit"
    done
    sleep 0.1
done
echo 'Product controller deadline expired; owner state must be inspected' >&2
exit 78
