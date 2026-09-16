#!/bin/sh
# Hermetic tests for the removable-medium update wrapper. No device, no root:
# the wrapper is sourced and its external commands are stubbed, so every
# refusal path can be driven directly. FUS_USB_WRAPPER points the suite at a
# copy of the wrapper -- that is how the mutation runs are driven.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
WRAPPER="${FUS_USB_WRAPPER:-$HERE/../meta-fus-bsp/recipes-core/fus-usb-update/files/fus-usb-update.sh}"
[ -f "$WRAPPER" ] || { echo "FAIL: wrapper not found" >&2; exit 1; }

fails=0
ok()   { printf 'ok   %s\n' "$1"; }
bad()  { printf 'FAIL %s: %s\n' "$1" "$2" >&2; fails=$((fails + 1)); }

# The five words a run may end in. Nothing else may reach the event file.
VOCABULARY=" accepted refused deferred failed skipped "

# One sandbox per case: mount point, record dir, stage dir, stub bin dir.
# The wrapper reads its environment once at source time, so a case that
# changes a setting afterwards assigns the internal name instead.
setup() {
    T=$(mktemp -d)
    MNT="$T/mnt"; REC="$T/rec"; STG="$T/stage"; BIN="$T/bin"; HOOKS="$T/hooks"
    mkdir -p "$MNT" "$REC" "$STG" "$BIN" "$HOOKS"
    : >"$T/install.log"
    # The device is older than the medium by default, so the happy path
    # installs; a case that needs another relation rewrites one of the two.
    printf 'ID=test\nBUILD_ID="20260901"\n' >"$T/os-release"
    UPDATER_RC=27 UPDATER_RC_AFTER='' INSTALL_RC=0 PROGRESS_RC=48 RAUC_RC=0 STATUS_RC=0
    STUB_COMPAT=fus-update-testboard
    STUB_SYSTEM_COMPAT=fus-update-testboard
    STUB_VERSION=20260910
    STUB_FORMAT=verity
    cat >"$BIN/fs-updater" <<'STUB'
#!/bin/sh
case "$1" in
--update_reboot_state)
    # A second value answers only once an install has run, so a case can tell
    # the state before the install from the state after it.
    if [ -n "${UPDATER_RC_AFTER:-}" ] && grep -q '^install ' "$INSTALL_LOG" 2>/dev/null; then
        exit "$UPDATER_RC_AFTER"
    fi
    exit "${UPDATER_RC:-27}" ;;
--install_update)   echo "install $2" >>"$INSTALL_LOG"; exit "${INSTALL_RC:-0}" ;;
--install_progress) echo "progress" >>"$INSTALL_LOG"; exit "${PROGRESS_RC:-48}" ;;
esac
exit 99
STUB
    cat >"$BIN/rauc" <<'STUB'
#!/bin/sh
_verb=$1
_last=$1
for _a in "$@"; do _last=$_a; done
if [ "$_verb" = "status" ]; then
    [ "${STATUS_RC:-0}" -eq 0 ] || exit "${STATUS_RC:-0}"
    echo "RAUC_SYSTEM_COMPATIBLE='${STUB_SYSTEM_COMPAT}'"
    exit 0
fi
echo "info $_last" >>"$INSTALL_LOG"
[ "${RAUC_RC:-0}" -eq 0 ] || exit "${RAUC_RC:-0}"
cat <<INFO
RAUC_MF_COMPATIBLE='${STUB_COMPAT}'
RAUC_MF_VERSION='${STUB_VERSION}'
RAUC_MF_FORMAT='${STUB_FORMAT}'
RAUC_MF_IMAGES='1'
INFO
exit 0
STUB
    chmod +x "$BIN/fs-updater" "$BIN/rauc"
    export INSTALL_LOG="$T/install.log"
    export REC
    FS_UPDATER_BIN="$BIN/fs-updater" RAUC_BIN="$BIN/rauc"
    FUS_USB_RECORD_DIR="$REC" FUS_USB_STAGE_DIR="$STG"
    FUS_USB_EVENT_FILE="$T/event" FUS_USB_OS_RELEASE="$T/os-release"
    FUS_USB_HOOK_DIR="$HOOKS" FUS_USB_HOOK_TIMEOUT=5
    export FS_UPDATER_BIN RAUC_BIN FUS_USB_RECORD_DIR FUS_USB_STAGE_DIR
    export FUS_USB_EVENT_FILE FUS_USB_OS_RELEASE FUS_USB_HOOK_DIR FUS_USB_HOOK_TIMEOUT
    export UPDATER_RC UPDATER_RC_AFTER INSTALL_RC PROGRESS_RC RAUC_RC STATUS_RC
    export STUB_COMPAT STUB_SYSTEM_COMPAT STUB_VERSION STUB_FORMAT
    # shellcheck disable=SC1090  # path is computed above
    . "$WRAPPER"
}
teardown() { rm -rf "$T"; }

