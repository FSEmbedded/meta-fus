# shellcheck shell=sh
# pending-state.sh -- shared fs-updater pending-state predicate library.
#
# Sourced (never executed) by fus-update-confirm and fus-app-container-runtime;
# installed at /usr/lib/fus-update/pending-state.sh by the mode-invariant
# fus-update-confirm package. fs-updater remains the sole actor for state
# transitions: these helpers only read `--update_reboot_state`'s exit code
# and wrap the two existing CLI actors (--commit_update / --rollback_update)
# with their success-code checks.
#
# That "sole actor" premise is a packaging invariant, not something this
# library enforces itself: fus-update-confirm is only ever pulled onto an
# image via the fsupdater-door-gated RDEPENDS in rauc_%.bbappend, so a
# stock-door image never has fs-updater state to protect in the first place.
# If a packagegroup ever installed fus-update-confirm unconditionally, that
# guarantee would need re-establishing at the packaging layer.
set -u

FS_UPDATER="${FUS_UPDATER_BIN:-/usr/sbin/fs-updater}"

# Overridable for the same reason as FUS_UPDATER_BIN: so the contract test
# can stage it.
FUS_PROC_CMDLINE="${FUS_PROC_CMDLINE:-/proc/cmdline}"

# Tagged by the sourcing script's own name, not hardcoded -- this library is
# shared between fus-update-confirm and fus-app-container-runtime, and a
# fixed tag would mislabel whichever one didn't originally own it.
_log_tag=$(basename "$0")
log() { logger -t "$_log_tag" "$@" 2>/dev/null || true; echo "$_log_tag: $*" >&2; }

# Whether the state can be asked for at all. Without this check an absent or
# unrunnable CLI makes every predicate below answer "no", which reads exactly
# like a device with nothing pending -- the one answer that must not be
# guessed.
updater_reachable() { [ -x "$FS_UPDATER" ]; }

# The state as a value, for callers that branch on it more than once. Each
# predicate below asks the CLI itself, so a caller chaining two of them asks
# twice and can be handed two different answers.
updater_state_rc() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    echo $?
}

# Set membership for an already-read state. Takes the code, issues nothing.
rc_in_set() { # rc_in_set <rc> <set>
    for _c in $2; do
        [ "$1" = "$_c" ] && return 0
    done
    return 1
}

# The settled state. It is the only code that means "nothing is going on":
# every other answer names something, including the ones no verb serves.
# shellcheck disable=SC2034  # read by the sourcing script, not in here
IDLE_CODE=27

# What the CLI answers when it died on an exception instead of reporting a
# state -- an unreadable durable value is how this is reached in practice. It is
# NOT a state: every code below names a condition of the device, this one says
# the device was never successfully asked. A caller that lets it fall through to
# "not pending" acts on an answer it did not get, and for the boot guard that
# means discarding a trial budget on no evidence.
# shellcheck disable=SC2034  # read by the sourcing script, not in here
UPDATER_FATAL_CODE=124

# fs-updater-cli exit codes for --update_reboot_state (fs_updater_error.h,
# UPDATER_UPDATE_REBOOT_STATE, values 20-33). Only these two mean "an app
# update is pending AND the reboot into it already happened" -- the state
# this counter must protect.
APP_PENDING_CODES="24 25"   # INCOMPLETE_APP_UPDATE / INCOMPLETE_APP_FW_UPDATE

# Boot-time variant: also accepts 55, "app update pending, mount state
# unanswerable" (nothing loop-mounted yet).
APP_PENDING_ATBOOT_CODES="24 25 55"

