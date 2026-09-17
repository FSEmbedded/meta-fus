#!/bin/sh
# fus-verify-bundle.integration.sh -- fus-verify-bundle.sh against a REAL
# rauc and a real dev-signed bundle. Counterpart to the hermetic suite: a
# stub can model the same wrong world as the code under test, so the
# accept/reject paths are pinned here against the real thing.
#
# Cases: both dev-signed Yocto bundles verify (0); the app bundle resigned
# with the rogue CA is refused (8); a truncated copy is refused (8); the
# floor arithmetic against the bundle's real version (equal 0, above 10).
#
# SKIPs (exit 0) when rauc or an input is absent, so a bare runner stays
# green without pretending to have measured anything. Every input comes only
# from its environment variable, no default path:
#   FUS_IT_BUNDLE       the deployed app bundle (.raucb) to verify
#   FUS_IT_BUNDLE_FW    the deployed firmware bundle (.raucb) to verify
#   FUS_IT_KEYRING      the dev CA certificate (ca.cert.pem) to verify against
#   FUS_IT_ROGUE_CERT   a signing cert NOT in the dev CA chain, for the
#                        rogue-signature rejection case
#   FUS_IT_ROGUE_KEY    the matching private key for FUS_IT_ROGUE_CERT
set -u

# Builtins only, so the rauc-missing SKIP works even under an emptied PATH.
case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
DIR=$(CDPATH='' cd -- "$_self_dir" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
VERIFY="$DIR/fus-verify-bundle.sh"

FUS_IT_BUNDLE="${FUS_IT_BUNDLE:-}"
FUS_IT_BUNDLE_FW="${FUS_IT_BUNDLE_FW:-}"
FUS_IT_KEYRING="${FUS_IT_KEYRING:-}"
FUS_IT_ROGUE_CERT="${FUS_IT_ROGUE_CERT:-}"
FUS_IT_ROGUE_KEY="${FUS_IT_ROGUE_KEY:-}"

if [ -n "${FUS_RAUC:-}" ]; then
    [ -x "$FUS_RAUC" ] || skip "FUS_RAUC does not point at an executable"
    RAUC=$FUS_RAUC
else
    RAUC=$(command -v rauc 2>/dev/null) || skip "rauc not installed (Debian package: rauc)"
fi
[ -f "$FUS_IT_BUNDLE" ]  || skip "bundle not present (FUS_IT_BUNDLE)"
[ -f "$FUS_IT_KEYRING" ] || skip "dev CA not present (FUS_IT_KEYRING)"

fus_test_init
fail=0

echo "# rauc: $RAUC ($("$RAUC" --version 2>/dev/null))"

echo "# --- a valid dev-signed bundle verifies ---"
"$VERIFY" --keyring "$FUS_IT_KEYRING" "$FUS_IT_BUNDLE" > "$TMP/ok.out" 2> "$TMP/ok.err"
check "valid bundle -> 0" 0 "$?"
has "verification stated" "verify=pass" "$TMP/ok.out"
has "verdict stated"      "result=pass" "$TMP/ok.out"
has "app image keyed by its class" "image.appfs.filename=" "$TMP/ok.out"
version=$(sed -n 's/^version=//p' "$TMP/ok.out")
if [ -z "$version" ]; then
    echo "FAIL: no version parsed from the real rauc output -- field names drifted?"
    fail=1
else
    echo "# measured bundle version: $version"
fi

echo "# --- the fw bundle verifies too ---"
# The other real bundle shape: rootfs class, and more than one image when
# boot=slot is active -- the real multi-image parse path. The image count is
# not asserted; it depends on the build's boot mode.
if [ -f "$FUS_IT_BUNDLE_FW" ]; then
    "$VERIFY" --keyring "$FUS_IT_KEYRING" "$FUS_IT_BUNDLE_FW" \
        > "$TMP/fw.out" 2> "$TMP/fw.err"
    check "fw bundle -> 0" 0 "$?"
    has "fw verdict stated" "result=pass" "$TMP/fw.out"
    has "rootfs image keyed by its class" "image.rootfs.filename=" "$TMP/fw.out"
else
    echo "SKIP (case): fw bundle not present (FUS_IT_BUNDLE_FW)"
fi

echo "# --- a rogue-CA resign is refused ---"
if [ -f "$FUS_IT_ROGUE_CERT" ] && [ -f "$FUS_IT_ROGUE_KEY" ]; then
    "$RAUC" resign --no-verify --cert="$FUS_IT_ROGUE_CERT" --key="$FUS_IT_ROGUE_KEY" \
        "$FUS_IT_BUNDLE" "$TMP/rogue.raucb" > "$TMP/resign.log" 2>&1
    if [ "$?" -ne 0 ]; then
        echo "FAIL: cannot produce the rogue-signed bundle (see rauc resign output):"
        cat "$TMP/resign.log"
        fail=1
    else
        rc_is "rogue-signed bundle -> 8" 8 \
            "$VERIFY" --keyring "$FUS_IT_KEYRING" "$TMP/rogue.raucb"
    fi
else
    echo "SKIP (case): rogue CA material not present (FUS_IT_ROGUE_CERT/KEY)"
fi

echo "# --- a truncated bundle is refused ---"
# stat MUST dereference here: the deploy name is a symlink, and its own size
# is the length of the target name, not the bundle.
size=$(stat -Lc %s "$FUS_IT_BUNDLE")
check "resolved size is a bundle, not a link name" yes \
    "$([ "$size" -gt 100000 ] && echo yes || echo no)"
head -c $((size - 2000)) "$FUS_IT_BUNDLE" > "$TMP/trunc.raucb"
check "truncated copy is 2000 bytes short" "$((size - 2000))" \
    "$(stat -c %s "$TMP/trunc.raucb")"
rc_is "truncated bundle -> 8" 8 "$VERIFY" --keyring "$FUS_IT_KEYRING" "$TMP/trunc.raucb"

echo "# --- the floor against the real version ---"
if [ -n "$version" ]; then
    rc_is "floor equal to the real version -> 0" 0 \
        "$VERIFY" --keyring "$FUS_IT_KEYRING" --floor "$version" "$FUS_IT_BUNDLE"
    floor_hi=$(( ${version%%.*} + 1 ))
    rc_is "floor above the real version -> 10" 10 \
        "$VERIFY" --keyring "$FUS_IT_KEYRING" --floor "$floor_hi" "$FUS_IT_BUNDLE"
fi

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
