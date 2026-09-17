#!/bin/sh
# fus-test-lib.test.sh -- proves the canned rauc block has exactly ONE
# source. Every hermetic suite runs twice: untainted they must pass, and
# with STUB_TAINT set (which corrupts the canned version inside
# fus-rauc-stub.sh) EVERY one must fail. If only some fail, a second copy of
# the block still exists somewhere -- then this gate is red no matter how
# green everything else looks. Also pins the skip helper the integration
# suites rely on.
set -u

case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
DIR=$(CDPATH='' cd -- "$_self_dir" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
fus_test_init
fail=0
# Ambient stub knobs would redden the untainted legs and blind the tainted
# ones; this gate controls the stub environment itself.
unset STUB_RAUC_LOG STUB_RAUC_VERSION STUB_RAUC_RC STUB_CONF_COPY \
    STUB_BUNDLE_RC STUB_CONTENT_LIST STUB_CONTENT_COPY STUB_OMIT \
    STUB_COMPAT STUB_VERSION STUB_BUILD STUB_FORMAT STUB_HOOKS \
    STUB_IMAGE_NAME STUB_IMAGES STUB_IMAGE_HOOKS STUB_IMAGE_CLASS \
    STUB_REF_IMAGE_HOOKS \
    STUB_REF_VERSION STUB_REF_BUILD STUB_TAINT \
    STUB_MKSQ_LOG STUB_MKSQ_RC STUB_MKSQ_EMPTY \
    STUB_VERITY_LOG STUB_VERITY_RC STUB_VERITY_NO_TREE STUB_VERITY_NO_ROOTHASH \
    STUB_VERITY_BAD_ROOTHASH \
    STUB_OPENSSL_LOG STUB_OPENSSL_RC STUB_OPENSSL_EMPTY \
    FUS_I_KNOW_OWNERSHIP_IS_WRONG

echo "# --- the skip helper (what the integration suites rely on) ---"
( skip "probe reason" ) > "$TMP/skip.out"
check "skip exits 0" 0 "$?"
check "skip says SKIP, loudly" "SKIP: probe reason" "$(cat "$TMP/skip.out")"

echo "# --- one canned block, every hermetic suite ---"
"$DIR/fus-verify-bundle.test.sh" > "$TMP/v0.out" 2>&1
check "verify suite passes untainted" 0 "$?"
"$DIR/fus-mk-fw-bundle.test.sh" > "$TMP/m0.out" 2>&1
check "fw mk suite passes untainted" 0 "$?"
"$DIR/fus-mk-app-bundle.test.sh" > "$TMP/a0.out" 2>&1
check "app mk suite passes untainted" 0 "$?"
env STUB_TAINT=1 "$DIR/fus-verify-bundle.test.sh" > "$TMP/v1.out" 2>&1
check "a tainted canned block fails the verify suite" 1 "$?"
env STUB_TAINT=1 "$DIR/fus-mk-fw-bundle.test.sh" > "$TMP/m1.out" 2>&1
check "a tainted canned block fails the fw mk suite" 1 "$?"
# The app suite consumes the same block through its mandatory self-
# verification (--expect-version), so a tainted version has to redden it too.
env STUB_TAINT=1 "$DIR/fus-mk-app-bundle.test.sh" > "$TMP/a1.out" 2>&1
check "a tainted canned block fails the app mk suite" 1 "$?"

echo "# --- the stub must not sniff the path for 'reference' ---"
# Measured trap: with a TMPDIR component named reference*, the old stub
# applied the reference overrides to BOTH bundles and the drift case could
# not fail. The suite must stay green under such a TMPDIR.
mkdir -p "$TMP/reference-bench"
env TMPDIR="$TMP/reference-bench" "$DIR/fus-verify-bundle.test.sh" > "$TMP/rb.out" 2>&1
check "verify suite survives a reference-named TMPDIR" 0 "$?"

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
