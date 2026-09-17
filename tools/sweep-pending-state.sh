#!/bin/sh
# Property sweep over the boot-time predicates in pending-state.sh.
#
# The contract test beside the library asks what a predicate answers for the
# codes someone thought of. This asks a different question, over the whole
# input space: for EVERY exit code the client can return, does each predicate
# answer at all, does it answer the same way twice, and do the two answers the
# layer treats as special stay special.
#
# It is the shell counterpart of the library's fuzz targets. libFuzzer does not
# reach here, but the property does, and the surface is small enough to sweep
# exhaustively rather than sample: a process exit status is one byte, so 0..255
# IS the whole space. Nothing is left to chance and nothing is claimed beyond
# it -- the boot environment is held at one valid shape throughout, so this
# sweep says nothing about environment corruption, which needs a real
# device.
#
# Properties, each checked for every code:
#   1. every predicate exits 0 or 1 -- never another status, never a signal
#   2. every predicate answers the same way twice in a row; each one asks the
#      client again, so an unstable answer would mean the predicate itself
#      carries state it should not
#   3. the idle code claims nothing pending -- an idle device with a pending
#      predicate true is the contradiction the whole confirm chain exists to
#      prevent
#   4. the fatal code claims nothing pending either -- it means the client was
#      never successfully asked, and reading it as a state would spend a trial
#      budget on no evidence
#   5. every predicate answers "yes" for at least one code somewhere in the
#      sweep. Without this the sweep can pass while reaching nothing: a client
#      the library cannot execute makes every predicate answer "no" for every
#      code, stably and consistently, and properties 1 to 4 all hold vacuously.
#      That happened once while this script was being written, which is why the
#      check is here rather than in a reviewer's head.
#
# Usage: sweep-pending-state.sh <path-to-pending-state.sh>
# Exit codes: 0 all properties held, 1 a property failed, 2 usage or setup.
set -u

LIB=${1:-}
[ -n "$LIB" ] || { echo "usage: sweep-pending-state.sh <path-to-pending-state.sh>" >&2; exit 2; }
[ -r "$LIB" ] || { echo "ERROR: $LIB not readable" >&2; exit 2; }

command -v timeout >/dev/null 2>&1 || {
    echo "ERROR: timeout(1) is required -- without it a hung predicate looks like a slow one" >&2
    exit 2
}

tmp=$(mktemp -d) || exit 2
trap 'rm -rf "$tmp"' EXIT INT TERM HUP

# Stub client: answers --update_reboot_state with the staged code. Any other
# verb is a finding rather than a default, because a predicate that reaches for
# a second verb is doing more than reading a state.
cat > "$tmp/fs-updater" <<EOF
#!/bin/sh
case "\${1:-}" in
    --update_reboot_state) exit "\$(cat "$tmp/state-rc")" ;;
    *) echo "unexpected verb \${1:-}" >> "$tmp/unexpected"; exit 99 ;;
esac
EOF
chmod 0755 "$tmp/fs-updater"

# One valid environment, held constant: this sweep varies the client's answer,
# not the environment.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/fw_printenv" <<EOF
#!/bin/sh
case "\${2:-}" in
    application)    echo A ;;
    BOOT_ORDER)     echo "A B" ;;
    BOOT_ORDER_OLD) echo "A B" ;;
    update)         echo 0000 ;;
    BOOT_A_LEFT)    echo 3 ;;
    BOOT_B_LEFT)    echo 3 ;;
    *)              exit 1 ;;
esac
EOF
chmod 0755 "$tmp/bin/fw_printenv"
PATH="$tmp/bin:$PATH"
export PATH

# The library resolves the client through a path variable, not through PATH.
# Prepending PATH alone leaves it calling the device path, which does not exist
# here -- every predicate would then answer "no" for every code, and the whole
# sweep would pass while testing nothing. Property 5 below exists so that this
# can never again look like success.
FUS_UPDATER_BIN="$tmp/fs-updater"
export FUS_UPDATER_BIN

echo 0 > "$tmp/state-rc"

# The predicates that answer "is something pending". They are the ones
# properties 3 and 4 constrain; the rest are swept for 1 and 2 only.
pending_predicates='app_update_pending fw_update_pending app_fw_update_pending
    fw_rollback_pending app_rollback_pending app_fw_rollback_pending
    update_failed_pending app_update_indeterminate app_rollback_indeterminate
    fw_guard_pending update_reboot_outstanding'

# Every predicate the sweep drives. app_update_pending_atboot is included
# because the boot guard uses it in place of its sibling.
all_predicates="$pending_predicates app_update_pending_atboot"

IDLE_CODE=27
FATAL_CODE=124

fail=0
checked=0

# Each call runs in its own shell so a predicate cannot leak state into the
# next one through the sweep's own environment -- which would make property 2
# pass for the wrong reason.
ask() { # ask <predicate> -> prints the exit status, or "hang"
    _rc=0
    timeout --signal=KILL 10 sh -c '
        . "$1" >/dev/null 2>&1 || exit 90
        "$2" >/dev/null 2>&1
    ' _ "$LIB" "$1" || _rc=$?
    if [ "$_rc" = 137 ]; then
        printf 'hang\n'
    else
        printf '%s\n' "$_rc"
    fi
}

code=0
while [ "$code" -le 255 ]; do
    echo "$code" > "$tmp/state-rc"
    for p in $all_predicates; do
        first=$(ask "$p")
        second=$(ask "$p")
        checked=$((checked + 1))

        case "$first" in
            0|1) : ;;
            hang)
                echo "FAIL: $p hung on code $code" >&2
                fail=1
                continue
                ;;
            *)
                echo "FAIL: $p answered status $first on code $code -- predicates answer 0 or 1" >&2
                fail=1
                continue
                ;;
        esac

        if [ "$first" != "$second" ]; then
            echo "FAIL: $p answered $first then $second on code $code -- an unstable predicate" >&2
            fail=1
        fi

        # Property 5's evidence, collected as the sweep goes.
        [ "$first" = 0 ] && echo "$p" >> "$tmp/said-yes"

        case " $pending_predicates " in
            *" $p "*)
                if [ "$code" = "$IDLE_CODE" ] && [ "$first" = 0 ]; then
                    echo "FAIL: $p is true on the idle code" >&2
                    fail=1
                fi
                if [ "$code" = "$FATAL_CODE" ] && [ "$first" = 0 ]; then
                    echo "FAIL: $p is true on the fatal code -- it is not a state" >&2
                    fail=1
                fi
                ;;
        esac
    done
    code=$((code + 1))
done

# Property 5: a predicate that never said yes was never really exercised.
for p in $all_predicates; do
    if ! grep -qx "$p" "$tmp/said-yes" 2>/dev/null; then
        echo "FAIL: $p never answered yes for any code -- the sweep did not reach it" >&2
        fail=1
    fi
done

if [ -s "$tmp/unexpected" ]; then
    echo "FAIL: a predicate reached for a verb beyond the state read:" >&2
    sort -u "$tmp/unexpected" >&2
    fail=1
fi

if [ "$fail" -ne 0 ]; then
    echo "sweep-pending-state: FAILED" >&2
    exit 1
fi
echo "sweep-pending-state: ok ($checked predicate answers over 256 codes)"
