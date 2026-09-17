#!/bin/sh
# fus-mk-app-bundle.integration.sh -- fus-mk-app-bundle.sh against REAL rauc,
# mksquashfs, veritysetup and openssl, and against the real Yocto app bundle.
#
# The acceptance here is deliberately split in two, because a single
# reference=match is NOT reachable and saying so is the point:
#
#   1. The SIDECARS are drift-free and are proven byte-identical to the ones
#      Yocto deployed -- same input image, same derived salt/uuid, host
#      veritysetup and openssl. That is the whole of section 2.1 measured
#      against the real artifact, with nothing stubbed.
#   2. The PAYLOAD is not: the host's squashfs-tools produces a different
#      byte stream than Yocto's uninative-linked squashfs-tools-native, so
#      the image digest in the manifest differs and the reference diff
#      against the Yocto bundle cannot pass. What IS asserted is the
#      narrower and more useful claim: every other identity field --
#      compatible, version, format, the bundle hook verb, the image
#      filename, the image hook -- matches the Yocto bundle exactly. That is
#      the manifest wiring of this round, measured against the real thing.
#   3. reference=match is then proven for real, between two bundles this
#      tool built from the same tree: end-to-end reproducibility with the
#      real tools, which is the claim the hermetic suite can only make about
#      a stub.
#
# Repacking the deployed image with host squashfs-tools does not reproduce
# the build's bytes (the packer differs); the sidecars do. The comparison
# below is therefore strict on the sidecars and reports the image digest as
# a finding rather than asserting it must match.
#
# SKIPs (exit 0) when a tool or an input is absent, so a bare runner stays
# green without pretending to have measured anything. Every input comes only
# from its environment variable, no default path:
#   FUS_IT_APP_TREE       the unpacked app rootfs tree fus-mk-app-bundle.sh
#                          is meant to pack (the fus-app-container recipe's
#                          installed rootfs)
#   FUS_IT_APP_IMAGE      the deployed app squashfs image, with its
#                          .verity/.roothash/.roothash.p7s sidecars beside it
#   FUS_IT_APP_REFERENCE  the Yocto-built app bundle (.raucb) to compare
#                          against
#   FUS_IT_CERTS_DEV      directory holding sign.cert.pem, sign.key.pem and
#                          ca.cert.pem (dev signing material)
set -u

