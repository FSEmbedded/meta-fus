#!/bin/sh
# fus-mk-app-bundle.test.sh -- hermetic self-test for fus-mk-app-bundle.sh
# (pattern: fus-mk-fw-bundle.test.sh). rauc is fus-rauc-stub.sh in a
# temporary PATH -- the single source of the canned answer block -- and
# mksquashfs, veritysetup and openssl are the shared stubs from
# fus-test-lib.sh. sha256sum is deliberately REAL: the salt contract says the
# salt is the packed image's own sha256, and a stubbed digest would make that
# claim unfalsifiable here. No network, no layer checkout. The real accept
# path is pinned separately by fus-mk-app-bundle.integration.sh.
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
fus_test_init
fail=0
# an exported app signing pair would change what the default cases measure
unset FUS_APP_CONTAINER_SIGN_CERT FUS_APP_CONTAINER_SIGN_KEY

MK="$DIR/fus-mk-app-bundle.sh"
FWMK="$DIR/fus-mk-fw-bundle.sh"

KEYRING="$TMP/ca.pem";  printf 'stub keyring\n' > "$KEYRING"
CERT="$TMP/sign.cert";  printf 'stub cert\n' > "$CERT"
KEY="$TMP/sign.key";    printf 'stub key\n' > "$KEY"
EMPTY_KEYRING="$TMP/empty.pem"; : > "$EMPTY_KEYRING"
STAMP=20260901120000

# A contract-complete app tree, built by hand so every guard has one thing to
# take away. The layout mirrors the real container payload: an executable
# under usr/bin, etc/app_version and etc/app-release with a matching
# IMAGE_ID.
mkapptree() { # mkapptree <dir> <marker>
    mkdir -p "$1/usr/bin" "$1/etc"
    printf '#!/bin/sh\necho %s\n' "$2" > "$1/usr/bin/fus-demo-app"
    chmod +x "$1/usr/bin/fus-demo-app"
    printf '20260817\n' > "$1/etc/app_version"
    printf 'APP_ID=fus-demo-app\nAPP_VERSION=20260817\nIMAGE_ID=fus-demo-app\n' \
        > "$1/etc/app-release"
}
APPTREE="$TMP/apptree";  mkapptree "$APPTREE" one
APPTREE2="$TMP/apptree2"; mkapptree "$APPTREE2" two
EMPTYTREE="$TMP/empty-tree"; mkdir -p "$EMPTYTREE"

fus_test_install_rauc_stub "$DIR"
fus_test_install_mksquashfs_stub
fus_test_install_verity_stubs

# A valid build, as a SCRIPT (not a function) so cases can prefix it with
# `env STUB_...=...`. Later flags override the baked-in ones. The canned rauc
# block is fw-shaped by default, so the app-shaped values it must report back
# to the mandatory self-verification are set here.
APPSTUB="STUB_COMPAT=fus-update-fsimx8mp-appfs STUB_HOOKS=install-check"
APPSTUB="$APPSTUB STUB_IMAGE_NAME=fus-app-container.squashfs STUB_IMAGE_HOOKS=install"
APPSTUB="$APPSTUB STUB_IMAGE_CLASS=appfs"
MKOK="$TMP/mk-ok"
# The stub values are DEFAULTED, never forced: a case that prefixes this
# wrapper with its own STUB_COMPAT must win, or the drift cases below would
# silently measure the wrapper instead of the tool. The defaults fill an
# UNSET value only -- an explicitly empty override is a case in its own right
# (a bundle with no hook verb at all) and must reach the stub as empty.
cat > "$MKOK" <<EOF
#!/bin/sh
_o=\$1; shift
: "\${STUB_COMPAT=fus-update-fsimx8mp-appfs}"
: "\${STUB_HOOKS=install-check}"
: "\${STUB_IMAGE_NAME=fus-app-container.squashfs}"
: "\${STUB_IMAGE_HOOKS=install}"
: "\${STUB_IMAGE_CLASS=appfs}"
export STUB_COMPAT STUB_HOOKS STUB_IMAGE_NAME STUB_IMAGE_HOOKS STUB_IMAGE_CLASS
exec env PATH="$SPATH" \\
    "$MK" --version 20260902 --out "\$_o" \\
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \\
    --cert "$CERT" --key "$KEY" \\
    --keyring "$KEYRING" --build-stamp "$STAMP" "\$@"
EOF
chmod +x "$MKOK"

echo "# --- usage and argument errors (rauc must never be invoked) ---"
LOG="$TMP/rauc.log"; : > "$LOG"
mkdir -p "$TMP/out-u"
rc_is "no --app-dir -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --version 20260902 --out "$TMP/out-u" --cert "$CERT" --key "$KEY" \
    --keyring "$KEYRING" --app-binaries fus-demo-app --app-id fus-demo-app
rc_is "missing --version -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --out "$TMP/out-u" --app-dir "$APPTREE" --cert "$CERT" --key "$KEY" \
    --keyring "$KEYRING" --app-binaries fus-demo-app --app-id fus-demo-app
rc_is "version not semver -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" \
    --version not.a-version-
rc_is "--out does not exist -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/no-out"
rc_is "missing --keyring -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --version 20260902 --out "$TMP/out-u" --app-dir "$APPTREE" \
    --cert "$CERT" --key "$KEY" --app-binaries fus-demo-app --app-id fus-demo-app