# True if fs-updater reports an app update pending with the reboot into it
# already confirmed (the state this counter protects).
app_update_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $APP_PENDING_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# Boot-time form of app_update_pending for callers ordered strictly before
# the app mount (bootguard). Accepting 55 is safe there: an update recorded
# pending in the U-Boot env means the reboot into it already happened
# (installs run during a prior boot's runtime), and with nothing
# loop-mounted 55 can only be the update-indeterminate case. 57
# (rollback-indeterminate) is deliberately NOT accepted: a pending rollback
# is not trial-protected -- the deadline timer owns it -- and counting it
# would burn trials toward firing a rollback into a state that refuses it.
app_update_pending_atboot() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $APP_PENDING_ATBOOT_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True if fs-updater reports a FW-ONLY update pending (rc 23,
# INCOMPLETE_FW_UPDATE). fw installs reach this image through the same
# fs-updater door (hawkBit backend / manual CLI); the app-dimension
# bootguard/deadline do NOT apply to them (the fw dimension has its own
# U-Boot bootcount + the OS-slot health gate), but the pending state still
# needs a commit actor -- the same "health by application with commit
# update" pattern, applied to the fw dimension.
FW_PENDING_CODE=23
fw_update_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    [ "$?" = "$FW_PENDING_CODE" ]
}

# True iff a firmware dimension is pending-and-unconfirmed: rc 23 (fw-only
# pending) or rc 25 (combined app+fw pending -- the fw half is unconfirmed
# too). Distinct from fw_update_pending: app_update_pending's own set {24,25}
# already claims 25 for the app-dimension view: this predicate exists so
# rauc-mark-good's gate can be computed with one fs-updater call, correctly
# covering both codes that leave the firmware side unconfirmed.
FW_GUARD_PENDING_CODES="23 25"
fw_guard_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $FW_GUARD_PENDING_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True iff a COMBINED app+firmware update is pending (rc 25,
# INCOMPLETE_APP_FW_UPDATE) alone. Exists as its own predicate because
# nothing else distinguishes 23 from 25: the distinction lives only as set
# membership, and app_update_pending's set {24, 25} claims 25 first -- a
# caller that must branch on "both dimensions pending" cannot get that
# answer from the existing predicates.
APP_FW_PENDING_CODE=25
app_fw_update_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    [ "$?" = "$APP_FW_PENDING_CODE" ]
}

# True only for a bootloader fallback past an update that was applied: the
# booted slot is not the one the boot order leads with, it IS the one the
# previous order led with, the two orders differ (so an install really did
# move the order), and a boot budget has been spent to zero.
#
# All four conditions are needed because the caller's next act is to commit,
# and commit re-derives the situation from the same variables. Testing only
# "booted slot is not the first entry" is strictly weaker than what commit
# asks, and the difference is not academic: an update that is installed but
# not yet applied ALSO reads that way, and it is reported as pending-with-
# reboot-taken rather than reboot-pending whenever a boot budget is not
# pristine. Committing there makes the updater treat a freshly installed
# update as a failed one -- discarding it and marking its slot bad with no
# error to whoever installed it. Matching commit's own conditions removes
# that whole class instead of relying on the exit code to exclude it.
#
# Fail closed throughout: an unreadable, absent, empty or unrecognised value
# reports "no fallback". An accidental commit confirms or discards an update
# that never proved itself; an accidental skip only leaves the pending state
# for the next boot to reconsider.
revert_boot_detected() {
    _cmdline=$(cat "$FUS_PROC_CMDLINE" 2>/dev/null) || return 1
    _booted=
    for _tok in $_cmdline; do
        case "$_tok" in
        rauc.slot=*) _booted=${_tok#rauc.slot=} ;;
        esac
    done
    # Normalised, not merely non-empty: an unrecognised slot name would
    # otherwise "differ" from every order entry and read as a fallback.
    case "$_booted" in
    A|a) _booted=A ;;
    B|b) _booted=B ;;
    *)   return 1 ;;
    esac

    _order=$(fw_printenv -n BOOT_ORDER 2>/dev/null) || return 1
    _order_old=$(fw_printenv -n BOOT_ORDER_OLD 2>/dev/null) || return 1
    [ "$_order" != "$_order_old" ] || return 1
    # `read` rather than positional splitting: it takes the leading field
    # without exposing the value to pathname expansion.
    read -r _first _rest <<-EOF
	$_order
	EOF
    read -r _first_old _rest <<-EOF
	$_order_old
	EOF
    [ -n "$_first" ] && [ -n "$_first_old" ] || return 1
    [ "$_booted" != "$_first" ] || return 1
    [ "$_booted" = "$_first_old" ] || return 1

    _left_a=$(fw_printenv -n BOOT_A_LEFT 2>/dev/null) || return 1
    _left_b=$(fw_printenv -n BOOT_B_LEFT 2>/dev/null) || return 1
    case "$_left_a" in ''|*[!0-9]*) return 1 ;; esac
    case "$_left_b" in ''|*[!0-9]*) return 1 ;; esac
    [ "$_left_a" = 0 ] || [ "$_left_b" = 0 ]
}

