#!/bin/sh
# Host-side contract test for the two shell entry points of the update door:
# fus-update-confirm's verbs and fus-app-container-runtime's boot guard.
#
# Nothing here ships to any image. Both scripts are driven against a stub
# fs-updater, a stub fw_printenv and a stub systemctl in a temp dir, exactly
# as the runtime oeqa case stages them in a guest -- but without a kernel,
# because none of these paths need one: they read exit codes, environment
# variables and one counter file. The mount admission gate is the part that
# does need a kernel, and it stays in the runtime suite.
#
# The boot guard belongs to a different recipe, so its script is not in this
# one's work directory: pass it to cover the trial-budget cases too. Left out,
# those cases are skipped and say so -- a gate that quietly covers less than it
# looks like is worse than one that admits the gap.
#
# Usage: test-update-confirm.sh <fus-update-confirm> <pending-state.sh> [fus-app-container-runtime]
set -u

CONFIRM_SRC=${1:?usage: $0 <fus-update-confirm> <pending-state.sh> [fus-app-container-runtime]}
LIB_SRC=${2:?missing pending-state.sh}
RUNTIME_SRC=${3:-}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir -p "$tmp/bin" "$tmp/app"
cp "$CONFIRM_SRC" "$tmp/bin/fus-update-confirm"
cp "$LIB_SRC" "$tmp/pending-state.sh"
chmod 0755 "$tmp/bin/fus-update-confirm"
if [ -n "$RUNTIME_SRC" ]; then
    # Under its real name, so the wrapper's best-effort `command -v` dispatch
    # to the trial-counter reset resolves exactly as it does on a device.
    cp "$RUNTIME_SRC" "$tmp/bin/fus-app-container-runtime"
    chmod 0755 "$tmp/bin/fus-app-container-runtime"
fi

# Stub fs-updater: --update_reboot_state exits with the staged code; the
# state-changing verbs record themselves and exit with their own staged codes,
# defaulting to the real CLI's success codes (16 commit, 12 rollback, 52 mark)
# so an unstaged case exercises the genuine success path, not the exit 0 the
# real binary never returns. The mark records its slot argument, since which
# slot it names is the point.
cat > "$tmp/fs-updater" <<EOF
#!/bin/sh
case "\${1:-}" in
    --update_reboot_state) exit "\$(cat "$tmp/state-rc")" ;;
    --commit_update)
        echo "\$1" >> "$tmp/calls"
        exit "\$(cat "$tmp/commit-rc")" ;;
    --rollback_update)
        echo "\$1" >> "$tmp/calls"
        exit "\$(cat "$tmp/rollback-rc")" ;;
    --set_app_state_bad)
        echo "\$1 \${2:-}" >> "$tmp/calls"
        exit "\$(cat "$tmp/mark-rc" 2>/dev/null || echo 52)" ;;
    *) echo "unexpected \${1:-}" >> "$tmp/calls"; exit 99 ;;
esac
EOF

# Stub fw_printenv -n <var>: the slot pointer is read by the trial derivation
# and the quarantine mark, the two boot orders and budgets by the fallback
# detector. A staged file that does not exist makes the stub fail like the
# real tool, which is how the fail-closed paths are reached.
cat > "$tmp/bin/fw_printenv" <<EOF
#!/bin/sh
case "\${2:-}" in
    application)    cat "$tmp/application" 2>/dev/null || exit 1 ;;
    BOOT_ORDER)     cat "$tmp/boot-order" ;;
    BOOT_ORDER_OLD) cat "$tmp/boot-order-old" ;;
    BOOT_A_LEFT)    cat "$tmp/left-a" ;;
    BOOT_B_LEFT)    cat "$tmp/left-b" ;;
    *)              exit 1 ;;
esac
EOF

cat > "$tmp/bin/systemctl" <<EOF
#!/bin/sh
case "\${1:-}" in
    reboot) echo reboot >> "$tmp/reboot-calls" ;;
esac
EOF
chmod 0755 "$tmp/fs-updater" "$tmp/bin/fw_printenv" "$tmp/bin/systemctl"