bundle() { printf 'payload %s' "${1:-a}" >"$MNT/update.raucb"; }
# The identity the wrapper prints for the one bundle a case stages.
bundle_hash() { sha256sum "$MNT/update.raucb" 2>/dev/null | cut -d' ' -f1; }

installed_count() { grep -c '^install ' "$T/install.log" 2>/dev/null; }
records_exist() { for _r in "$REC"/*; do [ -e "$_r" ] && return 0; done; return 1; }
event_field() { sed -n "s/^$1=//p" "$T/event" 2>/dev/null | sed -n 1p; }
outcome() { event_field OUTCOME; }
# The one record a single-bundle case writes.
record_word() { cat "$REC"/* 2>/dev/null | cut -d' ' -f1 | sed -n 1p; }

# Every case that reaches an outcome runs through here: a word outside the
# vocabulary is a defect wherever it appears.
check_vocabulary() {
    case "$VOCABULARY" in
    *" $(outcome) "*) return 0 ;;
    esac
    bad "vocabulary" "'$(outcome)' is not one of the five words ($1)"
}

# --- a name from the medium must not escape the mount point ----------------
setup
for n in "../../etc/shadow" "/etc/shadow" ".." "." ""; do
    if name_is_safe "$n"; then bad "traversal" "accepted '$n'"; fi
done
name_is_safe "update.raucb" || bad "traversal" "rejected a plain name"
[ "$fails" -eq 0 ] && ok "traversal: separators and dot names refused"
teardown

# --- a non-idle device is left alone ---------------------------------------
setup; bundle; UPDATER_RC=21; export UPDATER_RC
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "non-idle: no install attempted" \
    || bad "non-idle" "installed anyway"
[ "$(outcome)" = "skipped" ] && ok "non-idle: signalled as skipped" \
    || bad "non-idle" "outcome was '$(outcome)'"
records_exist && bad "non-idle" "a skip reached the record"
teardown

# --- an empty medium is not an error ---------------------------------------
setup
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(installed_count)" -eq 0 ] && [ "$(outcome)" = "skipped" ]; then
    ok "no bundle: the run ends successfully and stages nothing"
else
    bad "no bundle" "rc=$rc, $(installed_count) install(s), outcome '$(outcome)'"
fi
records_exist && bad "no bundle" "a medium without a bundle reached the record"
teardown

# --- a symlink is not a bundle ---------------------------------------------
setup; ln -s /etc/shadow "$MNT/update.raucb"
main "$MNT" >/dev/null 2>&1; rc=$?
# The install count alone is green for a skip and for a run that died early --
# the refusal is only proven by the word and the status.
if [ "$rc" -eq 1 ] && [ "$(installed_count)" -eq 0 ] \
    && [ "$(outcome)" = "refused" ] && [ "$(event_field DETAIL)" = "symlink" ]; then
    ok "symlink: refused without following the link"
else
    bad "symlink" "rc=$rc, $(installed_count) install(s), outcome '$(outcome)', detail '$(event_field DETAIL)'"
fi
records_exist && bad "symlink" "a refusal before the hash reached the record"
teardown

# --- a refused bundle costs no durable state -------------------------------
setup; bundle; RAUC_RC=1; export RAUC_RC
main "$MNT" >/dev/null 2>&1
if [ "$(installed_count)" -eq 0 ] && records_exist && grep -q '^refused ' "$REC"/*; then
    ok "preflight: refuses before the install and records why"
else
    bad "preflight" "installed despite a failing inspection, or left no record"
fi
teardown

# --- the happy path installs the local copy, not the medium ----------------
setup; bundle
main "$MNT" >/dev/null 2>&1
_p=$(sed -n 's/^install //p' "$T/install.log" | head -1)
case "$_p" in
"$STG"/*) ok "install: runs against the staged copy" ;;
*)        bad "install" "installed from '$_p' instead of the stage dir" ;;
esac
[ "$(record_word)" = "accepted" ] && ok "record: outcome is accepted" \
    || bad "record" "outcome recorded as '$(record_word)', not accepted"
teardown

# --- the same bundle is not installed twice --------------------------------
setup; bundle
main "$MNT" >/dev/null 2>&1
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 1 ] && ok "repeat: a settled bundle is not reinstalled" \
    || bad "repeat" "installed $(installed_count) times"
[ "$(record_word)" = "accepted" ] && ok "repeat: the skip did not overwrite the record" \
    || bad "repeat" "the record now says '$(record_word)'"
teardown

# --- a busy installer is a retry, not a failure ----------------------------
setup; bundle; INSTALL_RC=66; export INSTALL_RC
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && grep -q '^deferred ' "$REC"/* 2>/dev/null; then
    ok "busy: deferred rather than failed"
else
    bad "busy" "rc=$rc and no deferred record"
fi
teardown

# --- a transient failure must not bar the bundle for good ------------------
setup; bundle; INSTALL_RC=49; export INSTALL_RC
UPDATER_RC_AFTER=27; export UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
INSTALL_RC=0 UPDATER_RC_AFTER=''; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 2 ] && ok "retry: a failed attempt does not block a later one" \
    || bad "retry" "second attempt was blocked"
teardown

# --- the records stay bounded ----------------------------------------------
setup
# shellcheck disable=SC2034  # read by the sourced wrapper
RECORD_KEEP=3
i=0
while [ "$i" -lt 6 ]; do
    bundle "$i"; main "$MNT" >/dev/null 2>&1; i=$((i + 1))
done
n=$(ls -1 "$REC" | wc -l)
[ "$n" -le 3 ] && ok "records: pruned to the keep limit ($n)" \
    || bad "records" "kept $n entries"
teardown

# --- staging failure does not fall back to the medium ----------------------
setup; bundle
# shellcheck disable=SC2034  # read by the sourced wrapper
STAGE_DIR="$T/does-not-exist"
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "stage: no fallback to the medium path" \
    || bad "stage" "installed from the medium after a staging failure"
# A run that cannot stage still ends in a word: every exit but the usage error
# signals one, or a caller watching the event file sees the previous run.
[ "$(outcome)" = "refused" ] && ok "stage: the failure is signalled as refused" \
    || bad "stage" "outcome was '$(outcome)'"
teardown

# --- the inspection sees the staged copy, not the medium -------------------
setup; bundle
main "$MNT" >/dev/null 2>&1
_i=$(sed -n 's/^info //p' "$T/install.log" | head -1)
case "$_i" in
"$STG"/*) ok "order: the inspection runs on the staged copy" ;;
*)        bad "order" "inspected '$_i' rather than the stage dir" ;;
esac
teardown

# --- without the loop breaker there is no install --------------------------
# Permission bits mean nothing to root, so this case would pass hollow there.
if [ "$(id -u)" -eq 0 ]; then
    printf 'skip %s\n' "record: unwritable record (needs a non-root run)"
    printf 'skip %s\n' "record: unreadable record (needs a non-root run)"
else
setup; bundle; chmod 555 "$REC"
main "$MNT" >/dev/null 2>&1; rc=$?
chmod 755 "$REC"
if [ "$(installed_count)" -eq 0 ] && [ "$rc" -ne 0 ]; then
    ok "record: an unwritable record stops the install"
else
    bad "record" "installed with rc=$rc while the record was unwritable"
fi
teardown

# --- an unreadable record is not an absent one -----------------------------
# The record present but unreadable used to read as "no record", which
# reinstalls a bundle this door already installed. Write-only rather than
# unreadable-and-unwritable: with the write bit gone the run would stop at the
# unwritable record instead, and this case would pass without ever exercising
# the read.
setup; bundle
main "$MNT" >/dev/null 2>&1
chmod 200 "$REC"/*
main "$MNT" >/dev/null 2>&1; rc=$?
chmod 644 "$REC"/*
if [ "$(installed_count)" -eq 1 ] && [ "$rc" -ne 0 ] \
    && [ "$(event_field DETAIL)" = "record-unreadable" ]; then
    ok "record: an unreadable record stops the install"
else
    bad "record" "rc=$rc, $(installed_count) install(s), detail '$(event_field DETAIL)'"
fi
teardown
fi

# --- a bundle that cannot be read is not installed -------------------------
setup; bundle; chmod 000 "$MNT/update.raucb"
main "$MNT" >/dev/null 2>&1
chmod 644 "$MNT/update.raucb"
[ "$(installed_count)" -eq 0 ] && ok "unreadable: no install attempted" \
    || bad "unreadable" "installed an unreadable bundle"
teardown

# --- the pre-flight compares identity, format and version ------------------
setup; bundle; STUB_COMPAT=fus-update-otherboard; export STUB_COMPAT
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$(installed_count)" -eq 0 ] && [ "$rc" -ne 0 ] && [ "$(record_word)" = "refused" ]; then
    ok "preflight: a foreign compatible is refused before the install"
else
    bad "preflight" "compatible mismatch installed anyway (rc=$rc)"
fi
teardown

setup; bundle; STUB_FORMAT=plain; export STUB_FORMAT
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "preflight: a plain bundle is refused" \
    || bad "preflight" "installed a bundle of the wrong format"
teardown

setup; bundle; STUB_VERSION=20260930; export STUB_VERSION
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 1 ] && ok "version: a newer bundle installs" \
    || bad "version" "a newer bundle did not install"
teardown

setup; bundle; STUB_VERSION=20260901; export STUB_VERSION
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$(installed_count)" -eq 0 ] && [ "$rc" -eq 0 ] && [ "$(outcome)" = "skipped" ]; then
    ok "version: the running version is skipped, not refused"
else
    bad "version" "equal version gave rc=$rc, outcome '$(outcome)'"
fi
records_exist && bad "version" "the up-to-date skip reached the record"
teardown

setup; bundle; STUB_VERSION=20260801; export STUB_VERSION
main "$MNT" >/dev/null 2>&1
if [ "$(installed_count)" -eq 0 ] && [ "$(record_word)" = "refused" ]; then
    ok "version: an older bundle is refused"
else
    bad "version" "an older bundle was not refused"
fi
teardown

setup; bundle; STUB_VERSION=2.2.9; export STUB_VERSION
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "version: a version that is no build date is refused" \
    || bad "version" "installed a bundle with an incomparable version"
teardown

setup; bundle; rm -f "$T/os-release"
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "version: a missing os-release refuses, fail-closed" \
    || bad "version" "installed without knowing the running version"
teardown

setup; bundle; STATUS_RC=1; export STATUS_RC
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 0 ] && ok "preflight: no device identity refuses, fail-closed" \
    || bad "preflight" "installed without the device identity"
teardown

# --- the CLI's wait ending is not the install ending -----------------------
setup; bundle; INSTALL_RC=47 PROGRESS_RC=48; export INSTALL_RC PROGRESS_RC
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(record_word)" = "accepted" ]; then
    ok "wait: 47 then a finished install is accepted"
else
    bad "wait" "rc=$rc, record '$(record_word)'"
fi
teardown

setup; bundle; INSTALL_RC=47 PROGRESS_RC=49 UPDATER_RC_AFTER=20
export INSTALL_RC PROGRESS_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -ne 0 ] && [ "$(record_word)" = "failed" ]; then
    ok "wait: 47 then a failed install with a spent state is failed"
else
    bad "wait" "rc=$rc, record '$(record_word)'"
fi
teardown

setup; bundle; INSTALL_RC=47 PROGRESS_RC=47; export INSTALL_RC PROGRESS_RC
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(record_word)" = "deferred" ]; then
    ok "wait: a still-running install is deferred, never accepted"
else
    bad "wait" "rc=$rc, record '$(record_word)'"
fi
teardown

# --- the durable state decides between a failure and a retry ---------------
setup; bundle; INSTALL_RC=3 UPDATER_RC_AFTER=21; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
[ "$(record_word)" = "failed" ] && ok "state: 21 after a failed install is a failure" \
    || bad "state" "recorded '$(record_word)' for state 21"
teardown

setup; bundle; INSTALL_RC=3 UPDATER_RC_AFTER=27; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(record_word)" = "deferred" ]; then
    ok "state: an untouched state after a failed install allows a retry"
else
    bad "state" "rc=$rc, recorded '$(record_word)' for state 27"
fi
teardown

setup; bundle; INSTALL_RC=3 UPDATER_RC_AFTER=99; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
[ "$(record_word)" = "failed" ] && ok "state: an unknown state is a failure, not a retry" \
    || bad "state" "recorded '$(record_word)' for an unknown state"
teardown

# The state outranks the code in the other direction too: the door starts from
# idle so a pending state can only have come from this install.
for _s in 23 26; do
    setup; bundle; INSTALL_RC=3 UPDATER_RC_AFTER=$_s; export INSTALL_RC UPDATER_RC_AFTER
    main "$MNT" >/dev/null 2>&1; rc=$?
    if [ "$rc" -eq 0 ] && [ "$(record_word)" = "accepted" ]; then
        ok "state: $_s after a failure says the update landed"
    else
        bad "state" "rc=$rc, recorded '$(record_word)' for state $_s"
    fi
    teardown
done

setup; bundle; INSTALL_RC=3 UPDATER_RC_AFTER=23; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
INSTALL_RC=0 UPDATER_RC_AFTER=''; export INSTALL_RC UPDATER_RC_AFTER
main "$MNT" >/dev/null 2>&1
[ "$(installed_count)" -eq 1 ] && ok "state: a landed update is not installed a second time" \
    || bad "state" "installed $(installed_count) times after a landed state"

# --- every outcome is one of the five words --------------------------------
setup; bundle
main "$MNT" >/dev/null 2>&1; check_vocabulary accepted
UPDATER_RC=21; export UPDATER_RC
main "$MNT" >/dev/null 2>&1; check_vocabulary skipped
UPDATER_RC=27 RAUC_RC=1; export UPDATER_RC RAUC_RC
bundle b; main "$MNT" >/dev/null 2>&1; check_vocabulary refused
RAUC_RC=0 INSTALL_RC=66; export RAUC_RC INSTALL_RC
bundle c; main "$MNT" >/dev/null 2>&1; check_vocabulary deferred
INSTALL_RC=3 UPDATER_RC_AFTER=21; export INSTALL_RC UPDATER_RC_AFTER
bundle d; main "$MNT" >/dev/null 2>&1; check_vocabulary failed
ok "vocabulary: five runs, five words from the list"
teardown

# --- the event file carries the schema, and its loss costs nothing ---------
setup; bundle
main "$MNT" >/dev/null 2>&1
_miss=""
for k in OUTCOME BUNDLE DETAIL TIME; do
    grep -q "^$k=" "$T/event" || _miss="$_miss $k"
done
[ -z "$_miss" ] && ok "event: the schema carries every key" \
    || bad "event" "missing key(s):$_miss"
[ -n "$(event_field BUNDLE)" ] && ok "event: the bundle identity is named" \
    || bad "event" "no bundle identity in the event file"
teardown

setup; bundle
# shellcheck disable=SC2034  # read by the sourced wrapper
EVENT_FILE="$T/nowhere/event"
mkdir -p "$T/nowhere"; chmod 555 "$T/nowhere"
main "$MNT" >/dev/null 2>&1; rc=$?
chmod 755 "$T/nowhere"
if [ "$rc" -eq 0 ] && [ "$(installed_count)" -eq 1 ] && [ "$(record_word)" = "accepted" ]; then
    ok "event: an unwritable event file does not break the install"
else
    bad "event" "rc=$rc, $(installed_count) install(s), record '$(record_word)'"
fi
teardown

# --- hooks are advisory and run last ---------------------------------------
setup; bundle
cat >"$HOOKS/10-log" <<'HOOK'
#!/bin/sh
printf 'hook %s %s record=%s\n' "$1" "$2" \
    "$(cut -d' ' -f1 "$REC/$2" 2>/dev/null)" >>"$INSTALL_LOG"
HOOK
chmod +x "$HOOKS/10-log"
printf '#!/bin/sh\necho "hook-skipped" >>"$INSTALL_LOG"\n' >"$HOOKS/20-not-executable"
chmod 644 "$HOOKS/20-not-executable"
main "$MNT" >/dev/null 2>&1
_h=$(sed -n 's/^hook //p' "$T/install.log" | sed -n 1p)
case "$_h" in
"accepted "*"record=accepted") ok "hook: gets the word and the hash, after the record" ;;
*)                             bad "hook" "hook saw '$_h'" ;;
esac
grep -q '^hook-skipped' "$T/install.log" && bad "hook" "ran a non-executable file"
_order=$(grep -n '^install \|^hook ' "$T/install.log" | sed -n 's/^\([0-9]*\):\([a-z]*\).*/\2/p' | tr '\n' ' ')
case "$_order" in
"install hook "*) ok "hook: runs after the install, not before it" ;;
*)                bad "hook" "order was '$_order'" ;;
esac
teardown