# True if fs-updater reports a firmware ROLLBACK awaiting its bookkeeping.
# The two codes are NOT interchangeable descriptions of the same situation:
# 28 is the answer while the updater still considers the rollback's reboot
# outstanding, 31 the answer once it asks for the commit. Neither reveals
# whether the reboot has actually been taken -- 31 is reported both before
# and after it. Accepting both is nevertheless right here, because this
# predicate is only ever asked at boot, and any boot enacts a prepared
# rollback: the low-level write forcing the bootloader to the other slot
# happened when the rollback was requested. Nothing is left to decide, only
# to finalize. commit_update -- not rollback_update -- consumes these states
# (it adopts the switched boot order, restores counters, clears the marker);
# no other verb does, so an unrecognised code here would leave the state
# dangling.
#
# Both codes are reachable today. 31 has a second source -- the state a
# not-compiled-in flow would write -- but does not depend on it: the live
# rollback state produces 31 directly once the commit is requested. Dropping it
# because that other state is reserved would break the reachable path. The same
# holds for all three families, this one included.
FW_ROLLBACK_CODES="28 31"
fw_rollback_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $FW_ROLLBACK_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True if fs-updater reports an APPLICATION rollback whose reboot has already
# been taken (rc 29 ROLLBACK_APP_REBOOT_PENDING, or its rc 32
# INCOMPLETE_APP_ROLLBACK sibling). Same finalize contract as the firmware
# case above, on the app dimension -- including the reachability: both codes
# occur, 32 from the live rollback state once the commit is requested.
APP_ROLLBACK_CODES="29 32"
app_rollback_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $APP_ROLLBACK_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True if fs-updater reports a COMBINED firmware+application rollback whose
# reboot has already been taken (rc 30 ROLLBACK_APP_FW_REBOOT_PENDING, or its
# rc 33 INCOMPLETE_APP_FW_ROLLBACK sibling). Same finalize contract, both
# dimensions together.
#
# Reachable like its two siblings: the combined rollback state is written by the
# firmware rollback verb when a combined update is pending, and it reports 30 or
# 33 depending on whether the reboot is still outstanding. The state that shares
# the name of code 33 has no writer -- the apply path that wrote it is not in the
# shipped configuration -- but that costs this predicate nothing, because the
# live state produces both codes on its own. The library-side status of every
# value is enforced by fus_selfcheck_state_flows.
APP_FW_ROLLBACK_CODES="30 33"
app_fw_rollback_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $APP_FW_ROLLBACK_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True if fs-updater reports a FAILED update pending acknowledgement (rc
# 20/21/22). A failed install never switched the running slot, so there is
# nothing to health-probe -- but the state machine blocks every new install
# until this is acknowledged. commit_update() is the acknowledge verb in
# this state (it settles a failed-update marker, not a boot slot).
FAILED_CODES="20 21 22"
update_failed_pending() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    _rc=$?
    for _c in $FAILED_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# True while an update is installed but the reboot into it has not happened
# (rc 26). Not a stored state: the CLI derives it when the stored state says an
# update is installed and is_reboot_complete() answers PENDING, and it does so
# for all three dimensions alike. Seen during a boot it means the bootloader
# did not start the target -- the install is stalled. Read only to report it:
# the answer to a reboot that did not take effect is not another reboot.
REBOOT_OUTSTANDING_CODE=26
update_reboot_outstanding() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    [ "$?" = "$REBOOT_OUTSTANDING_CODE" ]
}