PATH="$tmp/bin:$PATH"
export PATH
FUS_UPDATER_BIN="$tmp/fs-updater";        export FUS_UPDATER_BIN
FUS_PENDING_STATE_LIB="$tmp/pending-state.sh"; export FUS_PENDING_STATE_LIB
FUS_PROC_CMDLINE="$tmp/cmdline";          export FUS_PROC_CMDLINE
FUS_APP_CONTAINER_BASE="$tmp/app";        export FUS_APP_CONTAINER_BASE
FUS_APP_TRIALS_FILE="$tmp/app/trials";    export FUS_APP_TRIALS_FILE
FUS_APP_IMG_DIR="$tmp/app/images";        export FUS_APP_IMG_DIR
FUS_APP_CURRENT="$tmp/app/current";       export FUS_APP_CURRENT
FUS_APP_MOUNT="$tmp/merged";              export FUS_APP_MOUNT
FUS_TRIALS=3;                             export FUS_TRIALS

# The booted slot is fixed at B; which way the fallback detector decides is
# chosen per case through the staged boot order.
CMDLINE="console=ttymxc1,115200 root=PARTUUID=171db42c-01 rootwait ro init=/sbin/preinit.sh rauc.slot=B"

fails=0
case_name=""
case_bad=0

start() { case_name=$1; case_bad=0; }

ck() { # ck <what> <want> <got>
    [ "$2" = "$3" ] && return 0
    echo "  $1: want [$2] got [$3]"
    case_bad=1
}

done_case() {
    if [ "$case_bad" -eq 0 ]; then
        echo "PASS: $case_name"
    else
        echo "FAIL: $case_name"
        fails=$((fails + 1))
    fi
}

arm() { # arm <state> [trials|-] [target|-] [commit-rc] [rollback-rc] [fallback 0|1] [slot|-]
    _a_state=$1
    _a_trials=${2:--}
    _a_target=${3:--}
    _a_crc=${4:-16}
    _a_rrc=${5:-12}
    _a_fb=${6:-0}
    _a_slot=${7:-A}

    printf '%s\n' "$_a_state" > "$tmp/state-rc"
    printf '%s\n' "$_a_crc"   > "$tmp/commit-rc"
    printf '%s\n' "$_a_rrc"   > "$tmp/rollback-rc"
    printf '%s\n' "$CMDLINE"  > "$tmp/cmdline"

    # The default is a HEALTHY boot: the booted slot leads the order, the two
    # orders agree, both budgets are pristine. fallback=1 stages a COMPLETE
    # fallback -- the order leads with A while B booted, the previous order led
    # with B, and A's budget is spent -- because the detector asks all four
    # questions and a partial staging would silently miss the branch. A is the
    # slot the update went to and failed on; B is the proven one it fell back to.
    if [ "$_a_fb" -eq 1 ]; then
        printf 'A B\n' > "$tmp/boot-order"
        printf 'B A\n' > "$tmp/boot-order-old"
        printf '0\n'   > "$tmp/left-a"
        printf '3\n'   > "$tmp/left-b"
    else
        printf 'B A\n' > "$tmp/boot-order"
        printf 'B A\n' > "$tmp/boot-order-old"
        printf '3\n'   > "$tmp/left-a"
        printf '3\n'   > "$tmp/left-b"
    fi

    : > "$tmp/calls"
    : > "$tmp/reboot-calls"

    # "-" removes the file, so every read of the slot fails: the unreadable
    # environment case.
    if [ "$_a_slot" = "-" ]; then
        rm -f "$tmp/application"
    else
        printf '%s\n' "$_a_slot" > "$tmp/application"
    fi

    mkdir -p "$tmp/app/images"
    # Both slots present by default: the reject verb checks the slot its revert
    # would select, and only the cases about that check stage anything else.
    for _a_s in a b; do
        printf 'payload\n' > "$tmp/app/images/app_$_a_s.squashfs"
        for _a_x in verity roothash roothash.p7s; do
            printf 'x\n' > "$tmp/app/images/app_$_a_s.squashfs.$_a_x"
        done
    done

    if [ "$_a_trials" = "-" ]; then
        rm -f "$tmp/app/trials"
    elif [ "$_a_target" = "-" ]; then
        # Untagged: both the pre-derivation on-disk form and the inherit case.
        printf 'trials=%s\n' "$_a_trials" > "$tmp/app/trials"
    else
        printf 'trials=%s\ntarget=%s\n' "$_a_trials" "$_a_target" > "$tmp/app/trials"
    fi
}

run_confirm() { sh "$tmp/bin/fus-update-confirm" "$1" >/dev/null 2>&1; rc=$?; }

