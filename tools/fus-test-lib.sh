# shellcheck shell=sh
# fus-test-lib.sh -- shared harness for this directory's test suites.
#
# Sourced, never executed; the shell directive above is the lint marker, as
# in fus-bundle-lib.sh. Provides the check/expect helpers, the SKIP exit,
# the work directory + cleanup trap, and the temporary-PATH stub
# installation every suite used to build for itself. The helpers write to
# the caller's `fail` and print the exact ok/FAIL lines the suites have
# always printed, so converting a suite changes no check count.
#
# The verdict accumulator `fail` belongs to the sourcing suite (it sets
# fail=0 and reads it at the end); the helpers only ever raise it. SPATH and
# TMP are likewise the suite's variables, set here for it.
# shellcheck disable=SC2034
set -u

fus_test_init() { # sets TMP (mktemp -d, removed by trap)
    TMP=$(mktemp -d) || { echo "FAIL: cannot create the test workdir" >&2; exit 1; }
    trap 'rm -rf "$TMP"' EXIT
}

check() { # check <desc> <want> <got>
    if [ "$2" = "$3" ]; then
        echo "ok   $1"
    else
        echo "FAIL $1: want [$2] got [$3]"
        fail=1
    fi
}

rc_is() { # rc_is <desc> <want-rc> <cmd...>
    _desc=$1; _want=$2; shift 2
    "$@" >/dev/null 2>&1
    check "$_desc" "$_want" "$?"
}

has() { # has <desc> <fixed-string> <file>
    if grep -qF -- "$2" "$3"; then
        echo "ok   $1"
    else
        echo "FAIL $1: no [$2] in $3"
        fail=1
    fi
}

lacks() { # lacks <desc> <fixed-string> <file>
    if grep -qF -- "$2" "$3"; then
        echo "FAIL $1: found [$2] in $3"
        fail=1
    else
        echo "ok   $1"
    fi
}

skip() { # skip <reason...>  -- a suite that cannot measure exits green but LOUD
    echo "SKIP: $*"
    exit 0
}

fus_test_install_rauc_stub() { # fus_test_install_rauc_stub <suite-dir>
    # Installs THE canned rauc (fus-rauc-stub.sh, the single source of the
    # answer block) into a temporary PATH and sets SPATH. Suites never carry
    # their own copy of the block; fus-test-lib.test.sh proves there is only
    # this one.
    mkdir -p "$TMP/bin" || { echo "FAIL: cannot create the stub dir" >&2; exit 1; }
    cp "$1/fus-rauc-stub.sh" "$TMP/bin/rauc" && chmod +x "$TMP/bin/rauc" || {
        echo "FAIL: cannot install the rauc stub from $1" >&2; exit 1; }
    SPATH="$TMP/bin:$PATH"
}

fus_test_install_mksquashfs_stub() { # a packing mksquashfs beside the rauc stub
    # ONE stub for every suite, like the rauc stub: a second, differently
    # behaving mksquashfs would let two tests disagree about what "packing"
    # means. The -version branch is all the older suites ever exercise; the
    # pack branch writes a DETERMINISTIC fake squashfs derived from the
    # source tree and SOURCE_DATE_EPOCH only, never from the clock -- the
    # reproducibility case byte-compares two runs. The 'hsqs' prefix keeps
    # the output within the image-door magic contract.
    # Knobs: STUB_MKSQ_LOG appends each invocation's "$*" (the guard tests
    # assert absence); STUB_MKSQ_RC fails the pack verb; STUB_MKSQ_EMPTY
    # exits 0 without writing anything (the no-output guard).
    mkdir -p "$TMP/bin" || { echo "FAIL: cannot create the stub dir" >&2; exit 1; }
    cat > "$TMP/bin/mksquashfs" <<'MKSQ_STUB' || { echo "FAIL: cannot write the mksquashfs stub" >&2; exit 1; }
#!/bin/sh
[ -n "${STUB_MKSQ_LOG:-}" ] && printf '%s\n' "$*" >> "$STUB_MKSQ_LOG"
case "$*" in *-version*) echo "mksquashfs version 0.0-stub"; exit 0 ;; esac
_rc=${STUB_MKSQ_RC:-0}
if [ "$_rc" -ne 0 ]; then echo "stub-mksquashfs: pack failed" >&2; exit "$_rc"; fi
[ -n "${STUB_MKSQ_EMPTY:-}" ] && exit 0
_src=$1; _dest=$2
{
    printf 'hsqs stub pack epoch=%s\n' "${SOURCE_DATE_EPOCH:-unset}"
    (CDPATH='' cd -- "$_src" && find . -type f | LC_ALL=C sort | \
        while IFS= read -r _f; do printf '>>%s\n' "$_f"; cat "$_f"; done)
} > "$_dest"
exit 0
MKSQ_STUB
    chmod +x "$TMP/bin/mksquashfs" || exit 1
}

