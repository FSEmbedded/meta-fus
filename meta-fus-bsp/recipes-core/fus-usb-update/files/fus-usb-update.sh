#!/bin/sh
# Install a firmware bundle from a removable medium. Argument: the mount point.
#
# The medium is untrusted input. Nothing on it is sourced or executed, the
# bundle name is fixed by the image, and the signature expresses intent.
set -u

FS_UPDATER="${FS_UPDATER_BIN:-/usr/sbin/fs-updater}"
RAUC="${RAUC_BIN:-/usr/bin/rauc}"
BUNDLE_NAME="${FUS_USB_BUNDLE_NAME:-update.raucb}"
RECORD_DIR="${FUS_USB_RECORD_DIR:-/data/fus-usb-update}"
STAGE_DIR="${FUS_USB_STAGE_DIR:-/tmp}"
# Beside the record directory, never inside it: the records are keyed by bundle
# hash and pruned by age, and this file is neither.
EVENT_FILE="${FUS_USB_EVENT_FILE:-/data/fus-usb-update.event}"
# The vendor path, not the /etc symlink to it: /etc is a writable overlay whose
# upper outlives every later image, so a copy frozen there would hold the
# version comparison at whatever it said the day it was made.
OS_RELEASE="${FUS_USB_OS_RELEASE:-/usr/lib/os-release}"
HOOK_DIR="${FUS_USB_HOOK_DIR:-/usr/libexec/fus-usb-update.d}"
HOOK_TIMEOUT="${FUS_USB_HOOK_TIMEOUT:-30}"
# A medium left inserted must not grow the records without bound.
RECORD_KEEP="${FUS_USB_RECORD_KEEP:-20}"
# Every bundle this layer builds is verity; a plain one reaching this door was
# built elsewhere.
BUNDLE_FORMAT="${FUS_USB_BUNDLE_FORMAT:-verity}"

# Terminal codes of a successful install: one per bundle type, plus the one the
# door answers when the type is empty, which a plain bundle leaves it.
INSTALL_OK="0 4 8 48"
# The updater answers this while nothing is pending.
STATE_IDLE=27
# The service refuses a concurrent install; that is a retry, not a failure.
STATE_BUSY=66
# The CLI stops watching after its no-progress wait and answers this while the
# install may still be running; the progress verb repeats it.
INSTALL_RUNNING=47
# Durable states that say an update did land and is waiting for a restart or a
# confirmation. Reached after a non-success install code, they outrank it: the
# door started from idle, so the state can only have moved because this install
# moved it. The layer's own state table names them pending/unconfirmed and
# installed-reboot-pending, not "incomplete" as the enum's name suggests.
STATE_LANDED="23 24 25 26"
# Nothing is pending: the install left no trace and a later insertion may try
# again. Anything outside both lists is reported as a failure -- unknown is not
# "try again".
STATE_RETRY="27"

STAGED=""
# Set by preflight() for the caller's log line and record entry.
REFUSAL=""

# Stderr, not logger: the unit's SyslogIdentifier puts this under the tag an
# operator is told to read. A syslog call does not get there on these images
# -- busybox syslogd runs beside journald and takes the /dev/log traffic to
# /var/log/messages instead, leaving `journalctl -t fus-usb-update` empty.
# Neither sink outlives a restart (the journal here is runtime-only); what
# survives the restart that activates an install is the record on /data.
log() { printf '%s\n' "$*" >&2; }

cleanup() { [ -n "$STAGED" ] && rm -f "$STAGED"; }

in_list() { # <value> <space-separated list>
    for _il in $2; do
        [ "$1" = "$_il" ] && return 0
    done
    return 1
}