# Same call with both streams kept: the wrapper logs to stderr, and a case
# about what it says must not depend on which stream a harness happens to
# keep.
run_confirm_out() {
    sh "$tmp/bin/fus-update-confirm" "$1" > "$tmp/out" 2>&1
    rc=$?
}
said() { # said <word>
    grep -qi -- "$1" "$tmp/out" && echo yes || echo no
}
run_runtime() { sh "$tmp/bin/fus-app-container-runtime" "$@" >/dev/null 2>&1; rc=$?; }

# Same call with both streams kept, for cases about what the guard says.
run_runtime_out() {
    sh "$tmp/bin/fus-app-container-runtime" "$@" > "$tmp/out" 2>&1
    rc=$?
}

calls()   { tr '\n' ' ' < "$tmp/calls" | sed 's/ *$//'; }
reboots() { tr '\n' ' ' < "$tmp/reboot-calls" | sed 's/ *$//'; }
trials()  { sed -n 's/^trials=//p' "$tmp/app/trials" 2>/dev/null; }
target()  { sed -n 's/^target=//p' "$tmp/app/trials" 2>/dev/null; }

# --- confirm: the states it settles and the ones it leaves alone -----------

start "confirm leaves a pending app update to the external verdict"
arm 24 2
run_confirm confirm
ck "calls" "" "$(calls)"
ck "trial counter untouched" "2" "$(trials)"
done_case

start "confirm leaves a pending firmware update to the external verdict"
arm 23
run_confirm confirm
ck "calls" "" "$(calls)"
done_case

start "a combined pending update on a healthy boot stays externalized"
arm 25
run_confirm confirm
ck "calls" "" "$(calls)"
ck "reboots" "" "$(reboots)"
done_case

start "a combined fallback is settled via commit and rebooted"
arm 25 - - 16 12 1
run_confirm confirm
ck "calls" "--commit_update" "$(calls)"
ck "reboots" "reboot" "$(reboots)"
done_case

start "a firmware-only fallback commits without a reboot"
arm 23 - - 16 12 1
run_confirm confirm
ck "calls" "--commit_update" "$(calls)"
ck "reboots" "" "$(reboots)"
done_case

start "an app-only pending update stays externalized under a fallback view"
arm 24 - - 16 12 1
run_confirm confirm
ck "calls" "" "$(calls)"
ck "reboots" "" "$(reboots)"
done_case

start "a failed recovery commit does not reboot"
arm 25 - - 19 12 1
run_confirm confirm
ck "calls" "--commit_update" "$(calls)"
ck "reboots" "" "$(reboots)"
done_case

start "the recovery reboot is one-shot, even with the boot view still disagreeing"
arm 25 - - 16 12 1
run_confirm confirm
ck "first boot reboots" "reboot" "$(reboots)"
arm 27 - - 16 12 1
run_confirm confirm
ck "settled state is not committed again" "" "$(calls)"
ck "settled state does not reboot again" "" "$(reboots)"
done_case

start "a not-yet-rebooted update is never committed under a fallback view"
arm 26 - - 16 12 1
run_confirm confirm
ck "calls" "" "$(calls)"
ck "reboots" "" "$(reboots)"
done_case

for _s in 20 21 22; do
    start "a failed update ($_s) is acknowledged unconditionally"
    arm "$_s"
    run_confirm confirm
    ck "calls" "--commit_update" "$(calls)"
    done_case
done

# The revert was already enacted when this state was written, so an unmountable
# image leaves nothing to validate and the commit settles it on that evidence.
# Until the library learned that, every verb refused and the device parked; the
# case below pinned the naming that was all this layer could do then.
start "confirm settles the rollback whose image will not mount"
arm 57
run_confirm_out confirm
ck "exit" "0" "$rc"
ck "calls" "--commit_update" "$(calls)"
ck "reboots" "" "$(reboots)"
ck "names the rollback" "yes" "$(said rollback)"
ck "does not claim the device is idle" "no" "$(said 'nothing pending')"
done_case

# The backstop reboots for this code in the same boot, so reporting an idle
# device here puts two contradictory lines in the journal: "nothing to do",
# then minutes later "rebooting", over and over until the budget erodes.
start "confirm names the pending update whose image will not mount"
arm 55
run_confirm_out confirm
ck "exit" "0" "$rc"
ck "calls" "" "$(calls)"
ck "reboots" "" "$(reboots)"
ck "names the update" "yes" "$(said 'update')"
ck "does not claim the device is idle" "no" "$(said 'nothing pending')"
done_case