# The two app-contract inputs are MANDATORY, not defaulted: the layer's
# fus-demo-app is the reference app, and defaulting to it would let a
# bring-your-own-app payload pass a check that measured nothing about it.
env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    --app-id fus-demo-app > "$TMP/ab.out" 2> "$TMP/ab.err"
check "missing --app-binaries -> 2" 2 "$?"
has "the refusal names --app-binaries" "--app-binaries" "$TMP/ab.err"
lacks "the refusal invents no default" "fus-demo-app" "$TMP/ab.err"
env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    --app-binaries fus-demo-app > "$TMP/ai.out" 2> "$TMP/ai.err"
check "missing --app-id -> 2" 2 "$?"
has "the refusal names --app-id" "--app-id" "$TMP/ai.err"
# This door carries no uid guard, and -all-root is the ONLY reason it needs
# none. The constant is overridable, so the premise is asserted: without the
# flag a non-root run would ship the builder's ownership with nothing
# refusing it -- exactly what the firmware door answers 11 for.
MLOGA="$TMP/mksq-ar.log"; : > "$MLOGA"
env STUB_MKSQ_LOG="$MLOGA" FUS_APP_MKSQUASHFS_ARGS="-noappend -comp zstd" \
    "$MKOK" "$TMP/out-u" > "$TMP/ar.out" 2> "$TMP/ar.err"
check "FUS_APP_MKSQUASHFS_ARGS without -all-root -> 2" 2 "$?"
has "the refusal names the variable" "FUS_APP_MKSQUASHFS_ARGS" "$TMP/ar.err"
has "the refusal names the missing flag" "-all-root" "$TMP/ar.err"
has "the refusal says why this door has no guard" "no ownership guard" "$TMP/ar.err"
check "refused before any mksquashfs call" "" "$(cat "$MLOGA")"
# Word-wise, not substring: "-all-rootish" must not satisfy the requirement.
rc_is "-all-rootish does not satisfy the requirement -> 2" 2 \
    env FUS_APP_MKSQUASHFS_ARGS="-noappend -all-rootish" "$MKOK" "$TMP/out-u"
rc_is "unknown option -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" --frobnicate
rc_is "unexpected operand -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" bundle.raucb
rc_is "unusable machine name -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" --machine a/b
# The payload name is a constant, but every library constant is overridable
# from the environment -- and an override that collides with a reserved
# bundle entry would be silently overwritten by the hook or the manifest,
# producing a bundle that builds, publishes and then fails on the device.
rc_is "payload name overridden to a reserved entry -> 2" 2 \
    env STUB_RAUC_LOG="$LOG" FUS_APP_PAYLOAD_NAME=install-check "$MKOK" "$TMP/out-u"
rc_is "payload name overridden to the manifest -> 2" 2 \
    env STUB_RAUC_LOG="$LOG" FUS_APP_PAYLOAD_NAME=manifest.raucm "$MKOK" "$TMP/out-u"
rc_is "payload name overridden with a path -> 2" 2 \
    env STUB_RAUC_LOG="$LOG" FUS_APP_PAYLOAD_NAME=sub/dir.squashfs "$MKOK" "$TMP/out-u"
# The lever itself still works: a renamed payload is legitimate, and the
# manifest must follow it.
mkdir -p "$TMP/out-rn"
env FUS_APP_PAYLOAD_NAME=renamed-app.squashfs "$MKOK" "$TMP/out-rn" --dry-run \
    > "$TMP/rn.out" 2>&1
check "a legitimate payload rename -> 0" 0 "$?"
has "the manifest follows the renamed payload" "filename=renamed-app.squashfs" "$TMP/rn.out"
mkdir -p "$TMP/out-e"
: > "$TMP/out-e/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb"
rc_is "artifact already exists -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-e"
check "call errors never invoked rauc" "" "$(cat "$LOG")"

echo "# --- tool resolution and the window ---"
rc_is "emptied PATH -> 3" 3 env PATH= "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"
# One PATH per missing tool: the app door needs five, and a message naming
# the wrong Debian package is as useless as no message at all.
for _t in mksquashfs veritysetup openssl sha256sum; do
    mkdir -p "$TMP/bin-no$_t"
    for _c in rauc mksquashfs veritysetup openssl; do
        [ "$_c" = "$_t" ] && continue
        cp "$TMP/bin/$_c" "$TMP/bin-no$_t/" 2>/dev/null || :
    done
    [ "$_t" = sha256sum ] || cp "$(command -v sha256sum)" "$TMP/bin-no$_t/sha256sum"
done
env PATH="$TMP/bin-nomksquashfs" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP" \
    > "$TMP/nm.out" 2> "$TMP/nm.err"
check "missing mksquashfs -> 3" 3 "$?"
has "the message names the Debian package" "squashfs-tools" "$TMP/nm.err"
env PATH="$TMP/bin-noveritysetup" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP" \
    > "$TMP/nv.out" 2> "$TMP/nv.err"
check "missing veritysetup -> 3" 3 "$?"
has "the message names cryptsetup-bin" "cryptsetup-bin" "$TMP/nv.err"
env PATH="$TMP/bin-noopenssl" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP" \
    > "$TMP/no.out" 2> "$TMP/no.err"
check "missing openssl -> 3" 3 "$?"
has "the message names openssl" "openssl" "$TMP/no.err"
env PATH="$TMP/bin-nosha256sum" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP" \
    > "$TMP/ns.out" 2> "$TMP/ns.err"
check "missing sha256sum -> 3" 3 "$?"
has "the message names coreutils" "coreutils" "$TMP/ns.err"
rc_is "rauc below the window -> 3" 3 env STUB_RAUC_VERSION=1.12 "$MKOK" "$TMP/out-u"
env PATH="$SPATH" "$MK" --check-tools > "$TMP/ct.out" 2>&1
check "--check-tools -> 0" 0 "$?"
has "check-tools reports rauc"        "tool.rauc.version="        "$TMP/ct.out"
has "check-tools reports mksquashfs"  "tool.mksquashfs.version="  "$TMP/ct.out"
has "check-tools reports veritysetup" "tool.veritysetup.version=" "$TMP/ct.out"
has "check-tools reports openssl"     "tool.openssl.version="     "$TMP/ct.out"
has "check-tools reports sha256sum"   "tool.sha256sum.version="   "$TMP/ct.out"
has "check-tools reports the window"  "rauc.window=1.13..1.15.2"  "$TMP/ct.out"
rc_is "--check-tools under the window -> 3" 3 env PATH="$SPATH" STUB_RAUC_VERSION=1.12 "$MK" --check-tools
rc_is "--require-rauc mismatch -> 3" 3 "$MKOK" "$TMP/out-u" --require-rauc 1.13
"$MKOK" "$TMP/out-u" --expect-rauc 1.13 --dry-run > /dev/null 2> "$TMP/er.err"
check "--expect-rauc mismatch only warns -> 0" 0 "$?"
has "expect-rauc warns" "expected '1.13'" "$TMP/er.err"