# The name comes from the image, never from the medium; this guards a
# misconfigured image rather than a hostile one.
name_is_safe() {
    case "$1" in
    */*|..|.|'') return 1 ;;
    *) return 0 ;;
    esac
}

# The bundle's own text is read, never evaluated: a manifest carrying shell
# syntax must not reach an interpreter.
unquote() {
    _uq=$1
    case "$_uq" in
    \'*\') _uq=${_uq#\'}; _uq=${_uq%\'} ;;
    \"*\") _uq=${_uq#\"}; _uq=${_uq%\"} ;;
    esac
    printf '%s\n' "$_uq"
}

shell_field() { # <shell-format text> <field name>
    unquote "$(printf '%s\n' "$1" | sed -n "s/^$2=//p" | sed -n 1p)"
}

file_field() { # <file> <field name>
    unquote "$(sed -n "s/^$2=//p" "$1" 2>/dev/null | sed -n 1p)"
}

# The firmware version is a build date throughout this layer. Anything else is
# not comparable, and an incomparable version is refused rather than guessed.
is_build_id() {
    case "$1" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;;
    *) return 1 ;;
    esac
}

updater_state() {
    "$FS_UPDATER" --update_reboot_state >/dev/null 2>&1
    echo $?
}

install_progress() {
    "$FS_UPDATER" --install_progress >/dev/null 2>&1
    echo $?
}

bundle_id() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

record_path() { echo "$RECORD_DIR/$1"; }

# Outcome, not a bare attempt: a transient failure must not bar a bundle for
# good, so only a completed install blocks a repeat. A record that exists but
# cannot be read is not the same as no record -- reading it as "nothing" would
# reinstall a bundle this door already installed, so it is an error.
record_read() {
    _rr=$(record_path "$1")
    [ -e "$_rr" ] || return 0
    cut -d' ' -f1 2>/dev/null <"$_rr"
}

# The record is what breaks the reinstall loop, so a record that cannot be
# written is a stop condition, not a warning. Written to a temp file and
# renamed into place -- a crash mid-write must not leave a truncated record
# that record_read (and the "no record" path) would misread as absent.
record_write() {
    mkdir -p "$RECORD_DIR" || return 1
    _rp=$(record_path "$1")
    printf '%s %s %s\n' "$2" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${3:-}" \
        >"$_rp.tmp" || return 1
    mv -f "$_rp.tmp" "$_rp" || return 1
    record_prune
    return 0
}

record_prune() {
    ls -1t "$RECORD_DIR" 2>/dev/null | tail -n +$((RECORD_KEEP + 1)) | while read -r _f; do
        rm -f "$RECORD_DIR/$_f"
    done
    return 0
}

# Reading the bundle changes nothing, so a refusal here costs neither the
# durable update state nor a restart. The device's own identity comes from the
# running RAUC rather than from a configuration path: this image keeps no
# /etc/rauc, and a copy in the writable overlay would outvote every later
# image. Returns 0 to install, 2 when the medium carries the running version,
# 1 to refuse with the reason in REFUSAL.
preflight() { # <staged bundle>
    _pf_info=$("$RAUC" info --output-format=shell "$1" 2>/dev/null) || {
        REFUSAL="inspection"
        return 1
    }
    _pf_status=$("$RAUC" status --output-format=shell 2>/dev/null) || {
        REFUSAL="device-identity"
        return 1
    }

    _pf_want=$(shell_field "$_pf_status" RAUC_SYSTEM_COMPATIBLE)
    if [ -z "$_pf_want" ]; then
        REFUSAL="device-identity"
        return 1
    fi
    if [ "$(shell_field "$_pf_info" RAUC_MF_COMPATIBLE)" != "$_pf_want" ]; then
        REFUSAL="compatible"
        return 1
    fi
    if [ "$(shell_field "$_pf_info" RAUC_MF_FORMAT)" != "$BUNDLE_FORMAT" ]; then
        REFUSAL="format"
        return 1
    fi

    _pf_dev=$(file_field "$OS_RELEASE" BUILD_ID)
    if ! is_build_id "$_pf_dev"; then
        REFUSAL="device-version"
        return 1
    fi
    _pf_new=$(shell_field "$_pf_info" RAUC_MF_VERSION)
    if ! is_build_id "$_pf_new"; then
        REFUSAL="bundle-version"
        return 1
    fi
    [ "$_pf_new" != "$_pf_dev" ] || return 2
    if [ "$_pf_new" -lt "$_pf_dev" ]; then
        REFUSAL="downgrade"
        return 1
    fi
    return 0
}

install_bundle() { "$FS_UPDATER" --install_update "$1"; }

# An unwritable event file must not cost an install that already happened.
write_event() { # <word> <bundle id> <detail>
    _we_dir=${EVENT_FILE%/*}
    [ "$_we_dir" = "$EVENT_FILE" ] || mkdir -p "$_we_dir" 2>/dev/null
    {
        printf 'OUTCOME=%s\n' "$1"
        printf 'BUNDLE=%s\n' "$2"
        printf 'DETAIL=%s\n' "$3"
        printf 'TIME=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$EVENT_FILE" 2>/dev/null || log "WARNING: the event file was not written"
}

# There is no timeout(1) on this target -- neither coreutils nor a BusyBox
# applet -- so the deadline is a second child that fells the first.
run_hook() { # <path> <word> <bundle id>
    "$1" "$2" "$3" >/dev/null 2>&1 &
    _rh_pid=$!
    (
        # One-second steps rather than one long sleep: when the hook finishes
        # first this subshell is killed, and only a second of sleeping is
        # orphaned with it instead of the whole deadline.
        _rh_n=0
        while [ "$_rh_n" -lt "$HOOK_TIMEOUT" ]; do
            sleep 1
            _rh_n=$((_rh_n + 1))
        done
        # TERM asks; KILL is why the wait below always ends. A hook that traps
        # TERM would otherwise hold the door open until systemd's own timeout.
        kill -TERM "$_rh_pid" 2>/dev/null
        sleep 2
        kill -KILL "$_rh_pid" 2>/dev/null
    ) &
    _rh_guard=$!
    wait "$_rh_pid" 2>/dev/null
    kill -TERM "$_rh_guard" 2>/dev/null
    wait "$_rh_guard" 2>/dev/null
    return 0
}

# Hooks are advisory and run last: the outcome is decided, recorded and written
# to the event file before the first one starts, and a hook's exit status
# changes none of it. The directory is the image's, never the medium's.
run_hooks() { # <word> <bundle id>
    [ -d "$HOOK_DIR" ] || return 0
    for _rs_h in "$HOOK_DIR"/*; do
        if [ ! -f "$_rs_h" ] || [ ! -x "$_rs_h" ]; then
            continue
        fi
        run_hook "$_rs_h" "$1" "$2"
    done
    return 0
}

# One place where a finished run says what it was. The record is written by the
# caller instead: `skipped` is the one word that must never land there, because
# the records are keyed by bundle hash and a skip would overwrite an accepted
# entry.
signal() { # <word> <bundle id> <detail>
    write_event "$1" "$2" "$3"
    run_hooks "$1" "$2"
}

main() {
    _mount=${1:-}
    if [ -z "$_mount" ]; then
        echo "usage: $0 <mount-point>" >&2
        return 2
    fi
    trap cleanup EXIT
    trap 'cleanup; trap - EXIT; exit 143' INT TERM

    _state=$(updater_state)
    if [ "$_state" -ne "$STATE_IDLE" ]; then
        log "update state $_state is not idle -- skipping"
        signal skipped "" "state=$_state"
        return 0
    fi

    if ! name_is_safe "$BUNDLE_NAME"; then
        log "refusing bundle name '$BUNDLE_NAME'"
        signal refused "" "bundle-name"
        return 1
    fi
    _bundle="$_mount/$BUNDLE_NAME"
    # Tested before -f, which follows the link: a link to a regular file passes
    # -f and would be staged. A link is untrusted input naming a path the medium
    # does not own, so it is a refusal and not an absence.
    if [ -L "$_bundle" ]; then
        log "refusing $BUNDLE_NAME: the medium offers a symlink"
        signal refused "" "symlink"
        return 1
    fi
    if [ ! -f "$_bundle" ]; then
        log "no $BUNDLE_NAME on the medium"
        signal skipped "" "no-bundle"
        return 0
    fi

    # Staged before anything is read from it, so the identity, the inspection
    # and the install all see the same bytes -- a medium that answers each read
    # differently cannot slip between them -- and so it can be withdrawn.
    STAGED=$(mktemp "$STAGE_DIR/fus-usb-update.XXXXXX") || {
        log "cannot stage"
        signal refused "" "stage"
        return 1
    }
    if ! cp -f "$_bundle" "$STAGED"; then
        log "cannot stage the bundle -- not falling back to the medium"
        signal refused "" "stage"
        return 1
    fi

    _id=$(bundle_id "$STAGED")
    if [ -z "$_id" ]; then
        log "cannot hash the bundle"
        signal refused "" "hash"
        return 1
    fi

    _prev=$(record_read "$_id") || {
        log "the record for $_id cannot be read -- not installing"
        signal refused "$_id" "record-unreadable"
        return 1
    }
    case "$_prev" in
    accepted|settled)
        log "bundle $_id was already installed -- not repeating"
        signal skipped "$_id" "already-$_prev"
        return 0
        ;;
    esac

    preflight "$STAGED"
    case $? in
    0) ;;
    2)
        log "bundle $_id carries the running version -- nothing to do"
        signal skipped "$_id" "up-to-date"
        return 0
        ;;
    *)
        log "bundle $_id refused before install: $REFUSAL"
        record_write "$_id" refused "$REFUSAL" || log "WARNING: the refusal was not recorded"
        signal refused "$_id" "$REFUSAL"
        return 1
        ;;
    esac

    record_write "$_id" attempted "" || {
        log "cannot record the attempt -- refusing to install without the loop breaker"
        signal refused "$_id" "record-unwritable"
        return 1
    }

    install_bundle "$STAGED"
    _rc=$?

    if [ "$_rc" -eq "$STATE_BUSY" ]; then
        log "installer busy -- will retry on the next insertion"
        record_write "$_id" deferred "rc=$_rc" || true
        signal deferred "$_id" "busy"
        return 0
    fi

    # The CLI gave up watching, not the install; the progress verb carries the
    # terminal answer, and while it still says running there is no outcome to
    # claim.
    if [ "$_rc" -eq "$INSTALL_RUNNING" ]; then
        _rc=$(install_progress)
        if [ "$_rc" -eq "$INSTALL_RUNNING" ]; then
            log "install still running past the wait -- deferring"
            record_write "$_id" deferred "rc=$_rc" || true
            signal deferred "$_id" "still-running"
            return 0
        fi
    fi

    if in_list "$_rc" "$INSTALL_OK"; then
        record_write "$_id" accepted "rc=$_rc" \
            || log "WARNING: accepted but not recorded -- the next insertion may repeat it"
        log "bundle $_id accepted (rc=$_rc); activation happens on the next restart"
        signal accepted "$_id" "rc=$_rc"
        return 0
    fi

    # An install error alone does not say what happened to the durable state.
    # The state does, and it outranks the code in both directions.
    _post=$(updater_state)
    if in_list "$_post" "$STATE_LANDED"; then
        record_write "$_id" accepted "rc=$_rc state=$_post" \
            || log "WARNING: accepted but not recorded -- the next insertion may repeat it"
        log "bundle $_id answered rc=$_rc but state $_post says it landed; activation happens on the next restart"
        signal accepted "$_id" "rc=$_rc state=$_post"
        return 0
    fi
    if in_list "$_post" "$STATE_RETRY"; then
        log "bundle $_id did not install (rc=$_rc); state $_post allows a retry"
        record_write "$_id" deferred "rc=$_rc state=$_post" || true
        signal deferred "$_id" "rc=$_rc state=$_post"
        return 0
    fi

    log "bundle $_id failed to install (rc=$_rc, state $_post)"
    record_write "$_id" failed "rc=$_rc state=$_post" || true
    signal failed "$_id" "rc=$_rc state=$_post"
    return 1
}

case "${0##*/}" in
fus-usb-update.sh) main "$@" ;;
esac