start "confirm keeps quiet about an updater it can still reach"
arm 27
run_confirm_out confirm
ck "exit" "0" "$rc"
ck "says nothing pending" "yes" "$(said 'nothing pending')"
done_case

start "confirm says so when the updater cannot be run"
arm 27
FUS_UPDATER_BIN="$tmp/does-not-exist" run_confirm_out confirm
ck "exit stays a oneshot success" "0" "$rc"
ck "names the unreachable updater" "yes" "$(said 'cannot run the updater')"
done_case

# 26 is not a stored state: the CLI derives it when the stored state says an
# update is installed but is_reboot_complete() answers PENDING. Reaching a
# confirm run with it therefore means the boot did not take effect -- the
# bootloader did not start the target. Nothing here settles that, and nothing
# should: the answer to a reboot that did not happen is not another reboot,
# which is why the deadline stays out of it too. But the run must not report
# an idle device, because an update is installed and waiting.
start "an outstanding reboot is a no-op for confirm"
arm 26
run_confirm_out confirm
ck "calls" "" "$(calls)"
ck "reboots" "" "$(reboots)"
ck "names the outstanding reboot" "yes" "$(said 'reboot')"
ck "does not claim the device is idle" "no" "$(said 'nothing pending')"
done_case

start "the settled state is a no-op for confirm"
arm 27
run_confirm confirm
ck "calls" "" "$(calls)"
done_case

# All six codes are driven, and all six are reachable against a current image:
# each rollback state reports the first code while its reboot is outstanding and
# the second once the commit is requested, and all three rollback states are
# written by a verb. The three states that share a name with the second code of
# each pair have no writer, but no code depends on them. Seeding the code
# directly is what keeps the cases independent of that.
for _s in 28 31 29 32 30 33; do
    start "a decided rollback ($_s) is finalized via commit"
    arm "$_s"
    run_confirm confirm
    ck "calls" "--commit_update" "$(calls)"
    done_case
done

# A taken rollback leaves the boot view indistinguishable from a bootloader
# fallback: the order still leads with the slot that was reverted away from,
# and its budget was forced to zero. The only thing keeping the recovery
# branch out is that these codes sit outside the firmware guard set, so these
# cases stage the view that really occurs and would fail if it were widened.
for _s in 31 32 33; do
    start "a decided rollback ($_s) under a fallback view only finalizes"
    arm "$_s" - - 16 12 1
    run_confirm confirm
    ck "calls" "--commit_update" "$(calls)"
    ck "reboots" "" "$(reboots)"
    done_case
done

# --- deadline: the backstop's set -----------------------------------------

for _s in 20 21 22 23 24 25 28 29 30 31 32 33; do
    start "the deadline reboots for state $_s"
    arm "$_s"
    run_confirm deadline
    ck "reboots" "reboot" "$(reboots)"
    done_case
done

start "the deadline does not reboot when nothing is pending"
arm 27
run_confirm deadline
ck "reboots" "" "$(reboots)"
done_case

# A pending update whose image never mounts answers the same code for the
# whole boot and no verb settles it, so without the backstop the device parks
# with a partially spent budget. The reboot is bounded: the boot guard counts
# an attempt per boot and reverts once the budget is gone.
start "the deadline re-drives a pending update whose image never mounts"
arm 55
run_confirm deadline
ck "reboots" "reboot" "$(reboots)"
done_case

# Its rollback-side sibling must NOT be re-driven: the revert already switched
# the active slot, so every further boot mounts the same unmountable image,
# and the boot guard counts no attempt for it. Parked and reachable beats a
# reboot that repeats forever.
start "the deadline leaves an indeterminate rollback alone"
arm 57
run_confirm deadline
ck "reboots" "" "$(reboots)"
done_case

start "the deadline stays out while a reboot is still outstanding"
arm 26
run_confirm deadline
ck "reboots" "" "$(reboots)"
done_case

# --- commit and reject: what they do, and what they report -----------------

start "commit settles a pending app update and clears the counter"
arm 24 2
run_confirm commit
ck "calls" "--commit_update" "$(calls)"
ck "exit" "0" "$rc"
done_case

start "rc 17 (not needed) is the other success code for a commit"
arm 24 2 - 17
run_confirm commit
ck "calls" "--commit_update" "$(calls)"
ck "exit" "0" "$rc"
done_case

start "a refused commit keeps the counter and says so"
arm 24 2 - 19
run_confirm commit
ck "calls" "--commit_update" "$(calls)"
ck "counter kept" "2" "$(trials)"
ck "exit" "1" "$rc"
done_case