echo "# --- signing material (4) ---"
rc_is "no cert and no key -> 4" 4 env PATH="$SPATH" "$MK" --version 20260902 \
    --out "$TMP/out-u" --app-dir "$APPTREE" --app-binaries fus-demo-app \
    --app-id fus-demo-app --keyring "$KEYRING" --build-stamp "$STAMP"
env PATH="$SPATH" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$TMP/secret-missing.pem" --key "$KEY" \
    --keyring "$KEYRING" --build-stamp "$STAMP" > "$TMP/c4.out" 2> "$TMP/c4.err"
check "unreadable cert -> 4" 4 "$?"
lacks "the cert message withholds the path" "secret-missing" "$TMP/c4.err"
rc_is "empty keyring file -> 4" 4 "$MKOK" "$TMP/out-u" --keyring "$EMPTY_KEYRING"
# The fw door accepts pkcs11 URIs because only rauc ever touches the key.
# The app door signs the root hash with openssl itself, which cannot take a
# URI without an engine/provider setup this tool does not build -- so the
# refusal is explicit rather than a confusing openssl error one step later.
env PATH="$SPATH" "$MK" --version 20260902 --out "$TMP/out-u" \
    --app-dir "$APPTREE" --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "pkcs11:token=stub;object=cert" --key "$KEY" \
    --keyring "$KEYRING" --build-stamp "$STAMP" > "$TMP/p11.out" 2> "$TMP/p11.err"
check "pkcs11 cert -> 4" 4 "$?"
has "the refusal names the sidecar signature" "roothash" "$TMP/p11.err"
rc_is "pkcs11 key -> 4" 4 env PATH="$SPATH" "$MK" --version 20260902 \
    --out "$TMP/out-u" --app-dir "$APPTREE" --app-binaries fus-demo-app \
    --app-id fus-demo-app --cert "$CERT" --key "pkcs11:token=stub;object=key" \
    --keyring "$KEYRING" --build-stamp "$STAMP"

echo "# --- the app payload contract, one case per contract line (5) ---"
rc_is "app directory does not exist -> 5" 5 "$MKOK" "$TMP/out-u" --app-dir "$TMP/no-such-tree"
rc_is "app directory is empty -> 5" 5 "$MKOK" "$TMP/out-u" --app-dir "$EMPTYTREE"
rc_is "missing hook -> 5" 5 "$MKOK" "$TMP/out-u" --hook "$TMP/no-hook"
# 1. every named binary present AND executable
BINTREE="$TMP/tree-nobin"; mkapptree "$BINTREE" nobin; rm "$BINTREE/usr/bin/fus-demo-app"
"$MKOK" "$TMP/out-u" --app-dir "$BINTREE" > "$TMP/b1.out" 2> "$TMP/b1.err"
check "app binary missing -> 5" 5 "$?"
has "the refusal names the binary" "fus-demo-app" "$TMP/b1.err"
has "the refusal names the contract" "no program to run" "$TMP/b1.err"
NOXTREE="$TMP/tree-noexec"; mkapptree "$NOXTREE" noexec; chmod -x "$NOXTREE/usr/bin/fus-demo-app"
rc_is "app binary present but not executable -> 5" 5 "$MKOK" "$TMP/out-u" --app-dir "$NOXTREE"
# A binary list of two, one of them absent: the loop must not stop at the
# first hit and call the contract satisfied.
rc_is "second binary of a list missing -> 5" 5 "$MKOK" "$TMP/out-u" \
    --app-binaries "fus-demo-app fus-demo-helper"
# 2. etc/app_version present and non-empty
VERTREE="$TMP/tree-nover"; mkapptree "$VERTREE" nover; rm "$VERTREE/etc/app_version"
"$MKOK" "$TMP/out-u" --app-dir "$VERTREE" > "$TMP/v1.out" 2> "$TMP/v1.err"
check "app_version missing -> 5" 5 "$?"
has "the refusal names app_version" "app_version" "$TMP/v1.err"
EMPTYVER="$TMP/tree-emptyver"; mkapptree "$EMPTYVER" ev; : > "$EMPTYVER/etc/app_version"
rc_is "app_version empty -> 5" 5 "$MKOK" "$TMP/out-u" --app-dir "$EMPTYVER"
# 3. etc/app-release present, with an IMAGE_ID equal to --app-id
RELTREE="$TMP/tree-norel"; mkapptree "$RELTREE" norel; rm "$RELTREE/etc/app-release"
"$MKOK" "$TMP/out-u" --app-dir "$RELTREE" > "$TMP/r1.out" 2> "$TMP/r1.err"
check "app-release missing -> 5" 5 "$?"
has "the refusal names app-release" "app-release" "$TMP/r1.err"
"$MKOK" "$TMP/out-u" --app-id other-app > "$TMP/r2.out" 2> "$TMP/r2.err"
check "IMAGE_ID does not match --app-id -> 5" 5 "$?"
has "the refusal names the configured id" "other-app" "$TMP/r2.err"
has "the refusal names the found id" "fus-demo-app" "$TMP/r2.err"
IDLESS="$TMP/tree-noid"; mkapptree "$IDLESS" noid
printf 'APP_ID=fus-demo-app\n' > "$IDLESS/etc/app-release"
rc_is "app-release without any IMAGE_ID -> 5" 5 "$MKOK" "$TMP/out-u" --app-dir "$IDLESS"
check "no contract failure left a fragment in --out" "" "$(ls -A "$TMP/out-u")"

