#!/bin/sh
# fus-mk-fw-bundle.integration.sh -- fus-mk-fw-bundle.sh against a REAL rauc
# and the real Yocto payload. This is the acceptance that matters: not "the
# script ran", but that the built bundle diffs clean against the Yocto-built
# firmware bundle (reference=match) -- and the counter-proof that a bundle
# built with a wrong compatible makes the SAME diff fail. Without the
# counter-proof the match only shows that something was compared.
#
# SKIPs (exit 0) when rauc or an input is absent, so a bare runner stays
# green without pretending to have measured anything. Every input comes only
# from its environment variable, no default path:
#   FUS_IT_PAYLOAD      the deployed rootfs squashfs of fusys-image-eval
#   FUS_IT_FW_REFERENCE the Yocto-built firmware bundle (.raucb) to compare
#                        against
#   FUS_IT_CERTS_DEV    directory holding sign.cert.pem, sign.key.pem and
#                        ca.cert.pem (dev signing material)
set -u

# Builtins only, so the rauc-missing SKIP works even under an emptied PATH.
case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
DIR=$(CDPATH='' cd -- "$_self_dir" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
# MK and VERIFY are deliberately NOT set here: they are set below, after the
# tool set has been copied into the work directory (see the copy block).

FUS_IT_PAYLOAD="${FUS_IT_PAYLOAD:-}"
FUS_IT_FW_REFERENCE="${FUS_IT_FW_REFERENCE:-}"
FUS_IT_CERTS_DEV="${FUS_IT_CERTS_DEV:-}"

if [ -n "${FUS_RAUC:-}" ]; then
    [ -x "$FUS_RAUC" ] || skip "FUS_RAUC does not point at an executable"
else
    command -v rauc >/dev/null 2>&1 || skip "rauc not installed (Debian package: rauc)"
fi
command -v mksquashfs >/dev/null 2>&1 || [ -n "${FUS_MKSQUASHFS:-}" ] || \
    skip "mksquashfs not installed (Debian package: squashfs-tools)"
[ -f "$FUS_IT_PAYLOAD" ]      || skip "payload not present (FUS_IT_PAYLOAD)"
[ -f "$FUS_IT_FW_REFERENCE" ] || skip "Yocto fw bundle not present (FUS_IT_FW_REFERENCE)"
[ -f "$FUS_IT_CERTS_DEV/sign.cert.pem" ] && [ -f "$FUS_IT_CERTS_DEV/sign.key.pem" ] && \
    [ -f "$FUS_IT_CERTS_DEV/ca.cert.pem" ] || skip "dev signing material not present (FUS_IT_CERTS_DEV)"
CA="$FUS_IT_CERTS_DEV/ca.cert.pem"


fus_test_init
fail=0

# The claim under test is "a COPIED tool set plus the real tools builds a
# valid bundle", so the run happens from a copy, not from tools/. install-check
# is dereferenced (`cp -L`): a preserved symlink would reach back into the
# layer and prove nothing about a detached copy.
SET="$TMP/toolset"; mkdir -p "$SET"
for _f in "$DIR"/fus-*.sh; do
    cp "$_f" "$SET/" || { echo "FAIL: cannot copy $_f" >&2; exit 1; }
done
cp -L "$DIR/install-check" "$SET/install-check" || {
    echo "FAIL: cannot copy install-check" >&2; exit 1; }
chmod +x "$SET"/fus-*.sh
MK="$SET/fus-mk-fw-bundle.sh"
VERIFY="$SET/fus-verify-bundle.sh"

# The version under test is READ from the reference bundle, not pinned. A
# constant here passed only on the day the deploy tree happened to carry it and
# went red after every rebuild since: the suite encoded a moment instead of an
# invariant, and because nothing ever ran it, nobody saw it. Read through the
# project's own verifier rather than rauc directly -- it already carries the
# keyring and the signing-purpose the host call needs.
"$VERIFY" --keyring "$CA" --identity-out "$TMP/ref.identity" "$FUS_IT_FW_REFERENCE" \
    > "$TMP/ref.identity.out" 2>&1 || {
    echo "FAIL: cannot read the identity of FUS_IT_FW_REFERENCE" >&2
    tail -3 "$TMP/ref.identity.out" >&2
    echo "---"; echo "FAILURES"; exit 1
}
IT_VERSION=$(sed -n 's/^version=//p' "$TMP/ref.identity")
[ -n "$IT_VERSION" ] || { echo "FAIL: reference identity carries no version" >&2
    echo "---"; echo "FAILURES"; exit 1; }
echo "# reference version under test: $IT_VERSION"

OUT="$TMP/out"; mkdir -p "$OUT"

echo "# --- build from the real payload ---"
# No --payload-name: the default is the source basename, and the reference
# diff against the Yocto bundle is what proves that default right.
"$MK" --version "$IT_VERSION" --out "$OUT" \
    --rootfs-image "$FUS_IT_PAYLOAD" \
    --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" \
    --build-stamp 20260901130000 > "$TMP/mk.out" 2> "$TMP/mk.err"
_rc=$?
check "build -> 0" 0 "$_rc"
if [ "$_rc" -ne 0 ]; then
    echo "# build diagnostics:"; cat "$TMP/mk.err"
    echo "---"; echo "FAILURES"; exit 1
fi
ARTIFACT=$(sed -n 's/^artifact=//p' "$TMP/mk.out")
check "artifact named on stdout" yes "$([ -n "$ARTIFACT" ] && [ -f "$ARTIFACT" ] && echo yes)"
has "info exists beside the artifact" "tool.rauc.version=" "$ARTIFACT.info"
has "info records the chain subject" "signature.subject=" "$ARTIFACT.info"
lacks "info holds no signing-material path" "$FUS_IT_CERTS_DEV" "$ARTIFACT.info"

echo "# --- the acceptance: reference=match against the Yocto bundle ---"
"$VERIFY" --keyring "$CA" --reference "$FUS_IT_FW_REFERENCE" "$ARTIFACT" \
    > "$TMP/ref.out" 2> "$TMP/ref.err"
check "reference diff against the Yocto fw bundle -> 0" 0 "$?"
has "reference=match" "reference=match" "$TMP/ref.out"
if ! grep -qF "reference=match" "$TMP/ref.out"; then
    echo "# the differing fields (this difference is the finding, do not tune it away):"
    cat "$TMP/ref.err"
fi

echo "# --- the counter-proof: a wrong compatible must fail the same diff ---"
"$MK" --version "$IT_VERSION" --out "$OUT" \
    --rootfs-image "$FUS_IT_PAYLOAD" \
    --compatible fus-update-wrongboard \
    --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" \
    --build-stamp 20260901130001 > "$TMP/mk2.out" 2> "$TMP/mk2.err"
check "wrong-compat build -> 0 (the bundle itself is valid)" 0 "$?"
ARTIFACT2=$(sed -n 's/^artifact=//p' "$TMP/mk2.out")
"$VERIFY" --keyring "$CA" --reference "$FUS_IT_FW_REFERENCE" "$ARTIFACT2" \
    > "$TMP/ctr.out" 2> "$TMP/ctr.err"
check "wrong-compat vs Yocto reference -> 8" 8 "$?"
has "the diff names the compatible" "compatible" "$TMP/ctr.err"
lacks "no reference=match for the counter-proof" "reference=match" "$TMP/ctr.out"

echo "# --- the directory door: unsquashfs/repack drift ---"
# Unpack the real Yocto payload, repack it through the directory door with
# the SAME SOURCE_DATE_EPOCH, and diff the result's manifest against the
# image door's. Repacking with host squashfs-tools does not reproduce the
# build's bytes (the packer differs), so a digest mismatch here is a
# FINDING, not a defect of this test -- `reference=match` is not an
# acceptance criterion for this door, and the verdict is recorded, not
# tuned to pass.
repack_skip=''
[ "$(id -u)" -eq 0 ] || repack_skip="needs root -- non-root unsquashfs cannot restore uid/gid, and the directory door refuses uid $(id -u) (11); see the fakeroot leg below for a non-root alternative"
if [ -z "$repack_skip" ] && ! command -v unsquashfs >/dev/null 2>&1; then
    repack_skip="unsquashfs not installed (Debian package: squashfs-tools)"
fi
if [ -z "$repack_skip" ]; then
    UNPACKED="$TMP/unpacked"
    unsquashfs -d "$UNPACKED" "$FUS_IT_PAYLOAD" > "$TMP/unsq.out" 2>&1
    _unsq_rc=$?
    check "unsquashfs of the Yocto payload -> 0" 0 "$_unsq_rc"
    # A partial unpack must STOP the leg: the epoch is read from the payload,
    # not from the tree, so everything below would still run and print a
    # drift number measured against an incomplete source -- into the very
    # comment block this file keeps as the durable record.
    [ "$_unsq_rc" -eq 0 ] || \
        repack_skip="the unpack failed (exit $_unsq_rc); a partial tree cannot be measured"
fi
if [ -z "$repack_skip" ]; then
    # The epoch comes from the source superblock, not from the payload file's
    # mtime: mksquashfs stamps SOURCE_DATE_EPOCH there, and that is the value
    # Yocto packed with. Taking the file mtime instead would inject a
    # difference of this test's own making, so a failed read is a SKIP and
    # never a fallback. LC_ALL=C on both: this host's locale is German and
    # `date -d` cannot parse a localised month name.
    LC_ALL=C unsquashfs -stat "$FUS_IT_PAYLOAD" > "$TMP/stat.out" 2>/dev/null
    SDE=$(sed -n 's/^Creation or last append time //p' "$TMP/stat.out")
    SDE=$(LC_ALL=C date -d "$SDE" +%s 2>/dev/null) || SDE=''
    [ -n "$SDE" ] || repack_skip="the payload superblock names no readable creation epoch"
fi
if [ -n "$repack_skip" ]; then
    echo "SKIP (case): repack drift: $repack_skip"
else
    "$MK" --version "$IT_VERSION" --out "$OUT" \
        --rootfs-dir "$UNPACKED" \
        --payload-name "${FUS_IT_PAYLOAD##*/}" \
        --source-date-epoch "$SDE" \
        --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" \
        --build-stamp 20260901130002 > "$TMP/mk3.out" 2> "$TMP/mk3.err"
    _rc3=$?
    check "directory-door build -> 0" 0 "$_rc3"
    if [ "$_rc3" -eq 0 ]; then
        ARTIFACT3=$(sed -n 's/^artifact=//p' "$TMP/mk3.out")
        has "info records the packing uid" "ownership.build_uid=0" "$ARTIFACT3.info"
        has "info records the guard held" "ownership.guard_bypassed=no" "$ARTIFACT3.info"
        "$VERIFY" --keyring "$CA" --reference "$FUS_IT_FW_REFERENCE" "$ARTIFACT3" \
            > "$TMP/rep.out" 2> "$TMP/rep.err"
        _repack_rc=$?
        echo "# repack drift verdict (record it, do not tune it): exit $_repack_rc"
        if [ "$_repack_rc" -eq 0 ]; then
            echo "# repack.drift=none -- the repacked squashfs digest equals Yocto's"
        else
            echo "# repack.drift=present -- the differing fields:"
            cat "$TMP/rep.err"
        fi
    else
        echo "# directory-door build diagnostics:"; cat "$TMP/mk3.err"
    fi
fi

echo "# --- the directory door: the same repack, under fakeroot, real tools ---"
# A SECOND, independent way to close the ownership half of the leg above,
# for hosts (like this one) that have no real root and no working multi-uid
# user namespace: `fakeroot` -- already installed here, no sudo, no
# container. It answers a NARROWER question than the leg above: whether the
# directory door preserves ownership correctly when it is given a chance to
# see it (real or session-faked), NOT which mksquashfs binary produced the
# bytes (that stays the open question the leg above already names).
#
# The one way this goes wrong: fakeroot's
# faking is scoped to ONE process tree. Unpacking OUTSIDE fakeroot and only
# packing INSIDE it makes every file look like uid 0 to the packer -- not
# just the ones that really are root's, all of them (measured: a synthetic
# tree with a 1234:5678 entry came back as root:root, and the packed
# `Number of ids` dropped from 3 to 1) -- the same collapse the real-root leg
# above exists to catch, reproduced with a different tool. So unsquashfs and
# the build below run in ONE fakeroot session, never two.
#
# A second measured quirk: `chown` under this fakeroot answers EINVAL and a
# non-zero unsquashfs exit even though the fake ownership DOES take -- so the
# unsquashfs exit code here is diagnostic only, never the pass/fail signal.
fr_skip=''
command -v fakeroot >/dev/null 2>&1 || fr_skip="fakeroot not installed (Debian package: fakeroot)"
if [ -z "$fr_skip" ] && [ -z "${SDE:-}" ]; then
    # Independent of the leg above: that one only computes SDE once it is
    # past its own root check, which this host never reaches (uid 1000).
    # This leg needs the epoch on its own.
    LC_ALL=C unsquashfs -stat "$FUS_IT_PAYLOAD" > "$TMP/fr-stat.out" 2>/dev/null
    FR_SDE_RAW=$(sed -n 's/^Creation or last append time //p' "$TMP/fr-stat.out")
    SDE=$(LC_ALL=C date -d "$FR_SDE_RAW" +%s 2>/dev/null) || SDE=''
    [ -n "$SDE" ] || fr_skip="the payload superblock names no readable creation epoch"
fi
if [ -n "$fr_skip" ]; then
    echo "SKIP (case): fakeroot repack: $fr_skip"
else
    FR_UNPACKED="$TMP/fr-unpacked"; FR_OUT="$TMP/fr-out"; mkdir -p "$FR_OUT"
    fakeroot sh -c "
        unsquashfs -d '$FR_UNPACKED' '$FUS_IT_PAYLOAD' >'$TMP/fr-unsq.out' 2>&1
        '$MK' --version '$IT_VERSION' --out '$FR_OUT' \
            --rootfs-dir '$FR_UNPACKED' \
            --payload-name '${FUS_IT_PAYLOAD##*/}' \
            --source-date-epoch '$SDE' \
            --certs '$FUS_IT_CERTS_DEV' --keyring '$CA' \
            --build-stamp 20260901130003
    " > "$TMP/fr-mk.out" 2> "$TMP/fr-mk.err"
    _frrc=$?
    check "fakeroot directory-door build -> 0" 0 "$_frrc"
    if [ "$_frrc" -eq 0 ]; then
        FR_ARTIFACT=$(sed -n 's/^artifact=//p' "$TMP/fr-mk.out")
        has "fakeroot info records the packing uid" "ownership.build_uid=0" "$FR_ARTIFACT.info"
        has "fakeroot info records the guard held" "ownership.guard_bypassed=no" "$FR_ARTIFACT.info"
        # The actual probe (see the plan this leg came from): a check that
        # cannot fail is not a check. "root:root matches the original" is
        # true under fakeroot whether the session was sequenced correctly or
        # not -- the id COUNT is not, and is the same ground truth the leg
        # above already trusts.
        FR_BUNDLE_TREE="$TMP/fr-bundle-extract"
        unsquashfs -f -d "$FR_BUNDLE_TREE" "$FR_ARTIFACT" > "$TMP/fr-extract.out" 2>&1
        FR_PAYLOAD="$FR_BUNDLE_TREE/${FUS_IT_PAYLOAD##*/}"
        FR_IDS=$(unsquashfs -stat "$FR_PAYLOAD" 2>/dev/null | sed -n 's/^Number of ids //p')
        check "fakeroot repack keeps all three ownership ids, not one" 3 "${FR_IDS:-0}"
        "$VERIFY" --keyring "$CA" --reference "$FUS_IT_FW_REFERENCE" "$FR_ARTIFACT" \
            > "$TMP/fr-rep.out" 2> "$TMP/fr-rep.err"
        _fr_repack_rc=$?
        echo "# fakeroot repack drift verdict (record it, do not tune it): exit $_fr_repack_rc"
        if [ "$_fr_repack_rc" -eq 0 ]; then
            echo "# repack.drift=none -- the repacked squashfs digest equals Yocto's"
        else
            echo "# repack.drift=present -- the differing fields:"
            cat "$TMP/fr-rep.err"
        fi
    else
        echo "# fakeroot directory-door build diagnostics:"; cat "$TMP/fr-mk.err"
    fi
fi

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