start "commit settles a pending firmware update"
arm 23
run_confirm commit
ck "calls" "--commit_update" "$(calls)"
ck "exit" "0" "$rc"
done_case

start "reject rolls a pending app update back and clears the counter"
arm 24 2
run_confirm reject
ck "calls" "--rollback_update" "$(calls)"
ck "exit" "0" "$rc"
done_case

start "a refused rollback says so"
arm 24 2 - 16 13
run_confirm reject
ck "calls" "--rollback_update" "$(calls)"
ck "exit" "1" "$rc"
done_case

start "reject rolls a pending firmware update back"
arm 23
run_confirm reject
ck "calls" "--rollback_update" "$(calls)"
ck "exit" "0" "$rc"
done_case

for _v in commit reject; do
    start "$_v reports the settled state distinctly"
    arm 27
    run_confirm "$_v"
    ck "exit" "3" "$rc"
    ck "calls" "" "$(calls)"
    done_case
done

# A state exists but these verbs do not serve it. Reporting the settled code
# here would tell a caller the device is doing nothing while an update sits
# on it; 99 stands for anything the layer does not know.
for _s in 26 29 55 57 99; do
    for _v in commit reject; do
        start "$_v reports state $_s as one it cannot settle"
        arm "$_s"
        run_confirm "$_v"
        ck "exit" "4" "$rc"
        ck "calls" "" "$(calls)"
        done_case
    done
done

# Not "a state the layer does not know" but "the tool ran and could not read
# the device's state" -- the distinction this script already draws one case
# below, where the updater cannot be run at all. Reporting it as settled would
# tell a fleet caller the device has nothing to do while nobody can say what
# it has.
for _v in commit reject; do
    start "$_v does not report an unreadable state as settled"
    arm 124
    run_confirm_out "$_v"
    ck "exit" "4" "$rc"
    ck "calls" "" "$(calls)"
    ck "does not claim the device is idle" "no" "$(said 'nothing pending')"
    done_case
done

for _v in commit reject; do
    start "$_v reports an updater it cannot run"
    arm 24 2
    FUS_UPDATER_BIN="$tmp/does-not-exist" run_confirm "$_v"
    ck "exit" "5" "$rc"
    ck "calls" "" "$(calls)"
    done_case
done

start "an unknown verb is a usage error"
arm 27
run_confirm definitely-not-a-verb
ck "exit" "2" "$rc"
done_case

# --- fw-guard: the mark-good gate -----------------------------------------

start "fw-guard gates while a firmware-only update is pending"
arm 23
run_confirm fw-guard
ck "exit" "1" "$rc"
done_case

start "fw-guard gates while a combined update is pending"
arm 25
run_confirm fw-guard
ck "exit" "1" "$rc"
done_case

start "fw-guard does not gate on an app-only pending update"
arm 24
run_confirm fw-guard
ck "exit" "0" "$rc"
done_case

start "fw-guard does not gate when nothing is pending"
arm 27
run_confirm fw-guard
ck "exit" "0" "$rc"
done_case

# The gate covers the firmware dimension only, so for a failed update and for
# every decided rollback it lets mark-good through and the boot budget is
# restored on each boot. That is deliberate -- those states are not a firmware
# update awaiting a verdict -- but it is also what the deadline's boundedness
# rests on NOT being true: if the settle keeps failing for one of these codes,
# the timer re-drives every boot while nothing erodes. These cases pin the
# gating so that widening the set, or relying on erosion here, has to be a
# decision rather than an accident.
for _s in 20 21 22 28 29 30 31 32 33; do
    start "fw-guard leaves mark-good alone for state $_s"
    arm "$_s"
    run_confirm fw-guard
    ck "exit" "0" "$rc"
    done_case
done

# --- boot guard: the app trial budget --------------------------------------

if [ -z "$RUNTIME_SRC" ]; then
    echo "SKIP: boot guard cases -- no runtime script given"
    if [ "$fails" -ne 0 ]; then
        echo "update-confirm contract test: $fails case(s) FAILED"
        exit 1
    fi
    echo "update-confirm contract test: verb cases passed, boot guard skipped"
    exit 0
fi

# Clearing the counter is the runtime's job, asked for by the wrapper: these
# two need the real script, so they live with the boot-guard family.
start "a settled commit has the counter cleared"
arm 24 2
run_confirm commit
ck "counter cleared" "" "$(trials)"
done_case