echo "# --- the sidecar step: no bundle can leave without all three (7) ---"
mkdir -p "$TMP/out-s1" "$TMP/out-s2" "$TMP/out-s3" "$TMP/out-s4" "$TMP/out-s5" "$TMP/out-s6"
rc_is "veritysetup fails -> 7" 7 env STUB_VERITY_RC=1 "$MKOK" "$TMP/out-s1"
check "no fragment after the verity failure" "" "$(ls -A "$TMP/out-s1")"
env STUB_VERITY_NO_ROOTHASH=1 "$MKOK" "$TMP/out-s2" > "$TMP/s2.out" 2> "$TMP/s2.err"
check "veritysetup exits 0 without a root hash -> 7" 7 "$?"
has "the abort names the missing root hash" "roothash" "$TMP/s2.err"
check "no fragment after the missing root hash" "" "$(ls -A "$TMP/out-s2")"
env STUB_VERITY_NO_TREE=1 "$MKOK" "$TMP/out-s3" > "$TMP/s3.out" 2> "$TMP/s3.err"
check "veritysetup exits 0 without a hash tree -> 7" 7 "$?"
has "the abort names the missing hash tree" "verity" "$TMP/s3.err"
rc_is "openssl fails -> 7" 7 env STUB_OPENSSL_RC=1 "$MKOK" "$TMP/out-s4"
env STUB_OPENSSL_EMPTY=1 "$MKOK" "$TMP/out-s5" > "$TMP/s5.out" 2> "$TMP/s5.err"
check "openssl exits 0 without a signature -> 7" 7 "$?"
has "the abort names the missing signature" "p7s" "$TMP/s5.err"
check "no fragment after the missing signature" "" "$(ls -A "$TMP/out-s5")"
# A root hash of the wrong shape is worse than none: it would travel into the
# build evidence as a convincing-looking value the device then rejects.
mkdir -p "$TMP/out-s7"
env STUB_VERITY_BAD_ROOTHASH=1 "$MKOK" "$TMP/out-s7" > "$TMP/s7.out" 2> "$TMP/s7.err"
check "a malformed root hash -> 7" 7 "$?"
has "the abort names the root hash shape" "root hash" "$TMP/s7.err"
check "no fragment after the malformed root hash" "" "$(ls -A "$TMP/out-s7")"
rc_is "mksquashfs fails -> 7" 7 env STUB_MKSQ_RC=1 "$MKOK" "$TMP/out-s6"
rc_is "mksquashfs writes no output -> 7" 7 env STUB_MKSQ_EMPTY=1 "$MKOK" "$TMP/out-s6"
check "no fragment after the pack failure" "" "$(ls -A "$TMP/out-s6")"

echo "# --- the manifest: the bundle hook verb the device needs ---"
mkdir -p "$TMP/out-dry"
"$MKOK" "$TMP/out-dry" --dry-run > "$TMP/dry.out" 2> "$TMP/dry.err"
check "dry run -> 0" 0 "$?"
has "dry run prints the manifest"        "[update]" "$TMP/dry.out"
has "dry run: the -appfs compatible"     "compatible=fus-update-fsimx8mp-appfs" "$TMP/dry.out"
has "dry run: verity format"             "format=verity" "$TMP/dry.out"
has "dry run: the hook filename"         "filename=install-check" "$TMP/dry.out"
has "dry run: the BUNDLE hook verb"      "hooks=install-check" "$TMP/dry.out"
has "dry run: the appfs image section"   "[image.appfs]" "$TMP/dry.out"
has "dry run: the payload filename"      "filename=fus-app-container.squashfs" "$TMP/dry.out"
check "dry run builds nothing" "" "$(ls -A "$TMP/out-dry")"
# The [hooks] section, sliced: the app door writes exactly two lines there,
# and a bare grep for "hooks=" would also hit the image section.
sed -n '/^\[hooks\]/,/^$/p' "$TMP/dry.out" > "$TMP/dry.hooks"
has "app [hooks]: filename line" "filename=install-check" "$TMP/dry.hooks"
has "app [hooks]: bundle hook line" "hooks=install-check" "$TMP/dry.hooks"
# And the image section, sliced for the same reason: a bare grep for
# "hooks=install" is already satisfied by the bundle verb two sections up,
# so the image hook needs its own slice and a WHOLE-line match -- otherwise
# post-install, or no image hook at all, would pass here.
sed -n '/^\[image\.appfs\]/,/^$/p' "$TMP/dry.out" > "$TMP/dry.appfs"
has "dry run [image.appfs]: the payload filename" "filename=fus-app-container.squashfs" "$TMP/dry.appfs"
check "dry run [image.appfs]: the image hook is exactly install" 1 \
    "$(grep -cxF 'hooks=install' "$TMP/dry.appfs")"
# The counter-case: the fw door must be untouched by the new parameter. Same
# slice, and it must carry the filename line and NO hooks line -- the fw
# manifest's own "hooks=post-install" lives in [image.rootfs], which is why
# the section is sliced rather than grepped whole.
mkdir -p "$TMP/src" "$TMP/out-fw"
PAYLOAD="$TMP/src/fusys-image-eval-fsimx8mp.squashfs"
printf 'hsqs stub squashfs payload bytes\n' > "$PAYLOAD"
env PATH="$SPATH" "$FWMK" --version 20260902 --out "$TMP/out-fw" \
    --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    --build-stamp "$STAMP" --dry-run > "$TMP/fwdry.out" 2>&1
