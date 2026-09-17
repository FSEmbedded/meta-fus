#!/bin/sh
# fus-verify-bundle.test.sh -- hermetic self-test for fus-verify-bundle.sh
# (pattern: board.test.sh). rauc is fus-rauc-stub.sh in a temporary PATH --
# the single source of the canned answer block; fus-test-lib.test.sh proves
# there is only that one. Harness helpers come from fus-test-lib.sh. No
# network, no real rauc, no layer checkout needed. A stub can model the
# same wrong world as the code under test, so the REAL paths are pinned
# separately by fus-verify-bundle.integration.sh; this suite covers the
# logic around them.
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
fus_test_init
fail=0

VERIFY="$DIR/fus-verify-bundle.sh"

KEYRING="$TMP/ca.pem";           printf 'stub keyring\n' > "$KEYRING"
EMPTY_KEYRING="$TMP/empty.pem";  : > "$EMPTY_KEYRING"
BUNDLE="$TMP/bundle.raucb";      printf 'stub bundle bytes\n' > "$BUNDLE"
REFERENCE="$TMP/reference.raucb"; printf 'stub reference bytes\n' > "$REFERENCE"
# Correctly named rauc overrides, so each case dies for ITS reason and not
# at the basename rule.
mkdir -p "$TMP/notexecdir"
printf 'not executable\n' > "$TMP/notexecdir/rauc"

fus_test_install_rauc_stub "$DIR"
cp "$TMP/bin/rauc" "$TMP/bin/rauc-renamed"

echo "# --- usage and argument errors (rauc must never be invoked) ---"
LOG="$TMP/rauc.log"; : > "$LOG"
rc_is "no arguments -> 2"             2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY"
rc_is "missing --keyring -> 2"        2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" "$BUNDLE"
rc_is "unknown option -> 2"           2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --frobnicate --keyring "$KEYRING" "$BUNDLE"
rc_is "option without value -> 2"     2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring
rc_is "two bundle operands -> 2"      2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$KEYRING" "$BUNDLE" "$BUNDLE"
rc_is "bundle does not exist -> 2"    2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$KEYRING" "$TMP/nope.raucb"
rc_is "keyring does not exist -> 2"   2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$TMP/nope.pem" "$BUNDLE"
rc_is "reference does not exist -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$KEYRING" --reference "$TMP/nope-ref.raucb" "$BUNDLE"
rc_is "identity-out dir missing -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$KEYRING" --identity-out "$TMP/no-dir/id.txt" "$BUNDLE"
rc_is "floor not semver -> 2"         2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$KEYRING" --floor not-a-version "$BUNDLE"
rc_is "empty keyring file -> 4"       4 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$VERIFY" --keyring "$EMPTY_KEYRING" "$BUNDLE"
check "call errors never invoked rauc" "" "$(cat "$LOG")"
# The keyring path must not leak into any channel, not even in the error.
env PATH="$SPATH" "$VERIFY" --keyring "$TMP/secret-name.pem" "$BUNDLE" \
    > "$TMP/kp.out" 2> "$TMP/kp.err"
check "missing keyring again (message case) -> 2" 2 "$?"
lacks "exit-2 keyring message withholds the path" "secret-name" "$TMP/kp.err"
lacks "keyring path absent from stdout too"       "secret-name" "$TMP/kp.out"

echo "# --- help ---"
"$VERIFY" --help > "$TMP/help.out" 2> "$TMP/help.err"
check "--help exits 0" 0 "$?"
has   "--help prints usage on stdout" "Usage:" "$TMP/help.out"
check "--help prints nothing on stderr" "" "$(cat "$TMP/help.err")"