start "the other success code clears the counter as well"
arm 24 2 - 17
run_confirm commit
ck "counter cleared" "" "$(trials)"
done_case

start "a settled rejection has the counter cleared"
arm 24 2
run_confirm reject
ck "counter cleared" "" "$(trials)"
done_case

# --- the payload check the reject verb leans on -----------------------------
# Its own exit contract, deliberately NOT the mount path's: cmd_mount returns 0
# on every refusal ("never fail the boot"), and a check inheriting that would be
# inert -- it would answer "fine" for an image that is not there at all.

_stage_slot() { # _stage_slot <a|b> <present|missing|empty-sidecar>
    mkdir -p "$tmp/app/images"
    rm -f "$tmp/app/images/app_$1.squashfs"*
    case "$2" in
    present)
        printf 'payload\n' > "$tmp/app/images/app_$1.squashfs"
        for s in verity roothash roothash.p7s; do
            printf 'x\n' > "$tmp/app/images/app_$1.squashfs.$s"
        done ;;
    missing) : ;;
    empty-sidecar)
        printf 'payload\n' > "$tmp/app/images/app_$1.squashfs"
        printf 'x\n' > "$tmp/app/images/app_$1.squashfs.verity"
        printf 'x\n' > "$tmp/app/images/app_$1.squashfs.roothash"
        : > "$tmp/app/images/app_$1.squashfs.roothash.p7s" ;;
    esac
}

start "verify-slot accepts a slot whose payload and sidecars are all there"
_stage_slot b present
run_runtime verify-slot B
ck "exit" "0" "$rc"
done_case

start "verify-slot rejects a slot with no payload at all"
_stage_slot b missing
run_runtime verify-slot B
ck "exit" "3" "$rc"
done_case

start "verify-slot rejects a slot whose signature sidecar is empty"
_stage_slot b empty-sidecar
run_runtime verify-slot B
ck "exit" "3" "$rc"
done_case

start "verify-slot answers cannot-check for a slot name it does not know"
run_runtime verify-slot Q
ck "exit" "2" "$rc"
done_case

start "verify-slot is not the mount path -- it must not answer 0 for a missing image"
_stage_slot a missing
run_runtime verify-slot A
ck "exit" "3" "$rc"
done_case

# --- reject refuses to aim the revert at a slot that is not there ------------

start "reject refuses when the slot the revert would select has no payload"
arm 24 2 - 16 12 0 B
_stage_slot a missing
run_confirm_out reject
ck "exit" "6" "$rc"
ck "the updater was never asked" "" "$(calls)"
ck "names the way out" "yes" "$(said commit)"
done_case

start "reject proceeds when the target slot is there"
arm 24 2 - 16 12 0 B
_stage_slot a present
run_confirm reject
ck "exit" "0" "$rc"
ck "calls" "--rollback_update" "$(calls)"
done_case

# The combined state settles through a path that needs no mount evidence, so the
# guard must stay out of it -- refusing there would block the only firmware
# revert a device with an unusable app slot still has.
# A mixed image -- new confirm, older runtime -- answers the unknown verb with
# its usage code. Reading that as "unusable" would refuse every reject on such
# an image, which is worse than not checking at all.
start "an older runtime without the verb does not block the reject"
arm 24 2 - 16 12 0 B
_stage_slot a missing
cp "$tmp/bin/fus-app-container-runtime" "$tmp/runtime.real"
cat > "$tmp/bin/fus-app-container-runtime" <<'OLD'
#!/bin/sh
case "${1:-}" in
    bootguard|mount|trials-reset) exit 0 ;;
    *) echo "usage: $0 {bootguard|mount|trials-reset}" >&2; exit 2 ;;
esac
OLD
chmod 0755 "$tmp/bin/fus-app-container-runtime"
run_confirm reject
ck "exit" "0" "$rc"
ck "calls" "--rollback_update" "$(calls)"
cp "$tmp/runtime.real" "$tmp/bin/fus-app-container-runtime"
done_case

start "reject does not guard the combined state"
arm 25 - - 16 12 0 B
_stage_slot a missing
run_confirm reject
ck "exit" "0" "$rc"
ck "calls" "--rollback_update" "$(calls)"
done_case