setup; bundle
printf '#!/bin/sh\nexit 1\n' >"$HOOKS/10-fail"; chmod +x "$HOOKS/10-fail"
main "$MNT" >/dev/null 2>&1; rc=$?
if [ "$rc" -eq 0 ] && [ "$(record_word)" = "accepted" ]; then
    ok "hook: a failing hook changes nothing"
else
    bad "hook" "a failing hook changed the outcome (rc=$rc, '$(record_word)')"
fi
teardown

setup; bundle
# The hang outlasts the bound by far, so a loaded host stays well inside the
# bound while a missing deadline still cannot pass. `exec` lets the signal
# reach the sleep itself instead of orphaning it.
printf '#!/bin/sh\nexec sleep 300\n' >"$HOOKS/10-hang"; chmod +x "$HOOKS/10-hang"
# shellcheck disable=SC2034  # read by the sourced wrapper
HOOK_TIMEOUT=1
_t0=$(date +%s)
main "$MNT" >/dev/null 2>&1; rc=$?
_t1=$(date +%s)
if [ "$((_t1 - _t0))" -lt 60 ] && [ "$rc" -eq 0 ] && [ "$(record_word)" = "accepted" ]; then
    ok "hook: a hanging hook is killed and the outcome stands ($((_t1 - _t0))s)"