# True while an application UPDATE is pending and nothing is loop-mounted
# (rc 55). Its own set on purpose: the finalize verbs cannot serve it, because
# commit_update refuses without mount evidence, so only the deadline acts on
# it -- and its reboot is bounded, since the boot guard counts an attempt for
# this code and reverts once the budget is spent.
APP_UPDATE_INDETERMINATE_CODE=55
app_update_indeterminate() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    [ "$?" = "$APP_UPDATE_INDETERMINATE_CODE" ]
}

# True while an application ROLLBACK is pending and nothing is loop-mounted
# (rc 57). The confirm settles it with the commit: the revert already switched
# the active slot and no boot changes which image is mounted, so an unmountable
# image leaves nothing to validate, only bookkeeping to finish. Read to decide
# that -- never to drive a reboot, which would reach the same unmountable image
# again, every time.
APP_ROLLBACK_INDETERMINATE_CODE=57
app_rollback_indeterminate() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    [ "$?" = "$APP_ROLLBACK_INDETERMINATE_CODE" ]
}

# fs-updater's --commit_update never exits 0 on success; 16
# (UPDATE_COMMIT_SUCCESSFUL), 17 (UPDATE_NOT_NEEDED) and 59
# (LEGACY_STATE_MIGRATED) mean the commit actually completed. Invokes the verb
# once; not a read-only predicate like the *_pending checks above -- do not call
# more than once per decision (e.g. do not ||-chain it the way cmd_deadline
# chains predicates).
#
# 59 is a device that arrived carrying a durable state no current flow writes:
# the commit settled it, nothing was pending and nothing was discarded, so this
# chain is done with it. Without 59 here the confirm would read a completed
# migration as a failed commit and try again on the next boot, which is what
# made that state a dead end in the first place. 58 is deliberately NOT in this
# set -- there an install was discarded, and a device must not be recorded as
# running firmware it never booted.
COMMIT_OK_CODES="16 17 59"
commit_update_ok() {
    "$FS_UPDATER" --commit_update
    _rc=$?
    for _c in $COMMIT_OK_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# fs-updater's --rollback_update never exits 0 on success; only 12
# (UPDATE_ROLLBACK_SUCCESSFUL) means the revert actually completed. Same
# one-shot caveat as commit_update_ok above.
ROLLBACK_OK_CODES="12"
rollback_update_ok() {
    "$FS_UPDATER" --rollback_update
    _rc=$?
    for _c in $ROLLBACK_OK_CODES; do
        [ "$_rc" = "$_c" ] && return 0
    done
    return 1
}

# Mark the slot the device is running as bad. Only for a caller holding
# evidence that its payload failed -- the app there burned its whole boot
# budget. The library's revert marks an abandoned pending slot bad itself;
# the record written here is the one that survives a revert that fails. The
# switch guard refuses only uncommitted, bad or unprovisioned targets, so
# without any mark a later --switch_app_slot can walk straight back into the
# slot. A new install overwrites the digit unconditionally, so this
# quarantines the payload, not the slot. Fail-open: the caller's revert has
# its own success check, and losing the record must never fail a boot.
SET_STATE_OK_CODE=52
app_mark_running_slot_bad() {
    _slot=$(fw_printenv -n application 2>/dev/null)
    case "$_slot" in
    A|a) _slot=A ;;
    B|b) _slot=B ;;
    *)   log "WARN: unexpected application value '$_slot'; not marking a slot bad"
         return 1 ;;
    esac
    "$FS_UPDATER" --set_app_state_bad "$_slot" >/dev/null 2>&1
    _rc=$?
    if [ "$_rc" != "$SET_STATE_OK_CODE" ]; then
        log "WARN: could not mark app slot $_slot bad (rc $_rc)"
        return 1
    fi
    # The digit is logged because the revert that follows is chosen by it: a
    # mark that kept the in-flight bit sends the revert down the pending path,
    # one that replaced it sends it down the slot-switch path, and both end on
    # the same value. Without this line the two are indistinguishable on a
    # device -- the library's own log says which path it took, but only at a
    # level the journal does not carry.
    log "app slot $_slot marked bad after trial exhaustion; update=$(fw_printenv -n update 2>/dev/null)"
}
