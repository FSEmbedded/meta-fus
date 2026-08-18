#!/bin/sh
# Host-side contract test for pending-state.sh's predicates.
# Nothing here ships to any image: it sources the library against a stub
# fs-updater in a temp dir whose --update_reboot_state exit code is staged
# per case; every other verb is recorded as unexpected and fails, so each
# case proves which verb a predicate actually issued, not just what it
# returned.
# Usage: test-pending-state.sh <path-to-pending-state.sh>
set -u

LIB=${1:?usage: $0 <path-to-pending-state.sh>}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

# Stub fs-updater: --update_reboot_state exits with the staged code and
# records itself; --set_app_state_bad records the slot it was handed and
# exits with its own staged code; anything else is recorded as unexpected
# and fails.
cat > "$tmp/fs-updater" <<EOF
#!/bin/sh
case "\${1:-}" in
    --update_reboot_state)
        echo state >> "$tmp/verbs"
        exit "\$(cat "$tmp/state-rc")"
        ;;
    --set_app_state_bad)
        echo "bad:\${2:-}" >> "$tmp/verbs"
        exit "\$(cat "$tmp/mark-rc")"
        ;;
    --commit_update)
        echo commit >> "$tmp/verbs"
        exit "\$(cat "$tmp/commit-rc")"
        ;;
    *)
        echo "unexpected \${1:-}" >> "$tmp/verbs"
        exit 99
        ;;
esac
EOF
chmod 0755 "$tmp/fs-updater"

# Stub fw_printenv: the library reads the slot pointer, both boot orders and
# both boot budgets through it, so the stub branches on the variable name.
# A staged file that does not exist makes the stub fail like the real tool,
# which is how the fail-closed paths are reached. PATH is prepended so the
# stub shadows any real one.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/fw_printenv" <<EOF
#!/bin/sh
case "\${2:-}" in
    application)    cat "$tmp/application" ;;
    BOOT_ORDER)     cat "$tmp/boot-order" ;;
    BOOT_ORDER_OLD) cat "$tmp/boot-order-old" ;;
    update)         cat "$tmp/update" ;;
    BOOT_A_LEFT)    cat "$tmp/left-a" ;;
    BOOT_B_LEFT)    cat "$tmp/left-b" ;;
    *)              exit 1 ;;
esac
EOF
chmod 0755 "$tmp/bin/fw_printenv"
PATH="$tmp/bin:$PATH"
export PATH

FUS_UPDATER_BIN="$tmp/fs-updater"
export FUS_UPDATER_BIN
FUS_PROC_CMDLINE="$tmp/cmdline"
export FUS_PROC_CMDLINE
# shellcheck disable=SC1090  # path comes from argv; the library is linted on its own
. "$LIB"