else
    bad "hook" "waited $((_t1 - _t0))s, rc=$rc, record '$(record_word)'"
fi
teardown

setup; bundle
# The sleep is backgrounded and waited on: a POSIX shell runs a trap only
# once the foreground command returns, so a plain `sleep 30` would swallow
# the signal until long after the deadline had escalated.
cat >"$HOOKS/10-polite" <<'HOOK'
#!/bin/sh
trap 'echo hook-term >>"$INSTALL_LOG"; exit 0' TERM
sleep 30 &
wait
HOOK
chmod +x "$HOOKS/10-polite"
# shellcheck disable=SC2034  # read by the sourced wrapper
HOOK_TIMEOUT=1
main "$MNT" >/dev/null 2>&1
grep -q '^hook-term' "$T/install.log" \
    && ok "hook: the deadline asks with TERM before it enforces" \
    || bad "hook" "the hook was never sent TERM"
teardown

setup; bundle
# An ignored TERM survives the exec, so only KILL ends the sleep.
printf '#!/bin/sh\ntrap "" TERM\nexec sleep 300\n' >"$HOOKS/10-stubborn"; chmod +x "$HOOKS/10-stubborn"
# shellcheck disable=SC2034  # read by the sourced wrapper
HOOK_TIMEOUT=1
_t0=$(date +%s)
main "$MNT" >/dev/null 2>&1; rc=$?
_t1=$(date +%s)
if [ "$((_t1 - _t0))" -lt 60 ] && [ "$rc" -eq 0 ] && [ "$(record_word)" = "accepted" ]; then
    ok "hook: a hook that ignores TERM is killed anyway ($((_t1 - _t0))s)"