check "fw dry run -> 0" 0 "$?"
sed -n '/^\[hooks\]/,/^$/p' "$TMP/fwdry.out" > "$TMP/fwdry.hooks"
has "fw [hooks]: filename line still there" "filename=install-check" "$TMP/fwdry.hooks"
lacks "fw [hooks]: still NO bundle hook line" "hooks=" "$TMP/fwdry.hooks"
has "fw manifest keeps its image hook" "hooks=post-install" "$TMP/fwdry.out"
# And the same at the source: the library function itself, called the way the
# fw door calls it, must not grow a line.
( . "$DIR/fus-bundle-lib.sh" && fus_manifest_begin c v d b verity install-check ) \
    > "$TMP/mb6.out" 2>&1
sed -n '/^\[hooks\]/,$p' "$TMP/mb6.out" > "$TMP/mb6.hooks"
check "fus_manifest_begin with six arguments: the section is two lines" 2 \
    "$(grep -c . "$TMP/mb6.hooks")"
lacks "six arguments write no bundle hook verb" "hooks=" "$TMP/mb6.hooks"
( . "$DIR/fus-bundle-lib.sh" && fus_manifest_begin c v d b verity install-check '' ) \
    > "$TMP/mb7.out" 2>&1
sed -n '/^\[hooks\]/,$p' "$TMP/mb7.out" > "$TMP/mb7.hooks"
lacks "an empty seventh argument writes no bundle hook verb" "hooks=" "$TMP/mb7.hooks"
( . "$DIR/fus-bundle-lib.sh" && fus_manifest_begin c v d b verity install-check install-check ) \
    > "$TMP/mb7b.out" 2>&1
has "a filled seventh argument writes the verb" "hooks=install-check" "$TMP/mb7b.out"

echo "# --- the happy path ---"
OUT="$TMP/out"; mkdir -p "$OUT"
LOG2="$TMP/rauc-build.log"; : > "$LOG2"
VLOG="$TMP/verity.log"; : > "$VLOG"
OLOG="$TMP/openssl.log"; : > "$OLOG"
env STUB_RAUC_LOG="$LOG2" STUB_CONTENT_LIST="$TMP/content.list" \
    STUB_CONTENT_COPY="$TMP/content.copy" STUB_VERITY_LOG="$VLOG" \
    STUB_OPENSSL_LOG="$OLOG" \
    "$MKOK" "$OUT" > "$TMP/ok.out" 2> "$TMP/ok.err"
check "build -> 0" 0 "$?"
has "stdout names the artifact" "artifact=$OUT/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb" "$TMP/ok.out"
has "stdout reports the verdict" "result=pass" "$TMP/ok.out"
check "stamped artifact exists" yes \
    "$([ -f "$OUT/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb" ] && echo yes)"
check "info rides the stamped name" yes \
    "$([ -f "$OUT/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb.info" ] && echo yes)"
check "symlink points at the stamped name" "ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb" \
    "$(readlink "$OUT/ext-fus-app-bundle-fsimx8mp.raucb")"
lacks "bundle runs without --signing-keyring" "signing-keyring" "$LOG2"
# Six entries, not the fw door's three: payload + 3 sidecars + hook + manifest.
check "content holds exactly six entries" 6 "$(grep -c . "$TMP/content.list")"
has "content: the packed payload"  "fus-app-container.squashfs" "$TMP/content.list"
has "content: the hash tree"       "fus-app-container.squashfs.verity" "$TMP/content.list"
has "content: the root hash"       "fus-app-container.squashfs.roothash" "$TMP/content.list"
has "content: the signature"       "fus-app-container.squashfs.roothash.p7s" "$TMP/content.list"
has "content: the hook"            "install-check"  "$TMP/content.list"
has "content: the manifest"        "manifest.raucm" "$TMP/content.list"
# The sidecar NAMES are the device contract: fus-app-container-runtime's mount
# verb looks up "$img.verity" for the (renamed) image path, so a stem-keyed
# name would be found by nothing.
lacks "sidecars are image-keyed, not stem-keyed" "fus-app-container.verity" "$TMP/content.list"
lacks "root hash is image-keyed too" "fus-app-container.roothash" "$TMP/content.list"
MF="$TMP/content.copy/manifest.raucm"
has "manifest: compatible"     "compatible=fus-update-fsimx8mp-appfs" "$MF"
has "manifest: version"        "version=20260902" "$MF"
has "manifest: build stamp"    "build=$STAMP" "$MF"
has "manifest: verity format"  "format=verity" "$MF"
has "manifest: hook filename"  "filename=install-check" "$MF"
has "manifest: bundle hook"    "hooks=install-check" "$MF"
has "manifest: the appfs image" "[image.appfs]" "$MF"
sed -n '/^\[image\.appfs\]/,/^$/p' "$MF" > "$TMP/mf.appfs"
check "manifest [image.appfs]: the image hook is exactly install" 1 \
    "$(grep -cxF 'hooks=install' "$TMP/mf.appfs")"
lacks "manifest carries no digest (rauc computes it)" "sha256" "$MF"
# The three sidecars ride as plain content members, exactly as the recipe's
# RAUC_BUNDLE_EXTRA_FILES does: EXACTLY ONE [image.*] section, whatever it is
# called -- counting is the check, because a literal name no implementation
# would ever emit proves nothing.
check "exactly one [image.] section in the manifest" 1 \
    "$(grep -c '^\[image\.' "$MF")"