# Builtins only, so the tool-missing SKIP works even under an emptied PATH.
case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
DIR=$(CDPATH='' cd -- "$_self_dir" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"

FUS_IT_APP_TREE="${FUS_IT_APP_TREE:-}"
FUS_IT_APP_IMAGE="${FUS_IT_APP_IMAGE:-}"
FUS_IT_APP_REFERENCE="${FUS_IT_APP_REFERENCE:-}"
FUS_IT_CERTS_DEV="${FUS_IT_CERTS_DEV:-}"

if [ -n "${FUS_RAUC:-}" ]; then
    [ -x "$FUS_RAUC" ] || skip "FUS_RAUC does not point at an executable"
else
    command -v rauc >/dev/null 2>&1 || skip "rauc not installed (Debian package: rauc)"
fi
command -v mksquashfs >/dev/null 2>&1 || [ -n "${FUS_MKSQUASHFS:-}" ] || \
    skip "mksquashfs not installed (Debian package: squashfs-tools)"
command -v veritysetup >/dev/null 2>&1 || [ -n "${FUS_VERITYSETUP:-}" ] || \
    skip "veritysetup not installed (Debian package: cryptsetup-bin)"
command -v openssl >/dev/null 2>&1 || [ -n "${FUS_OPENSSL:-}" ] || \
    skip "openssl not installed (Debian package: openssl)"
[ -d "$FUS_IT_APP_TREE" ]      || skip "app tree not present (FUS_IT_APP_TREE)"
[ -f "$FUS_IT_APP_REFERENCE" ] || skip "Yocto app bundle not present (FUS_IT_APP_REFERENCE)"
[ -f "$FUS_IT_CERTS_DEV/sign.cert.pem" ] && [ -f "$FUS_IT_CERTS_DEV/sign.key.pem" ] && \
    [ -f "$FUS_IT_CERTS_DEV/ca.cert.pem" ] || skip "dev signing material not present (FUS_IT_CERTS_DEV)"
CA="$FUS_IT_CERTS_DEV/ca.cert.pem"

SIGN_CERT="$FUS_IT_CERTS_DEV/sign.cert.pem"
SIGN_KEY="$FUS_IT_CERTS_DEV/sign.key.pem"

fus_test_init
fail=0

# The claim under test is "a COPIED tool set plus the real tools builds a
# valid bundle", so the run happens from a copy, not from tools/.
# install-check is dereferenced (`cp -L`): a preserved symlink would reach
# back into the layer and prove nothing about a detached copy.
SET="$TMP/toolset"; mkdir -p "$SET"
for _f in "$DIR"/fus-*.sh; do
    cp "$_f" "$SET/" || { echo "FAIL: cannot copy $_f" >&2; exit 1; }
done
cp -L "$DIR/install-check" "$SET/install-check" || {
    echo "FAIL: cannot copy install-check" >&2; exit 1; }
chmod +x "$SET"/fus-*.sh
MK="$SET/fus-mk-app-bundle.sh"
VERIFY="$SET/fus-verify-bundle.sh"

# The version under test is READ from the reference bundle, not pinned. A
# constant here passed only on the day the deploy tree happened to carry it and
# went red after every rebuild since: the suite encoded a moment instead of an
# invariant, and because nothing ever ran it, nobody saw it. Read through the
# project's own verifier rather than rauc directly -- it already carries the
# keyring and the signing-purpose the host call needs.
"$VERIFY" --keyring "$CA" --identity-out "$TMP/ref.identity" "$FUS_IT_APP_REFERENCE" \
    > "$TMP/ref.identity.out" 2>&1 || {
    echo "FAIL: cannot read the identity of FUS_IT_APP_REFERENCE" >&2
    tail -3 "$TMP/ref.identity.out" >&2
    echo "---"; echo "FAILURES"; exit 1
}
IT_VERSION=$(sed -n 's/^version=//p' "$TMP/ref.identity")
[ -n "$IT_VERSION" ] || { echo "FAIL: reference identity carries no version" >&2
    echo "---"; echo "FAILURES"; exit 1; }
echo "# reference version under test: $IT_VERSION"

OUT="$TMP/out"; mkdir -p "$OUT"

echo "# --- the sidecars, against the real deployed set (no packer involved) ---"
# The drift-free half of the round: the verity tree, the root hash and the
# detached signature depend only on the input bytes and the derived salt, so
# they must come out byte-identical to the ones Yocto deployed. If they do
# not, the derivation in fus_verity_sidecars is wrong and no hermetic
# assertion can tell -- so this leg is the ground truth for section 2.1.
if [ -f "$FUS_IT_APP_IMAGE" ] && [ -f "$FUS_IT_APP_IMAGE.verity" ] && \
   [ -f "$FUS_IT_APP_IMAGE.roothash" ] && [ -f "$FUS_IT_APP_IMAGE.roothash.p7s" ]; then
    SC="$TMP/sidecar"; mkdir -p "$SC"
    # -L: deploy publishes the canonical name as a symlink to the versioned
    # artifact, and the sidecars hang off the canonical name.
    cp -L "$FUS_IT_APP_IMAGE" "$SC/img.squashfs"
    IT_VS="${FUS_VERITYSETUP:-$(command -v veritysetup)}"
    IT_SSL="${FUS_OPENSSL:-$(command -v openssl)}"
    IT_SHA="${FUS_SHA256SUM:-$(command -v sha256sum)}"
    (
        # shellcheck disable=SC1091
        . "$SET/fus-bundle-lib.sh" || exit 1
        fus_verity_sidecars "$SC/img.squashfs" "$SIGN_CERT" "$SIGN_KEY" \
            "$IT_VS" "$IT_SSL" "$IT_SHA" "$TMP/sidecar.log"
    ) > "$TMP/sc.out" 2> "$TMP/sc.err"
    check "sidecar derivation over the deployed image -> 0" 0 "$?"
    for _s in verity roothash roothash.p7s; do
        cmp -s "$SC/img.squashfs.$_s" "$FUS_IT_APP_IMAGE.$_s"
        check "derived .$_s equals the deployed .$_s" 0 "$?"
    done
    echo "# sidecar.drift verdict (record it, do not tune it):"
    for _s in verity roothash roothash.p7s; do
        if cmp -s "$SC/img.squashfs.$_s" "$FUS_IT_APP_IMAGE.$_s"; then
            echo "#   .$_s = identical"
        else
            echo "#   .$_s = DIFFERS -- this is the finding, not a test defect"
        fi
    done
else
    echo "SKIP (case): deployed app image or its sidecars not present (FUS_IT_APP_IMAGE)"
fi

echo "# --- build from the real app tree ---"
# The epoch comes from the DEPLOYED image's superblock, not from the tree's
# mtime: mksquashfs stamps SOURCE_DATE_EPOCH there, and that is the value
# Yocto packed with. Taking the mtime instead would inject a difference of
# this test's own making into the drift verdict below -- the packer question
# would then be unanswerable, and the number in this file's header wrong.
# LC_ALL=C on both: this host's locale is German and `date -d` cannot parse a
# localised month name. Without a readable epoch the builds still run (the
# tool defaults to the tree mtime) and the drift verdict says so.
IT_SDE=''
if command -v unsquashfs >/dev/null 2>&1 && [ -f "$FUS_IT_APP_IMAGE" ]; then
    LC_ALL=C unsquashfs -stat "$FUS_IT_APP_IMAGE" > "$TMP/stat.out" 2>/dev/null
    IT_SDE=$(sed -n 's/^Creation or last append time //p' "$TMP/stat.out")
    IT_SDE=$(LC_ALL=C date -d "$IT_SDE" +%s 2>/dev/null) || IT_SDE=''
fi
if [ -n "$IT_SDE" ]; then
    echo "# packing with the deployed image's own epoch: $IT_SDE"
    # The positional parameters carry this epoch into EVERY build below, not
    # just the next one -- the drift verdict and the two later builds are only
    # comparable while all three pack with the same value. Nothing between
    # here and the last build may reuse or clear "$@".
    set -- --source-date-epoch "$IT_SDE"
else
    echo "# NOTE: no readable epoch in the deployed image; the drift verdict below"
    echo "#       also carries a timestamp difference and is NOT a packer verdict"
    set --
fi
"$MK" --version "$IT_VERSION" --out "$OUT" \
    --app-dir "$FUS_IT_APP_TREE" \
    --app-binaries fus-demo-app --app-id fus-demo-app \
    --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" "$@" \
    --build-stamp 20260901140000 > "$TMP/mk.out" 2> "$TMP/mk.err"
_rc=$?
check "build -> 0" 0 "$_rc"
if [ "$_rc" -ne 0 ]; then
    echo "# build diagnostics:"; cat "$TMP/mk.err"
    echo "---"; echo "FAILURES"; exit 1
fi
ARTIFACT=$(sed -n 's/^artifact=//p' "$TMP/mk.out")
check "artifact named on stdout" yes "$([ -n "$ARTIFACT" ] && [ -f "$ARTIFACT" ] && echo yes)"
has "info exists beside the artifact" "tool.rauc.version=" "$ARTIFACT.info"
has "info records the veritysetup version" "tool.veritysetup.version=" "$ARTIFACT.info"
has "info records the payload digest" "payload.sha256=" "$ARTIFACT.info"
has "info records the verity root hash" "verity.roothash=" "$ARTIFACT.info"
lacks "info holds no signing-material path" "$FUS_IT_CERTS_DEV" "$ARTIFACT.info"

echo "# --- the built bundle really carries six members ---"
# A verity-format bundle is a squashfs; unsquashfs is how the fw leg reads
# one too. The sidecar names inside are the device contract.
if command -v unsquashfs >/dev/null 2>&1; then
    BT="$TMP/bundle-tree"
    unsquashfs -f -d "$BT" "$ARTIFACT" > "$TMP/extract.out" 2>&1
    check "unsquashfs of the built bundle -> 0" 0 "$?"
    for _m in fus-app-container.squashfs fus-app-container.squashfs.verity \
              fus-app-container.squashfs.roothash \
              fus-app-container.squashfs.roothash.p7s install-check manifest.raucm; do
        check "bundle member $_m" yes "$([ -f "$BT/$_m" ] && echo yes)"
    done
    has "the bundle manifest carries the bundle hook verb" "hooks=install-check" \
        "$BT/manifest.raucm"
    has "the bundle manifest carries the appfs image" "[image.appfs]" "$BT/manifest.raucm"
    # rauc writes sha256/size INTO the bundled manifest; the input manifest
    # this tool wrote carried neither, so their presence here proves the
    # bundle went through rauc rather than being assembled by hand.
    has "rauc computed the image digest into the manifest" "sha256=" "$BT/manifest.raucm"
    # And the sidecars inside the bundle must be the ones derived from the
    # image inside the bundle -- not a stale set copied from somewhere.
    BSALT=$(sha256sum "$BT/fus-app-container.squashfs" | cut -d' ' -f1)
    has "the .info payload digest is the bundled image's" "payload.sha256=$BSALT" "$ARTIFACT.info"
else
    echo "SKIP (case): unsquashfs not installed (Debian package: squashfs-tools)"
fi

echo "# --- against the Yocto app bundle: what matches and what drifts ---"
# The positive half, and it is the load-bearing assertion of this round: the
# identity of both bundles must agree in EVERY field except the payload
# digest and size. compatible, version, format, the bundle hook verb, the
# image filename and the image hook all come from the manifest wiring this
# round added, and they are compared against the real Yocto artifact.
"$VERIFY" --keyring "$CA" --identity-out "$TMP/id.ours" "$ARTIFACT" \
    > "$TMP/idr.out" 2> "$TMP/idr.err"
check "identity of our bundle -> 0" 0 "$?"
"$VERIFY" --keyring "$CA" --identity-out "$TMP/id.yocto" "$FUS_IT_APP_REFERENCE" \
    > "$TMP/idy.out" 2> "$TMP/idy.err"
check "identity of the Yocto bundle -> 0" 0 "$?"
if [ -f "$TMP/id.ours" ] && [ -f "$TMP/id.yocto" ]; then
    # build= differs by design; the payload DIGEST is the measured packer
    # drift and is the only other field allowed to differ. image.appfs.size
    # is deliberately NOT stripped: the header records it as identical, and a
    # size that started to drift too must turn this red rather than pass
    # unmeasured.
    for _f in "$TMP/id.ours" "$TMP/id.yocto"; do
        sed -e '/^build=/d' -e '/^image\.appfs\.sha256=/d' \
            "$_f" > "$_f.cmp"
    done
    diff -u "$TMP/id.yocto.cmp" "$TMP/id.ours.cmp" > "$TMP/id.diff" 2>&1
    check "every identity field but the payload digest matches Yocto" 0 "$?"
    if [ -s "$TMP/id.diff" ]; then
        echo "# the differing fields (this difference is the finding, do not tune it):"
        cat "$TMP/id.diff"
    fi
    has "and the compared set really carried the compatible" \
        "compatible=fus-update-fsimx8mp-appfs" "$TMP/id.ours.cmp"
    has "and the bundle hook verb"  "hooks=install-check" "$TMP/id.ours.cmp"
    has "and the appfs image name"  "image.appfs.filename=fus-app-container.squashfs" \
        "$TMP/id.ours.cmp"
    has "and the appfs image hook"  "image.appfs.hooks=install" "$TMP/id.ours.cmp"
fi
# The full diff, recorded rather than asserted: the packer drift makes it
# fail, and that verdict is the honest one to publish.
"$VERIFY" --keyring "$CA" --reference "$FUS_IT_APP_REFERENCE" "$ARTIFACT" \
    > "$TMP/ref.out" 2> "$TMP/ref.err"
_ref_rc=$?
echo "# repack drift verdict against the Yocto app bundle (record it, do not tune it): exit $_ref_rc"
if [ "$_ref_rc" -eq 0 ]; then
    echo "# repack.drift=none -- the repacked squashfs digest equals Yocto's"
    has "reference=match" "reference=match" "$TMP/ref.out"
else
    echo "# repack.drift=present -- the differing fields:"
    cat "$TMP/ref.err"
    # Whatever the drift is, it must be confined to the payload bytes: a
    # mismatch naming the compatible or a hook would be a wiring defect
    # hiding behind a known packer difference.
    lacks "the drift does not touch the compatible" "compatible:" "$TMP/ref.err"
    lacks "the drift does not touch the bundle hooks" "hooks:" "$TMP/ref.err"
    lacks "the drift does not touch the image filename" "image.appfs.filename" "$TMP/ref.err"
    lacks "the drift does not touch the image hook" "image.appfs.hooks" "$TMP/ref.err"
    has "the drift names the payload digest" "image.appfs.sha256" "$TMP/ref.err"
fi

echo "# --- reference=match, proven between two builds of this tool ---"
"$MK" --version "$IT_VERSION" --out "$OUT" \
    --app-dir "$FUS_IT_APP_TREE" \
    --app-binaries fus-demo-app --app-id fus-demo-app \
    --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" "$@" \
    --build-stamp 20260901140001 > "$TMP/mk2.out" 2> "$TMP/mk2.err"
check "second build from the same tree -> 0" 0 "$?"
ARTIFACT2=$(sed -n 's/^artifact=//p' "$TMP/mk2.out")
"$VERIFY" --keyring "$CA" --reference "$ARTIFACT" "$ARTIFACT2" \
    > "$TMP/self.out" 2> "$TMP/self.err"
check "two builds of the same tree diff clean -> 0" 0 "$?"
has "reference=match (own reproducibility)" "reference=match" "$TMP/self.out"
if ! grep -qF "reference=match" "$TMP/self.out"; then
    echo "# the differing fields (this difference is the finding, do not tune it):"
    cat "$TMP/self.err"
fi

echo "# --- the counter-proof: a wrong compatible must fail the same diff ---"
"$MK" --version "$IT_VERSION" --out "$OUT" \
    --app-dir "$FUS_IT_APP_TREE" \
    --app-binaries fus-demo-app --app-id fus-demo-app \
    --compatible fus-update-wrongboard-appfs \
    --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" "$@" \
    --build-stamp 20260901140002 > "$TMP/mk3.out" 2> "$TMP/mk3.err"
check "wrong-compat build -> 0 (the bundle itself is valid)" 0 "$?"
ARTIFACT3=$(sed -n 's/^artifact=//p' "$TMP/mk3.out")
"$VERIFY" --keyring "$CA" --reference "$ARTIFACT" "$ARTIFACT3" \
    > "$TMP/ctr.out" 2> "$TMP/ctr.err"
check "wrong-compat vs our own reference -> 8" 8 "$?"
has "the diff names the compatible" "compatible" "$TMP/ctr.err"
lacks "no reference=match for the counter-proof" "reference=match" "$TMP/ctr.out"

echo "# --- the payload contract, refused on a real tree (5) ---"
# A copy of the real tree with its identity file taken away: the contract has
# to fire on the real thing, not only on the synthetic trees the hermetic
# suite builds.
BROKEN="$TMP/broken-tree"
cp -a "$FUS_IT_APP_TREE" "$BROKEN" 2>/dev/null || cp -r "$FUS_IT_APP_TREE" "$BROKEN"
if [ -f "$BROKEN/etc/app-release" ]; then
    rm -f "$BROKEN/etc/app-release"
    mkdir -p "$TMP/out-c"
    "$MK" --version "$IT_VERSION" --out "$TMP/out-c" --app-dir "$BROKEN" \
        --app-binaries fus-demo-app --app-id fus-demo-app \
        --certs "$FUS_IT_CERTS_DEV" --keyring "$CA" \
        --build-stamp 20260901140003 > "$TMP/br.out" 2> "$TMP/br.err"
    check "a real tree without etc/app-release -> 5" 5 "$?"
    has "the refusal names app-release" "app-release" "$TMP/br.err"
    check "nothing was published" "" "$(ls -A "$TMP/out-c")"
else
    echo "SKIP (case): the app tree carries no etc/app-release to remove"
fi

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