echo "# --- tool resolution ---"
env PATH= "$VERIFY" --keyring "$KEYRING" "$BUNDLE" > "$TMP/np.out" 2> "$TMP/np.err"
check "emptied PATH -> 3" 3 "$?"
has "the message names the binary"         "rauc"           "$TMP/np.err"
has "the message names the Debian package" "Debian package" "$TMP/np.err"
rc_is "FUS_RAUC not executable -> 3" 3 env PATH="$SPATH" FUS_RAUC="$TMP/notexecdir/rauc" "$VERIFY" --keyring "$KEYRING" "$BUNDLE"
rc_is "FUS_RAUC nonexistent -> 3"    3 env PATH="$SPATH" FUS_RAUC="$TMP/missing/rauc" "$VERIFY" --keyring "$KEYRING" "$BUNDLE"
# rauc is always invoked by PATH, never by name, so a foreign basename is
# fine HERE -- the by-name rule belongs to the helpers rauc launches itself.
rc_is "FUS_RAUC under a foreign basename -> 0" 0 env PATH="$SPATH" FUS_RAUC="$TMP/bin/rauc-renamed" "$VERIFY" --keyring "$KEYRING" "$BUNDLE"
# A relative PATH entry must not leak a relative tool path into results.
( cd "$TMP" && env PATH="bin:$PATH" "$VERIFY" --check-tools ) > "$TMP/relpath.out" 2>&1
check "check-tools over a relative PATH entry -> 0" 0 "$?"
has "the resolved path is pinned absolute" "tool.rauc.path=$TMP/bin/rauc" "$TMP/relpath.out"
env PATH="$SPATH" "$VERIFY" --check-tools > "$TMP/ct.out" 2>&1
check "--check-tools with rauc present -> 0" 0 "$?"
has "check-tools prints the path"    "tool.rauc.path=$TMP/bin/rauc"   "$TMP/ct.out"
has "check-tools prints the version" "tool.rauc.version=rauc 1.15.2"  "$TMP/ct.out"
rc_is "--check-tools without rauc -> 3" 3 env PATH= "$VERIFY" --check-tools
has "check-tools reports the window" "rauc.window=1.13..1.15.2" "$TMP/ct.out"
# The preflight enforces the window: a below-minimum rauc must not pass the
# preflight with 0 and only fall over at the first real verify -- but it
# still reports what it found before refusing.
env PATH="$SPATH" STUB_RAUC_VERSION=1.12 "$VERIFY" --check-tools > "$TMP/ctw.out" 2> "$TMP/ctw.err"
check "--check-tools under the window -> 3" 3 "$?"
has "the refused preflight still reports the version" "rauc.version=1.12" "$TMP/ctw.out"

echo "# --- the measured rauc version window ---"
env PATH="$SPATH" STUB_RAUC_VERSION=1.12 "$VERIFY" --keyring "$KEYRING" "$BUNDLE" \
    > "$TMP/vw.out" 2> "$TMP/vw.err"
check "rauc below the window -> 3" 3 "$?"
has "the refusal says unmeasured, not broken" "unmeasured, not known-broken" "$TMP/vw.err"
has "the refusal names the override"          "FUS_RAUC_MIN"                 "$TMP/vw.err"
env PATH="$SPATH" STUB_RAUC_VERSION=1.16 "$VERIFY" --keyring "$KEYRING" "$BUNDLE" \
    > "$TMP/vn.out" 2> "$TMP/vn.err"
check "rauc above the tested window -> 0 (warn only)" 0 "$?"
has "the newer version warns"          "newer than"  "$TMP/vn.err"
has "verification still runs to pass"  "result=pass" "$TMP/vn.out"
rc_is "window override is honoured -> 0" 0 env PATH="$SPATH" STUB_RAUC_VERSION=1.12 FUS_RAUC_MIN=1.12 "$VERIFY" --keyring "$KEYRING" "$BUNDLE"
# An undeterminable version cannot be compared: the gate warns and steps
# aside instead of blocking -- the parser's field assertion is the guard
# that still holds then.
env PATH="$SPATH" STUB_RAUC_VERSION=devbuild "$VERIFY" --keyring "$KEYRING" "$BUNDLE" \
    > "$TMP/vu.out" 2> "$TMP/vu.err"
check "undeterminable rauc version -> 0 (warn only)" 0 "$?"
has "the unchecked window warns" "cannot determine" "$TMP/vu.err"

echo "# --- parser field assertion (drift in a future rauc) ---"
env PATH="$SPATH" STUB_OMIT=RAUC_MF_BUILD "$VERIFY" --keyring "$KEYRING" "$BUNDLE" \
    > "$TMP/om.out" 2> "$TMP/om.err"
check "missing scalar in rauc output -> 8" 8 "$?"
has "the missing field is named" "RAUC_MF_BUILD" "$TMP/om.err"
# The same rule per image index: a renamed DIGEST or SIZE line would make
# the reference diff compare empty against empty and pass.
env PATH="$SPATH" STUB_OMIT=RAUC_IMAGE_DIGEST_0 "$VERIFY" --keyring "$KEYRING" "$BUNDLE" \
    > "$TMP/om2.out" 2> "$TMP/om2.err"