start "the guard decrements, then reverts at exhaustion"
arm 24
run_runtime bootguard
ck "after one boot" "2" "$(trials)"
run_runtime bootguard
ck "after two boots" "1" "$(trials)"
: > "$tmp/calls"
run_runtime bootguard
ck "calls" "--set_app_state_bad A --rollback_update" "$(calls)"
ck "counter cleared after the revert" "" "$(trials)"
done_case

start "a settled state clears a stale counter"
arm 27 1
run_runtime bootguard
ck "calls" "" "$(calls)"
ck "counter cleared" "" "$(trials)"
done_case

start "an indeterminate pending update counts a trial"
arm 55
run_runtime bootguard
ck "counter" "2" "$(trials)"
done_case

start "an indeterminate rollback counts nothing"
arm 57 1
run_runtime bootguard
ck "calls" "" "$(calls)"
ck "counter cleared" "" "$(trials)"
done_case

# A decided rollback is not an update, and the guard must not spend the
# application's budget on it: the revert has already happened, and the verb its
# exhaustion branch would fire refuses in that state. Both codes, because 32 is
# reachable before the mount through the bitfield shortcut and 29 through the
# mount evidence -- the guard really can be handed either.
for _s in 29 32; do
    start "a decided rollback ($_s) counts nothing at boot"
    arm "$_s" 1
    run_runtime bootguard
    ck "calls" "" "$(calls)"
    ck "counter cleared" "" "$(trials)"
    done_case
done

# The branch that counts nothing used to say nothing, so the only way to learn
# what the guard had seen on a device was to instrument it. It names the code.
start "the guard says which state it counted nothing for"
arm 32 1
run_runtime_out bootguard
ck "names the state" "yes" "$(said 'state 32')"
ck "says nothing was counted" "yes" "$(said 'no attempt counted')"
done_case

# An updater that died on an exception reported nothing about the device.
# Letting that fall through to "not pending" clears the counter, and then the
# budget cannot erode and a wedging update never reverts on its own. The
# counter has to survive an answer that was never given.
start "a fatal updater answer leaves the counter alone"
arm 124 1
run_runtime bootguard
ck "calls" "" "$(calls)"
ck "counter kept" "1" "$(trials)"
done_case

# The same rule one step earlier: no updater at all. The caller-facing verbs of
# this door check reachability before they act; the guard did not, so a missing
# binary took the budget with it.
start "an unrunnable updater leaves the counter alone"
arm 24 1
FUS_UPDATER_BIN="$tmp/does-not-exist" run_runtime bootguard
ck "calls" "" "$(calls)"
ck "counter kept" "1" "$(trials)"
done_case

start "a failed revert keeps the exhausted counter"
arm 24 1 - 16 14
run_runtime bootguard
ck "calls" "--set_app_state_bad A --rollback_update" "$(calls)"
ck "counter kept" "1" "$(trials)"
done_case

# A counter that cannot be persisted grants an UNBOUNDED budget: the next boot
# reads the default again, the countdown never reaches zero, and a wedging
# application update never reverts. The guard must say so rather than report a
# value it did not store -- a log line claiming "trials now N" for a write that
# failed is the same class of defect as a check that passes when its subject is
# absent, on the writing side.
start "a counter that cannot be written is reported, not silently granted"
arm 24
_saved=$tmp/app.saved
mv "$tmp/app" "$_saved"
: > "$tmp/app"          # the base is now a file: mkdir -p and the write both fail
run_runtime_out bootguard
ck "the guard names the failure" "yes" "$(said 'could not be')"
ck "no value is claimed for an unstored counter" "no" "$(said 'trials now')"
rm -f "$tmp/app"
mv "$_saved" "$tmp/app"
done_case

start "a new target starts from a fresh budget"
arm 24 1 A 16 12 0 B
run_runtime bootguard
ck "calls" "" "$(calls)"
ck "counter" "2" "$(trials)"
ck "tagged with its own slot" "B" "$(target)"
done_case

start "an untagged counter is inherited, not refreshed"
arm 24 1 - 16 12 0 A
run_runtime bootguard
ck "calls" "--set_app_state_bad A --rollback_update" "$(calls)"
done_case

start "an unreadable slot keeps charging the recorded budget"
arm 24 2 A 16 12 0 -
run_runtime bootguard
ck "counter" "1" "$(trials)"
ck "tag untouched" "A" "$(target)"
done_case