else
    bad "hook" "waited $((_t1 - _t0))s, rc=$rc, record '$(record_word)'"
fi
teardown

setup; bundle
mkdir -p "$MNT/fus-usb-update.d"
printf '#!/bin/sh\necho "hook-from-medium" >>"$INSTALL_LOG"\n' >"$MNT/fus-usb-update.d/10-evil"
chmod +x "$MNT/fus-usb-update.d/10-evil"
main "$MNT" >/dev/null 2>&1
grep -q '^hook-from-medium' "$T/install.log" \
    && bad "hook" "ran a hook from the medium" \
    || ok "hook: the directory is the image's, never the medium's"
teardown

# --- the prose goes to stderr, where the unit's identifier picks it up ------
# On the device, logger(1) returns 0 but the line reaches
# only /var/log/messages, a tmpfs the activating restart erases, because
# busybox syslogd takes the /dev/log traffic beside journald. A unit's
# SyslogIdentifier does put stderr into the journal, so that is the route.
setup; bundle
cat >"$BIN/logger" <<'STUB'
#!/bin/sh
echo "logger $*" >>"$INSTALL_LOG"
STUB
chmod +x "$BIN/logger"
# The stub has to be findable, and the search path has to be given back: an
# assignment in front of a function call outlives the call in some shells.
_path_before=$PATH
PATH="$BIN:$PATH"
_err=$(main "$MNT" 2>&1 >/dev/null)
PATH=$_path_before
# Without this the empty hash would make the pattern below match anything.
_hash=$(bundle_hash)
if [ -z "$_hash" ]; then
    bad "log" "no bundle hash to look for; the case would pass on nothing"