check "missing image digest line -> 8" 8 "$?"
has "the missing image field is named with its index" "RAUC_IMAGE_DIGEST_0" "$TMP/om2.err"
rc_is "missing image size line -> 8" 8 env PATH="$SPATH" STUB_OMIT=RAUC_IMAGE_SIZE_0 "$VERIFY" --keyring "$KEYRING" "$BUNDLE"

echo "# --- version shape (warn, never reject) ---"
env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --floor 1.0 "$BUNDLE" \
    > "$TMP/sh1.out" 2> "$TMP/sh1.err"
check "non-date floor still verifies -> 0" 0 "$?"
has "the odd shape warns"           "not date-shaped" "$TMP/sh1.err"
has "verification is unaffected"    "result=pass"     "$TMP/sh1.out"
env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --floor 20260901 "$BUNDLE" \
    > "$TMP/sh2.out" 2> "$TMP/sh2.err"
check "date-shaped floor -> 0" 0 "$?"
lacks "no warning for a date-shaped floor" "not date-shaped" "$TMP/sh2.err"
env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --expect-version 1.0 "$BUNDLE" \
    > /dev/null 2> "$TMP/sh3.err"
check "non-date expect-version -> 8 (mismatch)" 8 "$?"
has "expect-version also warns on shape" "not date-shaped" "$TMP/sh3.err"

echo "# --- verification (happy path, always under the generated conf) ---"
# Positive control for the empty-log assertion above: a run that reaches rauc
# must land in the log, or "never invoked" could pass with a broken log.
LOG2="$TMP/rauc-invoked.log"; : > "$LOG2"
env PATH="$SPATH" STUB_RAUC_LOG="$LOG2" STUB_CONF_COPY="$TMP/conf.copy" \
    "$VERIFY" --keyring "$KEYRING" "$BUNDLE" > "$TMP/ok.out" 2> "$TMP/ok.err"
check "verify -> 0" 0 "$?"
has "the stub log records real invocations" "$BUNDLE" "$TMP/rauc-invoked.log"
has "rauc runs under a configuration"       "--conf"  "$TMP/rauc-invoked.log"
has "states the verification ran"  "verify=pass"      "$TMP/ok.out"
has "states the enforced purpose"  "purpose=codesign" "$TMP/ok.out"
lacks "no configuration-free stage suggested (chain)"  "chain="  "$TMP/ok.out"
lacks "no configuration-free stage suggested (parity)" "parity=" "$TMP/ok.out"
has "reports the compatible"     "compatible=fus-update-fsimx8mp" "$TMP/ok.out"
has "reports the version"        "version=20260902" "$TMP/ok.out"
has "reports the format"         "format=verity"    "$TMP/ok.out"
has "images are keyed by class"  "image.rootfs.sha256=" "$TMP/ok.out"
has "reports the image count"    "image.count=1"    "$TMP/ok.out"
has "reports the verdict"        "result=pass"      "$TMP/ok.out"
check "diagnosis channel stays empty on success" "" "$(cat "$TMP/ok.err")"
# The generated configuration itself: the four mandatory keys plus the
# measured-safe signing-time rule.
has "conf carries the system section"  "[system]"       "$TMP/conf.copy"
has "conf carries a compatible"        "compatible="    "$TMP/conf.copy"
has "conf carries the bootloader (required to load)" "bootloader=uboot" "$TMP/conf.copy"
has "conf carries the keyring path"    "path=$KEYRING"  "$TMP/conf.copy"
has "conf carries check-purpose"       "check-purpose=codesign"       "$TMP/conf.copy"
has "conf carries the signing time"    "use-bundle-signing-time=true" "$TMP/conf.copy"

echo "# --- verification failure is not swallowed ---"
# The stub prints a COMPLETE, parseable info block on stdout and exits 1: an
# implementation that piped rauc's output into its parser would read the
# fields, lose the exit status and report a pass. The failure must win.
mkdir -p "$TMP/wtmp"
env PATH="$SPATH" TMPDIR="$TMP/wtmp" STUB_RAUC_RC=1 "$VERIFY" \
    --keyring "$KEYRING" "$BUNDLE" > "$TMP/f8.out" 2> "$TMP/f8.err"