fus_test_install_verity_stubs() { # veritysetup + openssl beside the other stubs
    # The app door's sidecar step. Both stubs are DERIVED, never constant:
    # the verity tree and the root hash come from the salt/uuid they were
    # given and from the input file's own content, so "two runs over the same
    # source agree" and "a different source disagrees" are both real
    # measurements -- a constant sidecar would leave the counter-probe unable
    # to fail. veritysetup also echoes the parsed --salt/--uuid into its log,
    # so a case can assert the salt really is the packed image's sha256; a
    # wrong derivation would otherwise pass every hermetic assertion.
    # sha256sum is deliberately NOT stubbed: it is the one step the salt
    # contract's whole reproducibility claim rests on.
    # Knobs: STUB_VERITY_LOG / STUB_OPENSSL_LOG append each invocation's "$*";
    # STUB_VERITY_RC / STUB_OPENSSL_RC fail the verb; STUB_VERITY_NO_TREE and
    # STUB_VERITY_NO_ROOTHASH exit 0 while leaving one sidecar unwritten (the
    # "a bundle without its sidecars must be structurally impossible" case);
    # STUB_VERITY_BAD_ROOTHASH writes a root hash of the wrong shape instead
    # of none at all; STUB_OPENSSL_EMPTY does the same for the signature.
    mkdir -p "$TMP/bin" || { echo "FAIL: cannot create the stub dir" >&2; exit 1; }
    cat > "$TMP/bin/veritysetup" <<'VERITY_STUB' || { echo "FAIL: cannot write the veritysetup stub" >&2; exit 1; }
#!/bin/sh
[ -n "${STUB_VERITY_LOG:-}" ] && printf '%s\n' "$*" >> "$STUB_VERITY_LOG"
case "$*" in *--version*) echo "veritysetup 0.0-stub"; exit 0 ;; esac
_salt=''; _uuid=''; _rh=''; _data=''; _hash=''
for _a in "$@"; do
    case "$_a" in
    format)             : ;;
    --salt=*)           _salt=${_a#--salt=} ;;
    --uuid=*)           _uuid=${_a#--uuid=} ;;
    --root-hash-file=*) _rh=${_a#--root-hash-file=} ;;
    -*)                 : ;;
    *)  if [ -z "$_data" ]; then _data=$_a; elif [ -z "$_hash" ]; then _hash=$_a; fi ;;
    esac
done
_rc=${STUB_VERITY_RC:-0}
if [ "$_rc" -ne 0 ]; then echo "stub-veritysetup: format failed" >&2; exit "$_rc"; fi
if [ -z "${STUB_VERITY_NO_TREE:-}" ]; then
    { printf 'stub-verity-tree salt=%s uuid=%s data=' "$_salt" "$_uuid"
      sha256sum < "$_data"; } > "$_hash"
fi
if [ -n "${STUB_VERITY_BAD_ROOTHASH:-}" ]; then
    printf 'not-a-root-hash' > "$_rh"
elif [ -z "${STUB_VERITY_NO_ROOTHASH:-}" ]; then
    _rhv=$(printf '%s|%s' "$_salt" "$_uuid" | sha256sum)
    printf '%s' "${_rhv%% *}" > "$_rh"
fi
exit 0
VERITY_STUB
    cat > "$TMP/bin/openssl" <<'OPENSSL_STUB' || { echo "FAIL: cannot write the openssl stub" >&2; exit 1; }
#!/bin/sh
[ -n "${STUB_OPENSSL_LOG:-}" ] && printf '%s\n' "$*" >> "$STUB_OPENSSL_LOG"
case "${1:-}" in version) echo "OpenSSL 0.0-stub"; exit 0 ;; esac
case "$*" in *--version*) echo "OpenSSL 0.0-stub"; exit 0 ;; esac
_in=''; _out=''; _last=''
for _a in "$@"; do
    case "$_last" in
    -in)  _in=$_a ;;
    -out) _out=$_a ;;
    esac
    _last=$_a
done
_rc=${STUB_OPENSSL_RC:-0}
if [ "$_rc" -ne 0 ]; then echo "stub-openssl: sign failed" >&2; exit "$_rc"; fi
[ -n "${STUB_OPENSSL_EMPTY:-}" ] && exit 0
{ printf 'stub-p7s '; sha256sum < "$_in"; } > "$_out"
exit 0
OPENSSL_STUB
    chmod +x "$TMP/bin/veritysetup" "$TMP/bin/openssl" || exit 1
}