else
    case "$_err" in
    *"$_hash"*) ok "log: the outcome line reaches stderr" ;;
    *) bad "log" "no outcome prose on stderr: '$_err'" ;;
    esac
fi
grep -q '^logger ' "$T/install.log" \
    && bad "log" "the wrapper called logger; its output does not reach the journal here" \
    || ok "log: no syslog call, so the unit's identifier carries the line"
teardown

# --- the build-time guard on the unit --------------------------------------
# The recipe's selfcheck is BitBake shell; extracted, given a bbfatal and a
# fabricated ${D}, it runs as plain sh. This checks the assertions themselves.
# Whether the recipe wires them is a build run, not a hermetic case.
SELFCHECK_CLASS="$HERE/../meta-fus-sdk/classes-recipe/fus-selfcheck.bbclass"
UNIT="$HERE/../meta-fus-bsp/recipes-core/fus-usb-update/files/fus-usb-update.service"

selfcheck_accepts() { # <unit text>
    _sc="$T/selfcheck"
    rm -rf "$_sc"; mkdir -p "$_sc/lib/systemd/system"
    printf '%s\n' "$1" >"$_sc/lib/systemd/system/fus-usb-update.service"
    {
        printf 'bbfatal() { echo "$*" >&2; exit 1; }\n'
        sed -n '/^fus_selfcheck_usb_door_unit()/,/^}$/p' "$SELFCHECK_CLASS" \
            | sed -e "s|[\$]{D}|$_sc|g" -e 's|[$]{systemd_system_unitdir}|/lib/systemd/system|g'
        printf 'fus_selfcheck_usb_door_unit\n'
    } >"$T/selfcheck.sh"
    sh "$T/selfcheck.sh" >/dev/null 2>&1
}