check "rauc failure -> 8, despite readable output" 8 "$?"
lacks "no result=pass on a failure" "result=pass" "$TMP/f8.out"
lacks "no verify=pass on a failure" "verify=pass" "$TMP/f8.out"
has "rauc's own diagnosis is passed through" "stub-rauc: verification rejected" "$TMP/f8.err"
# The rc=8 above already proves the cleanup trap did not overwrite the exit
# code; the empty directory proves the trap actually ran -- and the case
# below proves TMPDIR is honoured at all, so "empty" cannot pass vacuously.
check "cleanup trap ran and kept the exit code" "" "$(ls -A "$TMP/wtmp")"
env PATH="$SPATH" TMPDIR="$TMP/wtmp" "$VERIFY" --keyring "$KEYRING" "$BUNDLE" >/dev/null 2>&1
check "success leaves no work directory behind" "" "$(ls -A "$TMP/wtmp")"
rc_is "TMPDIR is honoured (missing parent -> 2)" 2 env PATH="$SPATH" TMPDIR="$TMP/no-such-tmp" "$VERIFY" --keyring "$KEYRING" "$BUNDLE"

echo "# --- field expectations ---"
rc_is "expect-compatible match -> 0"    0 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --expect-compatible fus-update-fsimx8mp "$BUNDLE"
rc_is "expect-compatible mismatch -> 8" 8 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --expect-compatible fus-update-other "$BUNDLE"
rc_is "expect-version mismatch -> 8"    8 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --expect-version 99999999 "$BUNDLE"
rc_is "expect-format mismatch -> 8"     8 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --expect-format plain "$BUNDLE"

echo "# --- version floor (policy code 10, never 8) ---"
rc_is "floor equal -> 0 (device accepts equality)" 0 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --floor 20260902 "$BUNDLE"
rc_is "floor above bundle -> 10"       10 env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --floor 20260903 "$BUNDLE"
rc_is "numeric, not lexical: 1.2.3 < 1.10.0 -> 10" 10 env PATH="$SPATH" STUB_VERSION=1.2.3 "$VERIFY" --keyring "$KEYRING" --floor 1.10.0 "$BUNDLE"
rc_is "1.10.0 above floor 1.9.9 -> 0"   0 env PATH="$SPATH" STUB_VERSION=1.10.0 "$VERIFY" --keyring "$KEYRING" --floor 1.9.9 "$BUNDLE"
rc_is "pre-release below its release -> 10" 10 env PATH="$SPATH" STUB_VERSION=1.2.3-rc.1 "$VERIFY" --keyring "$KEYRING" --floor 1.2.3 "$BUNDLE"
rc_is "release above pre-release floor -> 0" 0 env PATH="$SPATH" STUB_VERSION=1.2.3 "$VERIFY" --keyring "$KEYRING" --floor 1.2.3-rc.1 "$BUNDLE"
rc_is "version-less bundle with a floor -> 10" 10 env PATH="$SPATH" STUB_VERSION= "$VERIFY" --keyring "$KEYRING" --floor 20260902 "$BUNDLE"

echo "# --- reference diff ---"
LOG3="$TMP/rauc-ref.log"; : > "$LOG3"
env PATH="$SPATH" STUB_RAUC_LOG="$LOG3" STUB_REF_BUILD=20260830000000 "$VERIFY" \
    --keyring "$KEYRING" --reference "$REFERENCE" "$BUNDLE" >/dev/null 2>&1
check "reference equal except build -> 0" 0 "$?"
check "reference run: one version probe, two info calls" 3 "$(grep -c . "$LOG3")"
check "both info calls run under a configuration" 2 "$(grep -cF -- '--conf' "$LOG3")"
env PATH="$SPATH" STUB_REF_VERSION=20260901 "$VERIFY" \
    --keyring "$KEYRING" --reference "$REFERENCE" "$BUNDLE" > "$TMP/rd.out" 2> "$TMP/rd.err"
check "reference version drift -> 8" 8 "$?"
has   "the differing field is named"  "version"         "$TMP/rd.err"
lacks "no reference=match on drift"   "reference=match" "$TMP/rd.out"
# An image that lost its hook is materially different -- on the device the
# read-back check is gone with it -- so hook drift must not diff clean.
env PATH="$SPATH" STUB_REF_IMAGE_HOOKS=install "$VERIFY" \
    --keyring "$KEYRING" --reference "$REFERENCE" "$BUNDLE" > "$TMP/hd.out" 2> "$TMP/hd.err"
check "image-hook drift -> 8" 8 "$?"
has "the drifted hook field is named" "image.rootfs.hooks" "$TMP/hd.err"

echo "# --- identity out ---"
env PATH="$SPATH" "$VERIFY" --keyring "$KEYRING" --identity-out "$TMP/id.txt" "$BUNDLE" \
    > "$TMP/io.out" 2>&1