HOOKC="$TMP/content.copy/install-check"
has "staged hook: token substituted" "/data/app/images" "$HOOKC"
lacks "staged hook: no raw token left" "@@FUS_APP_IMG_DIR@@" "$HOOKC"
check "staged hook is executable" yes "$([ -x "$HOOKC" ] && echo yes)"
# THE derivation check: the salt veritysetup was handed must be the packed
# image's own sha256, and the uuid its 8-4-4-4-12 slicing. Without this a
# wrong (e.g. random, or source-tree-derived) salt passes every other case.
PACKED_SHA=$(sha256sum "$TMP/content.copy/fus-app-container.squashfs" | cut -d' ' -f1)
has "the salt is the packed image's sha256" "--salt=$PACKED_SHA" "$VLOG"
EXP_UUID=$(printf '%s' "$PACKED_SHA" | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/')
has "the uuid is that sha256, sliced 8-4-4-4-12" "--uuid=$EXP_UUID" "$VLOG"
has "veritysetup writes the image-keyed root hash file" \
    "--root-hash-file=$TMP" "$VLOG"
has "the root hash file name is image-keyed" \
    "fus-app-container.squashfs.roothash" "$VLOG"
check "openssl signs the root hash file ITSELF (-in, not just -out)" 1 \
    "$(grep -cE -- '-in [^ ]*/fus-app-container\.squashfs\.roothash( |$)' "$OLOG")"
has "the signature is detached DER" "-outform der" "$OLOG"
has "the signature carries no attributes" "-noattr" "$OLOG"
has "without --verity-cert the bundle certificate signs the root hash" \
    "-signer $CERT" "$OLOG"
INFO="$OUT/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
has "info: rauc version"          "tool.rauc.version=rauc 1.15.2" "$INFO"
has "info: mksquashfs version"    "tool.mksquashfs.version=" "$INFO"
has "info: veritysetup version"   "tool.veritysetup.version=" "$INFO"
has "info: openssl version"       "tool.openssl.version=" "$INFO"
has "info: the window"            "rauc.window=1.13..1.15.2" "$INFO"
has "info: the slot class"        "const.FUS_APP_SLOT_CLASS=appfs" "$INFO"
has "info: the image hook"        "const.FUS_APP_IMAGE_HOOK=install" "$INFO"
has "info: the bundle hook"       "const.FUS_APP_BUNDLE_HOOK=install-check" "$INFO"
has "info: the payload name"      "const.FUS_APP_PAYLOAD_NAME=fus-app-container.squashfs" "$INFO"
has "info: the all-root pack args" "-all-root" "$INFO"
has "info: source date epoch"     "source_date_epoch=" "$INFO"
has "info: sha256sum version"     "tool.sha256sum.version=" "$INFO"
has "info: the payload digest"    "payload.sha256=$PACKED_SHA" "$INFO"
has "info: the verity uuid"       "verity.uuid=$EXP_UUID" "$INFO"
# The exact value, not merely the key: the stub derives its root hash from
# the salt and uuid it was handed, so this is computable here -- and a
# `verity.roothash=` with nothing behind it would otherwise pass.
EXP_ROOT=$(printf '%s|%s' "$PACKED_SHA" "$EXP_UUID" | sha256sum | cut -d' ' -f1)
has "info: the derived root hash" "verity.roothash=$EXP_ROOT" "$INFO"
has "info: the suffix warning is clear" "compatible.suffix_warning=no" "$INFO"
has "info: the app id"            "app.id=fus-demo-app" "$INFO"
has "info: the app binaries"      "app.binaries=fus-demo-app" "$INFO"
has "info: shape warning clear"   "version.shape_warning=no" "$INFO"
has "info: identity travelled"    "compatible=fus-update-fsimx8mp-appfs" "$INFO"
has "info: chain subject"         "signature.subject=" "$INFO"
has "info: chain SPKI"            "signature.spki_sha256=" "$INFO"
lacks "info holds no host paths"  "$TMP" "$INFO"
# The app payload is packed -all-root by design, so this door makes no
# ownership claim and must not carry the fw door's guard lines.
lacks "app info carries no ownership claim" "ownership." "$INFO"
# The app payload's packing settings must reach the packer, not just the
# .info: -all-root is what makes the ownership guard unnecessary here.
MLOG="$TMP/mksq-args.log"; : > "$MLOG"
mkdir -p "$TMP/out-args"
env STUB_MKSQ_LOG="$MLOG" "$MKOK" "$TMP/out-args" >/dev/null 2>&1
check "the args run built a bundle -> 0" 0 "$?"
has "the pack carries -all-root"    "-all-root" "$MLOG"
has "the pack carries the layer's compression" "-comp zstd" "$MLOG"
has "the pack refuses to append"    "-noappend" "$MLOG"

echo "# --- the root hash signature can have its own certificate ---"
# The device pins one certificate for the app payload; a dedicated app leaf
# must sign the root hash while the bundle keeps the bundle certificate.
VCERT="$TMP/verity.cert"; printf 'stub verity cert\n' > "$VCERT"
VKEY="$TMP/verity.key";   printf 'stub verity key\n' > "$VKEY"
OLOGV="$TMP/openssl-v.log"; : > "$OLOGV"
RLOGV="$TMP/rauc-v.log"; : > "$RLOGV"
mkdir -p "$TMP/out-v" "$TMP/out-vp" "$TMP/out-ve" "$TMP/out-vx"
env STUB_OPENSSL_LOG="$OLOGV" STUB_RAUC_LOG="$RLOGV" "$MKOK" "$TMP/out-v" \
    --verity-cert "$VCERT" --verity-key "$VKEY" >/dev/null 2>&1
check "a separate verity pair builds -> 0" 0 "$?"
has "the verity certificate signs the root hash" "-signer $VCERT" "$OLOGV"
has "with the verity key" "-inkey $VKEY" "$OLOGV"
lacks "the bundle certificate does not sign the root hash" "-signer $CERT" "$OLOGV"
has "the bundle keeps the bundle certificate" "--cert=$CERT" "$RLOGV"
P11="pkcs11:object=verity"
"$MKOK" "$TMP/out-vp" --verity-cert "$P11" --verity-key "$VKEY" > /dev/null 2> "$TMP/p11v.err"
check "a pkcs11 verity certificate is refused -> 4" 4 "$?"
"$MKOK" "$TMP/out-vx" --verity-cert "$VCERT" > /dev/null 2> "$TMP/vhalf.err"
check "a verity certificate without its key is refused -> 2" 2 "$?"
"$MKOK" "$TMP/out-vx" --verity-key "$VKEY" > /dev/null 2>&1
check "a verity key without its certificate is refused -> 2" 2 "$?"
"$MKOK" "$TMP/out-vx" --verity-cert "$TMP/no-such.cert" --verity-key "$VKEY" \
    > /dev/null 2> "$TMP/vnone.err"
check "an unreadable verity certificate is refused -> 4" 4 "$?"
has "the refusal names the verity option" "--verity-cert" "$TMP/vnone.err"
OLOGE="$TMP/openssl-e.log"; : > "$OLOGE"
env FUS_APP_CONTAINER_SIGN_CERT="$VCERT" FUS_APP_CONTAINER_SIGN_KEY="$VKEY" \
    STUB_OPENSSL_LOG="$OLOGE" "$MKOK" "$TMP/out-ve" >/dev/null 2>&1
check "the verity pair from the environment builds -> 0" 0 "$?"
has "the environment verity certificate signs the root hash" "-signer $VCERT" "$OLOGE"

echo "# --- reproducibility: the salt is derived, never random ---"
mkdir -p "$TMP/out-r1" "$TMP/out-r2" "$TMP/out-r3"
env STUB_CONTENT_COPY="$TMP/repro1" "$MKOK" "$TMP/out-r1" \
    --source-date-epoch 1700000000 >/dev/null 2>&1
check "reproducibility run 1 -> 0" 0 "$?"
env STUB_CONTENT_COPY="$TMP/repro2" "$MKOK" "$TMP/out-r2" \
    --source-date-epoch 1700000000 >/dev/null 2>&1
check "reproducibility run 2 -> 0" 0 "$?"
for _s in verity roothash roothash.p7s; do
    cmp -s "$TMP/repro1/fus-app-container.squashfs.$_s" \
           "$TMP/repro2/fus-app-container.squashfs.$_s"
    check "two runs over the same source: identical .$_s" 0 "$?"
done
cmp -s "$TMP/repro1/fus-app-container.squashfs" "$TMP/repro2/fus-app-container.squashfs"
check "two runs over the same source: identical squashfs" 0 "$?"
# The counter-proof, without which the match above only shows that two runs
# of the same stub agree: a DIFFERENT source tree must change all three
# sidecars, which is only true if the salt really comes from the image.
env STUB_CONTENT_COPY="$TMP/repro3" "$MKOK" "$TMP/out-r3" \
    --app-dir "$APPTREE2" --source-date-epoch 1700000000 >/dev/null 2>&1
check "counter-run over a different source -> 0" 0 "$?"
for _s in verity roothash roothash.p7s; do
    cmp -s "$TMP/repro1/fus-app-container.squashfs.$_s" \
           "$TMP/repro3/fus-app-container.squashfs.$_s"
    check "a different source: different .$_s" 1 "$?"
done

echo "# --- build failures leave no fragment in --out ---"
mkdir -p "$TMP/out-7" "$TMP/out-8"
rc_is "rauc bundle fails -> 7" 7 env STUB_BUNDLE_RC=1 "$MKOK" "$TMP/out-7"
check "no fragment after exit 7" "" "$(ls -A "$TMP/out-7")"
rc_is "self-verification fails -> 8" 8 env STUB_RAUC_RC=1 "$MKOK" "$TMP/out-8"
check "no fragment after exit 8" "" "$(ls -A "$TMP/out-8")"
# The self-verification is what pins the compatible: a bundle whose manifest
# says one thing and whose rauc info says another must not be published.
mkdir -p "$TMP/out-8b"
rc_is "a drifted compatible fails self-verification -> 8" 8 \
    env STUB_COMPAT=fus-update-fsimx8mp "$MKOK" "$TMP/out-8b"
# The verify child pins compatible, version and format and NOTHING else, so
# the three fields this round actually added are checked by this tool itself.
# Each case drifts one of them in the canned rauc answer: without the check
# the bundle verifies clean, publishes, and only fails on the device.
mkdir -p "$TMP/out-w1" "$TMP/out-w2" "$TMP/out-w3" "$TMP/out-w4" "$TMP/out-w5"
env STUB_HOOKS=post-install "$MKOK" "$TMP/out-w1" > "$TMP/w1.out" 2> "$TMP/w1.err"
check "a wrong bundle hook verb -> 8" 8 "$?"
has "the refusal names the bundle hook" "install-check" "$TMP/w1.err"
check "no fragment after the bundle-hook drift" "" "$(ls -A "$TMP/out-w1")"
env STUB_HOOKS= "$MKOK" "$TMP/out-w2" > "$TMP/w2.out" 2> "$TMP/w2.err"
check "no bundle hook verb at all -> 8" 8 "$?"
has "the refusal names the consequence" "compatible" "$TMP/w2.err"
env STUB_IMAGE_HOOKS=post-install "$MKOK" "$TMP/out-w3" > "$TMP/w3.out" 2> "$TMP/w3.err"
check "a wrong image hook -> 8" 8 "$?"
has "the refusal names the image hook" "no 'install' hook" "$TMP/w3.err"
env STUB_IMAGE_NAME=some-other.squashfs "$MKOK" "$TMP/out-w4" > "$TMP/w4.out" 2> "$TMP/w4.err"
check "a wrong image filename -> 8" 8 "$?"
has "the refusal names the payload name" "fus-app-container.squashfs" "$TMP/w4.err"
# The slot class is the fourth field: an image rauc reports under rootfs
# leaves the device's appfs slot unwritten, and the payload name alone would
# still match, so nothing else in this suite would catch it.
env STUB_IMAGE_CLASS=rootfs "$MKOK" "$TMP/out-w5" > "$TMP/w5.out" 2> "$TMP/w5.err"
check "a drifted image slot class -> 8" 8 "$?"
has "the refusal names the slot class" "no 'appfs' image" "$TMP/w5.err"
check "no fragment after the slot-class drift" "" "$(ls -A "$TMP/out-w5")"
mkdir -p "$TMP/out-p1"
rc_is "verify child usage error -> 2, not 8" 2 env TMPDIR="$TMP/gone-tmp" "$MKOK" "$TMP/out-p1"
check "no fragment after the passthrough" "" "$(ls -A "$TMP/out-p1")"

echo "# --- the levers: compatible, machine, description, shape ---"
OUT2="$TMP/out2"; mkdir -p "$OUT2"
env STUB_COMPAT=fus-update-wrongboard-appfs STUB_CONTENT_COPY="$TMP/content.wrong" \
    "$MKOK" "$OUT2" --compatible fus-update-wrongboard-appfs >/dev/null 2>&1
check "wrong-compat build -> 0 (the bench lever)" 0 "$?"
has "manifest carries the override" "compatible=fus-update-wrongboard-appfs" \
    "$TMP/content.wrong/manifest.raucm"
# An override that drops the -appfs suffix still builds -- deliberately
# building a bundle the device must refuse is a legitimate bench lever -- but
# it must be loud, and the .info has to carry the mark.
OUT2B="$TMP/out2b"; mkdir -p "$OUT2B"
env STUB_COMPAT=fus-update-fsimx8mp "$MKOK" "$OUT2B" \
    --compatible fus-update-fsimx8mp > /dev/null 2> "$TMP/nosuffix.err"
check "a compatible without the suffix builds -> 0" 0 "$?"
has "the suffix warning fired" "does not end in '-appfs'" "$TMP/nosuffix.err"
has "the warning names the consequence" "device will reject" "$TMP/nosuffix.err"
has "info records the suffix warning" "compatible.suffix_warning=yes" \
    "$OUT2B/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
OUT3="$TMP/out3"; mkdir -p "$OUT3"
env STUB_COMPAT=fus-update-fsimx93-appfs STUB_CONTENT_COPY="$TMP/content.m93" \
    "$MKOK" "$OUT3" --machine fsimx93 >/dev/null 2>&1
check "another machine builds -> 0" 0 "$?"
has "the compatible follows the machine" "compatible=fus-update-fsimx93-appfs" \
    "$TMP/content.m93/manifest.raucm"
check "the artifact name follows the machine" yes \
    "$([ -f "$OUT3/ext-fus-app-bundle-fsimx93-20260902-$STAMP.raucb" ] && echo yes)"
OUT4="$TMP/out4"; mkdir -p "$OUT4"
env STUB_VERSION=1.0 "$MKOK" "$OUT4" --version 1.0 > /dev/null 2> "$TMP/shape.err"
check "non-date version builds -> 0" 0 "$?"
has "the shape warning fired" "not date-shaped" "$TMP/shape.err"
has "info records the shape warning" "version.shape_warning=yes" \
    "$OUT4/ext-fus-app-bundle-fsimx8mp-1.0-$STAMP.raucb.info"
OUT5="$TMP/out5"; mkdir -p "$OUT5"
env STUB_CONTENT_COPY="$TMP/content.desc" "$MKOK" "$OUT5" \
    --description "a different description" >/dev/null 2>&1
check "description override -> 0" 0 "$?"
has "the manifest carries it" "description=a different description" \
    "$TMP/content.desc/manifest.raucm"

echo "# --- second build repoints the symlink, keeps the first artifact ---"
"$MKOK" "$OUT" --build-stamp 20260901120001 >/dev/null 2>&1
check "second build -> 0" 0 "$?"
check "symlink repointed" "ext-fus-app-bundle-fsimx8mp-20260902-20260901120001.raucb" \
    "$(readlink "$OUT/ext-fus-app-bundle-fsimx8mp.raucb")"
check "first artifact untouched" yes \
    "$([ -f "$OUT/ext-fus-app-bundle-fsimx8mp-20260902-$STAMP.raucb" ] && echo yes)"

echo "# --- standalone: the tool set works copied away from the layer ---"
mkdir -p "$TMP/standalone" "$TMP/out-s"
cp "$DIR/fus-bundle-lib.sh" "$DIR/fus-verify-bundle.sh" "$DIR/fus-mk-app-bundle.sh" \
    "$TMP/standalone/"
cp -L "$DIR/install-check" "$TMP/standalone/install-check"
rc_is "copied set builds -> 0" 0 env PATH="$SPATH" $APPSTUB \
    "$TMP/standalone/fus-mk-app-bundle.sh" \
    --version 20260902 --out "$TMP/out-s" --app-dir "$APPTREE" \
    --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"
mkdir -p "$TMP/alone" "$TMP/out-a"
cp "$DIR/fus-mk-app-bundle.sh" "$DIR/fus-bundle-lib.sh" "$TMP/alone/"
rc_is "mk without the verify companion -> 3" 3 env PATH="$SPATH" \
    "$TMP/alone/fus-mk-app-bundle.sh" \
    --version 20260902 --out "$TMP/out-a" --app-dir "$APPTREE" \
    --app-binaries fus-demo-app --app-id fus-demo-app \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"

echo "# --- help ---"
"$MK" --help > "$TMP/help.out" 2> "$TMP/help.err"
check "--help exits 0" 0 "$?"
has "--help prints usage on stdout"     "Usage:" "$TMP/help.out"
has "--help documents the app door"     "--app-dir" "$TMP/help.out"
has "--help documents --app-binaries"   "--app-binaries" "$TMP/help.out"
has "--help documents --app-id"         "--app-id" "$TMP/help.out"
has "--help names the artifact shape"   "ext-fus-app-bundle-" "$TMP/help.out"
has "--help says pkcs11 is unsupported" "pkcs11" "$TMP/help.out"
check "--help prints nothing on stderr" "" "$(cat "$TMP/help.err")"

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