start "two cycles back to back do not share a budget"
arm 24 - - 16 12 0 B
run_runtime bootguard
ck "first cycle counter" "2" "$(trials)"
ck "first cycle tag" "B" "$(target)"
# Committed through the library (the state settles, the counter stays), then
# the next update installed and rebooted into: no boot in between ever sees a
# settled state, so nothing clears the counter.
printf '24\n' > "$tmp/state-rc"
printf 'A\n'  > "$tmp/application"
: > "$tmp/calls"
run_runtime bootguard
ck "second cycle counter" "2" "$(trials)"
ck "second cycle tag" "A" "$(target)"
ck "no revert on a fresh budget" "" "$(calls)"
done_case

start "a reused target inherits the remainder"
arm 24 2 B 16 12 0 B
run_runtime bootguard
ck "counter" "1" "$(trials)"
done_case

start "exhaustion reverts even when the slot cannot be read"
arm 24 1 A 16 12 0 -
run_runtime bootguard
ck "calls" "--rollback_update" "$(calls)"
ck "counter cleared" "" "$(trials)"
done_case

start "a slot case flip is the same target"
arm 24 2 A 16 12 0 a
run_runtime bootguard
ck "counter" "1" "$(trials)"
done_case

# --- boot guard: a firmware fallback under a combined update ----------------
# The firmware half of a combined update never booted, the bootloader fell back
# to the proven slot, and the application selector still names the new image.
# Settling here, before the mount, is what keeps the two from being paired for
# a whole boot. The recovery is the library's; the guard only runs it earlier
# than the confirm unit could.

start "a combined fallback settles before the mount"
arm 25 - - 16 12 1 A
run_runtime bootguard
ck "exit" "0" "$rc"
ck "calls" "--commit_update" "$(calls)"
ck "counter untouched by a boot the application did not spend" "" "$(trials)"
done_case

# The cell where two rules would disagree. A revert here would condemn the
# application slot on firmware evidence and leave a state no verb settles.
start "the fallback settles even with the trial budget spent"
arm 25 1 A 16 12 1 A
run_runtime bootguard
ck "exit" "0" "$rc"
ck "calls" "--commit_update" "$(calls)"
# The counter belonged to the update that just ended. Left behind it is
# inherited by the next update to the same slot -- and at one trial left, that
# update's first healthy boot would quarantine its own slot.
ck "counter cleared with the update it belonged to" "" "$(trials)"
done_case

# Scoping, the other way round: the combined state WITHOUT a fallback is the
# ordinary boot into a pending combined update. It must still be counted and
# still be left to the external verdict -- a guard that settled here would
# commit every pending combined update at boot and bypass the confirm door for
# the whole family.
start "a pending combined update without a fallback counts a trial"
arm 25 - - 16 12 0 A
run_runtime bootguard
ck "no commit" "" "$(calls)"
ck "the trial is counted" "2" "$(trials)"
done_case

# A firmware-only fallback belongs to the confirm run: the application
# dimension has nothing pending, so the guard neither settles nor counts.
start "a firmware-only fallback is left to the confirm run"
arm 23 - - 16 12 1 A
run_runtime bootguard
ck "no commit" "" "$(calls)"
ck "no counter" "" "$(trials)"
done_case

# Scoping: only the combined state. An application-only update is not what a
# firmware fallback decides, and the environment can look this way while the
# application half is the only thing pending.
start "an application-only update ignores a fallback order"
arm 24 - - 16 12 1 A
run_runtime bootguard
ck "no commit" "" "$(calls)"
ck "the trial is still counted" "2" "$(trials)"
done_case

# A settle that does not go through must not remove the bounded way out. The
# confirm run reaches the same verb later in this boot and fails the same way,
# so the state stays pending -- and then only the trial countdown still leads
# anywhere. A boot is never failed either way.
start "a failed pre-mount commit falls back to the trial countdown"
arm 25 2 A 14 12 1 A
run_runtime bootguard
ck "exit" "0" "$rc"
ck "calls" "--commit_update" "$(calls)"
ck "the trial is counted after all" "1" "$(trials)"
done_case

# After the guard settled, the confirm run must find nothing to do -- and must
# not read the fallback-shaped environment as a second recovery.
start "the confirm run is a no-op after the guard settled"
arm 27 - - 16 12 1 A
run_confirm confirm
ck "exit" "0" "$rc"
ck "calls" "" "$(calls)"
ck "no reboot" "" "$(reboots)"
done_case

if [ "$fails" -ne 0 ]; then
    echo "update-confirm contract test: $fails case(s) FAILED"
    exit 1
fi
echo "update-confirm contract test: all cases passed"