fails=0
run_case() {
    # run_case <name> <predicate> <state-rc> <expect-rc>
    name=$1 fn=$2 state_rc=$3 want=$4
    printf '%s\n' "$state_rc" > "$tmp/state-rc"
    : > "$tmp/verbs"
    "$fn"
    rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || { echo "  returned $rc, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "state" ] || {
        echo "  invoked [$verbs], expected [state]"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

run_case "atboot 24 (app pending) is pending"              app_update_pending_atboot 24 0
run_case "atboot 25 (app+fw pending) is pending"           app_update_pending_atboot 25 0
run_case "atboot 55 (update indeterminate) is pending"     app_update_pending_atboot 55 0
run_case "atboot 57 (rollback indeterminate) not pending"  app_update_pending_atboot 57 1
run_case "atboot 27 (no update) is not pending"            app_update_pending_atboot 27 1
run_case "atboot 23 (fw-only) is not pending (app set)"    app_update_pending_atboot 23 1

# Regression pin: the post-mount predicate keeps its own {24, 25} set --
# the indeterminate code must not count as pending there.
run_case "app_update_pending 55 is not pending"            app_update_pending 55 1
run_case "app_update_pending 24 is pending"                app_update_pending 24 0

# The combined-only predicate: exactly rc 25, no set membership.
run_case "app_fw_update_pending 25 (combined) is pending"  app_fw_update_pending 25 0
run_case "app_fw_update_pending 23 (fw-only) not combined" app_fw_update_pending 23 1
run_case "app_fw_update_pending 24 (app-only) not combined" app_fw_update_pending 24 1
run_case "app_fw_update_pending 55 (indeterminate) not combined" app_fw_update_pending 55 1

# An uninterpretable durable state answers 124, not the idle code. Every
# predicate is a positive-list membership test, so none of them may claim a
# pending dimension on a state nobody could read -- acting on a guess is
# exactly what the recovery state exists to prevent.
run_case "atboot 124 (not interpretable) is not pending"   app_update_pending_atboot 124 1
run_case "app_update_pending 124 is not pending"           app_update_pending 124 1
run_case "fw_update_pending 124 is not pending"            fw_update_pending 124 1
run_case "fw_guard_pending 124 is not pending"             fw_guard_pending 124 1
run_case "app_fw_update_pending 124 is not combined"       app_fw_update_pending 124 1

# The quarantine helper: it must mark the slot the device is running, and
# must fail open rather than propagate a refusal to its caller's boot.
mark_case() {
    # mark_case <name> <application> <mark-rc> <expect-rc> <expect-verbs>
    name=$1 app=$2 mark_rc=$3 want=$4 want_verbs=$5
    printf '%s\n' "$app" > "$tmp/application"
    # The quarantine helper reports the digit it produced, so the stub has to
    # answer for it -- otherwise the read fails and the line reports nothing.
    printf '%s\n' "0100" > "$tmp/update"
    printf '%s\n' "$mark_rc" > "$tmp/mark-rc"
    : > "$tmp/verbs"
    app_mark_running_slot_bad >/dev/null 2>&1
    rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || { echo "  returned $rc, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "$want_verbs" ] || {
        echo "  invoked [$verbs], expected [$want_verbs]"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

mark_case "marks the running slot A"            A 52 0 "bad:A"
mark_case "marks the running slot B"            B 52 0 "bad:B"
mark_case "lowercase slot letter is accepted"   b 52 0 "bad:B"
mark_case "a refused mark fails open"           A 53 1 "bad:A"
mark_case "unreadable slot marks nothing"       "" 52 1 ""

# The fallback detector: it must answer from the staged command line and
# boot order alone -- never by invoking fs-updater -- and fail closed on
# every doubt.
revert_case() {
    # revert_case <name> <cmdline|-> <order|-> <order-old|-> <a-left|-> <b-left|-> <expect-rc>
    # "-" stages no file at all: for <cmdline> the read fails, for every
    # other field the fw_printenv stub itself exits non-zero.
    name=$1 cmdline=$2 order=$3 order_old=$4 left_a=$5 left_b=$6 want=$7
    if [ "$cmdline" = "-" ]; then
        rm -f "$tmp/cmdline"
    else
        printf '%s\n' "$cmdline" > "$tmp/cmdline"
    fi
    for _f in "boot-order:$order" "boot-order-old:$order_old" \
              "left-a:$left_a" "left-b:$left_b"; do
        _n=${_f%%:*}; _v=${_f#*:}
        if [ "$_v" = "-" ]; then rm -f "$tmp/$_n"; else printf '%s\n' "$_v" > "$tmp/$_n"; fi
    done
    : > "$tmp/verbs"
    revert_boot_detected
    rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || { echo "  returned $rc, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "" ] || {
        echo "  invoked [$verbs], expected no fs-updater call"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

# Realistic command lines, modeled on a running board; the token must be
# found by name, not position, so it is tested both last and mid-line.
cmdline_tail="console=ttymxc1,115200 login_tty=ttymxc1,115200 undef root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh rauc.slot=A"
cmdline_mid="console=ttymxc1,115200 rauc.slot=A root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh"
cmdline_none="console=ttymxc1,115200 root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh"
cmdline_empty="console=ttymxc1,115200 root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh rauc.slot="
# A repeated parameter resolves to its LAST occurrence, matching the
# kernel's own handling; staged so first-wins (B, equal to the order head)
# would answer "not detected" while last-wins (A) detects.
cmdline_twice="console=ttymxc1,115200 rauc.slot=B root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh rauc.slot=A"

cmdline_bogus="console=ttymxc1,115200 root=PARTUUID=171db42c-01 rauc.slot=X"

# The canonical fallback: booted A, the order leads with B, the PREVIOUS
# order led with A, the two differ, and B's budget is spent to zero.
revert_case "full fallback: detected"                       "$cmdline_tail"  "B A" "A B" 3 0 0
revert_case "token mid-line, full fallback: detected"       "$cmdline_mid"   "B A" "A B" 3 0 0
revert_case "repeated token, last occurrence wins: detected" "$cmdline_twice" "B A" "A B" 3 0 0
revert_case "booted slot equals the order head: not detected" "$cmdline_tail" "A B" "B A" 3 0 1
revert_case "no rauc.slot token: not detected"              "$cmdline_none"  "B A" "A B" 3 0 1
revert_case "empty rauc.slot value: not detected"           "$cmdline_empty" "B A" "A B" 3 0 1
revert_case "unrecognised slot name: not detected"          "$cmdline_bogus" "B A" "A B" 3 0 1
revert_case "command line unreadable: not detected"         "-"              "B A" "A B" 3 0 1
revert_case "boot order read fails: not detected"           "$cmdline_tail"  "-"   "A B" 3 0 1
revert_case "previous boot order read fails: not detected"  "$cmdline_tail"  "B A" "-"   3 0 1

# The conjuncts that separate a fallback from an update merely installed.
# Without these the detector answers yes in the install window, and the
# commit that follows discards the fresh update as a failed one.
revert_case "budgets pristine (install window): not detected" "$cmdline_tail" "B A" "A B" 3 3 1
revert_case "orders identical (nothing moved): not detected"  "$cmdline_tail" "B A" "B A" 3 0 1
revert_case "booted slot is not the previous head: not detected" "$cmdline_tail" "B A" "C A" 3 0 1
# Mirrors the condition commit itself applies -- either budget at zero, not
# specifically the intended slot's. Not physically reachable (the bootloader
# would not have booted a slot with no attempts left), staged to pin that the
# layer asks the same question the commit will.
revert_case "the other budget at zero: detected"             "$cmdline_tail" "B A" "A B" 0 3 0
revert_case "non-numeric budget: not detected"               "$cmdline_tail" "B A" "A B" 3 x 1
revert_case "budget read fails: not detected"                "$cmdline_tail" "B A" "A B" 3 "-" 1
revert_case "boot order empty: not detected"                "$cmdline_tail" ""       "A B" 3 0 1
# Padding must not defeat the field split: with the same head as the booted
# slot this can only answer "not detected" if the leading field was taken.
revert_case "boot order padded, same head: not detected"    "$cmdline_tail" "  A B  " "B A" 3 0 1
revert_case "previous order padded, same head: detected"    "$cmdline_tail" "B A"    "  A B  " 3 0 0

# Install into a slot drained while idle, then a fallback to the running one:
# the install anchors both orders on the running slot before the primary
# moves, so they differ afterwards and the fallback is recognised. With the
# orders still equal (no anchor) it is not, and the confirm chain would keep
# rebooting until the surviving slot's budget is gone.
cmdline_booted_b="console=ttymxc1,115200 root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh rauc.slot=B"
revert_case "idle-drained slot fell back, orders anchored: detected" "$cmdline_booted_b" "A B" "B A" 0 3 0
revert_case "idle-drained slot fell back, orders equal: not detected" "$cmdline_booted_b" "A B" "A B" 0 3 1

# The state readers the caller-facing verbs branch on. The reader must hand
# back the code it was given and ask exactly once; the set test must answer
# from that code alone and never reach for the CLI, or a verb branching twice
# would ask twice and could be handed two different answers.
read_case() {
    # read_case <name> <state-rc> <expect-echo>
    name=$1 state_rc=$2 want=$3
    printf '%s\n' "$state_rc" > "$tmp/state-rc"
    : > "$tmp/verbs"
    got=$(updater_state_rc)
    ok=1
    [ "$got" = "$want" ] || { echo "  read $got, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "state" ] || {
        echo "  invoked [$verbs], expected [state]"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

run_case "55 is the indeterminate update"                  app_update_indeterminate 55 0
run_case "57 is not an indeterminate update"               app_update_indeterminate 57 1
run_case "24 is determinate, not indeterminate"            app_update_indeterminate 24 1
run_case "the settled code is not indeterminate"           app_update_indeterminate 27 1
run_case "57 is the indeterminate rollback"                app_rollback_indeterminate 57 0
run_case "55 is not an indeterminate rollback"             app_rollback_indeterminate 55 1
run_case "a decided rollback is not indeterminate"         app_rollback_indeterminate 29 1

read_case "the reader hands back a pending code"     24 24
read_case "the reader hands back the settled code"   27 27
read_case "the reader hands back an unknown code"    99 99

set_case() {
    # set_case <name> <rc> <set> <expect-rc>
    name=$1 rc=$2 set=$3 want=$4
    : > "$tmp/verbs"
    rc_in_set "$rc" "$set"
    got=$?
    ok=1
    [ "$got" -eq "$want" ] || { echo "  returned $got, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "" ] || {
        echo "  invoked [$verbs], expected no fs-updater call"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

set_case "a member of the pending set"        24 "$APP_PENDING_CODES" 0
set_case "the other member of that set"       25 "$APP_PENDING_CODES" 0
set_case "the settled code is not a member"   27 "$APP_PENDING_CODES" 1
set_case "an unknown code is not a member"    99 "$APP_PENDING_CODES" 1

# Reachability answers without asking anything: it is what separates "nothing
# is pending" from "the state could not be read".
reach_case() {
    # reach_case <name> <path> <expect-rc>
    name=$1 path=$2 want=$3
    FS_UPDATER=$path
    : > "$tmp/verbs"
    updater_reachable
    got=$?
    # shellcheck disable=SC2034  # read by the sourced library on later cases
    FS_UPDATER="$tmp/fs-updater"
    ok=1
    [ "$got" -eq "$want" ] || { echo "  returned $got, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "" ] || {
        echo "  invoked [$verbs], expected no fs-updater call"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

# The commit verb's success set. Until now nothing drove it, so which codes
# count as "the commit completed" rested on the comment above the list. The
# distinction is load-bearing in both directions: a completed outcome missing
# from the set is retried on every boot, and a discarded one wrongly inside it
# records a device as running firmware it never booted.
run_commit_case() {
    # run_commit_case <name> <commit-rc> <expect-rc>
    name=$1 commit_rc=$2 want=$3
    printf '%s\n' "$commit_rc" > "$tmp/commit-rc"
    : > "$tmp/verbs"
    commit_update_ok
    rc=$?
    ok=1
    [ "$rc" -eq "$want" ] || { echo "  returned $rc, expected $want"; ok=0; }
    verbs=$(cat "$tmp/verbs")
    [ "$verbs" = "commit" ] || {
        echo "  invoked [$verbs], expected [commit]"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

run_commit_case "16 (committed) completes the commit"          16 0
run_commit_case "17 (nothing to do) completes the commit"      17 0
# A device that arrived carrying a state no current flow writes. The commit
# settled it and nothing was discarded, so this chain is done with it; left out
# of the set, the confirm would read a completed migration as a failed commit
# and try again on every boot -- which is what made that state a dead end.
run_commit_case "59 (legacy state migrated) completes it too"  59 0
# Deliberately NOT complete: there an install was discarded and the device runs
# the firmware it ran before. Counting it as success would record the device as
# running firmware it never booted.
run_commit_case "58 (stalled install settled) does not"        58 1
run_commit_case "18 (state not allowed) does not"              18 1

reach_case "an executable updater is reachable"  "$tmp/fs-updater"   0
reach_case "an absent updater is not"            "$tmp/does-not-exist" 1
reach_case "a non-executable file is not"        "$tmp/state-rc"     1

if [ "$fails" -ne 0 ]; then
    echo "pending-state contract test: $fails case(s) FAILED"
    exit 1
fi
echo "pending-state contract test: all cases passed"