setup
if [ ! -f "$SELFCHECK_CLASS" ] || [ ! -f "$UNIT" ]; then
    bad "selfcheck" "class or unit not found beside the suite"
else
    _unit=$(cat "$UNIT")
    selfcheck_accepts "$_unit" && ok "selfcheck: the shipped unit passes" \
        || bad "selfcheck" "the shipped unit fails its own guard"
    selfcheck_accepts "$_unit
PrivateTmp=yes" && bad "selfcheck" "PrivateTmp=yes passed" \
        || ok "selfcheck: a private mount namespace breaks the build"
    selfcheck_accepts "$_unit
RootDirectory=/var/empty" && bad "selfcheck" "RootDirectory passed" \
        || ok "selfcheck: a rerooted unit breaks the build"
    selfcheck_accepts "$(printf '%s\n' "$_unit" | sed 's/^StartLimitIntervalSec=0/StartLimitIntervalSec=10min/')" \
        && bad "selfcheck" "a start rate limit passed" \
        || ok "selfcheck: a start rate limit breaks the build"
fi
teardown

if [ "$fails" -eq 0 ]; then
    echo "fus-usb-update.test: ok"
    # The verdict line the CI loop reads; it has to be the last one.
    echo "ALL PASS"
    exit 0
fi
echo "fus-usb-update.test: $fails failure(s)" >&2
exit 1