check "identity-out run -> 0" 0 "$?"
has "identity file holds the version" "version=20260902"     "$TMP/id.txt"
has "identity file holds the digest"  "image.rootfs.sha256=" "$TMP/id.txt"
has "stdout names the identity file"  "identity_out=$TMP/id.txt" "$TMP/io.out"

# The image count bounds the parse loop in one direction only; an entry
# BEYOND the count would vanish from both sides of a reference diff and
# pass uncompared. Red without the surplus guard.
{
    printf "RAUC_MF_COMPATIBLE='c'\nRAUC_MF_VERSION='1'\nRAUC_MF_BUILD='1'\n"
    printf "RAUC_MF_FORMAT='verity'\nRAUC_MF_HOOKS=''\nRAUC_MF_IMAGES='1'\n"
    for _i in 0 1; do
        printf "RAUC_IMAGE_NAME_%s='p%s'\nRAUC_IMAGE_CLASS_%s='c%s'\n" "$_i" "$_i" "$_i" "$_i"
        printf "RAUC_IMAGE_DIGEST_%s='d'\nRAUC_IMAGE_SIZE_%s='1'\nRAUC_IMAGE_HOOKS_%s=''\n" "$_i" "$_i" "$_i"
    done
} > "$TMP/surplus.shell"
( . "$DIR/fus-bundle-lib.sh" && fus_identity_from_shell "$TMP/surplus.shell" ) \
    > /dev/null 2> "$TMP/surplus.err"
check "image entries beyond the count -> 8" 8 "$?"
has "the surplus is named" "image name lines" "$TMP/surplus.err"
# The same with a GAP: count 1, entries at 0 and 2 -- a single-point probe
# at index 1 would see nothing and let the extra image vanish uncompared.
sed '/_1=/d' "$TMP/surplus.shell" > "$TMP/gap.shell.tmp"
sed 's/_1=/_2=/' "$TMP/surplus.shell" | grep '_2=' >> "$TMP/gap.shell.tmp" || true
mv "$TMP/gap.shell.tmp" "$TMP/gap.shell"
( . "$DIR/fus-bundle-lib.sh" && fus_identity_from_shell "$TMP/gap.shell" ) \
    > /dev/null 2> "$TMP/gap.err"
check "a gapped surplus entry -> 8" 8 "$?"
# A stale triple-form caller (an older tool next to a newer library in a
# mixed copy) must fail loudly, not silently skip the trailing tool.
( . "$DIR/fus-bundle-lib.sh" && fus_tools_report rauc FUS_RAUC rauc mksquashfs FUS_MKSQUASHFS squashfs-tools ) \
    > /dev/null 2> "$TMP/arity.err"
check "a triple-form report call -> 2" 2 "$?"

echo "# --- more than one image (the count-driven loop at n=2) ---"
env PATH="$SPATH" STUB_IMAGES=2 "$VERIFY" --keyring "$KEYRING" "$BUNDLE" > "$TMP/two.out" 2>&1
check "a two-image bundle verifies -> 0" 0 "$?"
has "both classes appear"  "image.boot.filename=boot.vfat" "$TMP/two.out"
has "the count follows"    "image.count=2" "$TMP/two.out"
# The presence rule holds per index on multi-image bundles too (a hookless
# image is measured to emit the line EMPTY, never to omit it).
env PATH="$SPATH" STUB_IMAGES=2 STUB_OMIT=RAUC_IMAGE_HOOKS_1 "$VERIFY" \
    --keyring "$KEYRING" "$BUNDLE" > /dev/null 2> "$TMP/twoh.err"
check "a missing second-image hooks line -> 8" 8 "$?"
has "the field is named with its index" "RAUC_IMAGE_HOOKS_1" "$TMP/twoh.err"

echo "# --- standalone: the tool set works copied away from the layer ---"
mkdir -p "$TMP/standalone"
cp "$DIR/fus-bundle-lib.sh" "$DIR/fus-verify-bundle.sh" "$TMP/standalone/"
rc_is "copied set verifies -> 0" 0 env PATH="$SPATH" "$TMP/standalone/fus-verify-bundle.sh" --keyring "$KEYRING" "$BUNDLE"
mkdir -p "$TMP/alone"
cp "$DIR/fus-verify-bundle.sh" "$TMP/alone/"
rc_is "verify without its library -> 3" 3 env PATH="$SPATH" "$TMP/alone/fus-verify-bundle.sh" --keyring "$KEYRING" "$BUNDLE"

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
