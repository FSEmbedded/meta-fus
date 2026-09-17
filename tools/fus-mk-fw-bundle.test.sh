#!/bin/sh
# fus-mk-fw-bundle.test.sh -- hermetic self-test for fus-mk-fw-bundle.sh
# (pattern: board.test.sh). rauc is fus-rauc-stub.sh in a temporary PATH --
# the single source of the canned answer block; fus-test-lib.test.sh proves
# there is only that one. Harness helpers come from fus-test-lib.sh, and so
# does the trivial mksquashfs stub. No network, no real tools, no layer
# checkout needed. The real accept path is pinned separately by
# fus-mk-fw-bundle.integration.sh.
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
fus_test_init
fail=0

MK="$DIR/fus-mk-fw-bundle.sh"

KEYRING="$TMP/ca.pem";  printf 'stub keyring\n' > "$KEYRING"
CERT="$TMP/sign.cert";  printf 'stub cert\n' > "$CERT"
KEY="$TMP/sign.key";    printf 'stub key\n' > "$KEY"
EMPTY_KEYRING="$TMP/empty.pem"; : > "$EMPTY_KEYRING"
mkdir -p "$TMP/src"
PAYLOAD="$TMP/src/fusys-image-eval-fsimx8mp.squashfs"
printf 'hsqs stub squashfs payload bytes\n' > "$PAYLOAD"
# Decoys in the source directory: the tool must never look at them.
printf 'hsqs decoy\n' > "$TMP/src/fusys-image-other.squashfs"
printf 'decoy\n' > "$TMP/src/fus-fw-bundle-other.raucb"
STAMP=20260901120000

fus_test_install_rauc_stub "$DIR"
fus_test_install_mksquashfs_stub

# A valid build, as a SCRIPT (not a function) so cases can prefix it with
# `env STUB_...=...`. Later flags override the baked-in ones.
MKOK="$TMP/mk-ok"
cat > "$MKOK" <<EOF
#!/bin/sh
_o=\$1; shift
exec env PATH="$SPATH" "$MK" --version 20260902 --out "\$_o" \\
    --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY" \\
    --keyring "$KEYRING" --build-stamp "$STAMP" "\$@"
EOF
chmod +x "$MKOK"

echo "# --- usage and argument errors (rauc must never be invoked) ---"
LOG="$TMP/rauc.log"; : > "$LOG"
mkdir -p "$TMP/out-u"
rc_is "no source -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --version 20260902 --out "$TMP/out-u" --cert "$CERT" --key "$KEY" --keyring "$KEYRING"
env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" --version 20260902 --out "$TMP/out-u" \
    --rootfs-dir "$TMP/src" --rootfs-image "$PAYLOAD" \
    --payload-name fusys-image-eval-fsimx8mp.squashfs \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    > "$TMP/rd.out" 2> "$TMP/rd.err"
check "both sources -> 2 (exactly one source)" 2 "$?"
has "the refusal names the image door" "--rootfs-image" "$TMP/rd.err"
has "the refusal names the directory door" "--rootfs-dir" "$TMP/rd.err"
env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" --version 20260902 --out "$TMP/out-u" \
    --rootfs-dir "$TMP/src" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    > "$TMP/pn.out" 2> "$TMP/pn.err"
check "--rootfs-dir without --payload-name -> 2" 2 "$?"
has "the refusal names --payload-name" "payload-name" "$TMP/pn.err"
rc_is "bypass flag with --rootfs-image -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" \
    "$TMP/out-u" --i-know-ownership-is-wrong
# The env twin refuses exactly like the flag: an ambient variable claiming an
# ownership property this door never touches is a lie, not a convenience.
rc_is "env-twin bypass with --rootfs-image -> 2" 2 \
    env STUB_RAUC_LOG="$LOG" FUS_I_KNOW_OWNERSHIP_IS_WRONG=1 "$MKOK" "$TMP/out-u"
rc_is "missing --version -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --out "$TMP/out-u" --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY" --keyring "$KEYRING"
rc_is "version not semver -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" --version not.a-version-
rc_is "--out does not exist -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --version 20260902 --out "$TMP/no-out" --rootfs-image "$PAYLOAD" \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING"
rc_is "missing --keyring -> 2" 2 env PATH="$SPATH" STUB_RAUC_LOG="$LOG" "$MK" \
    --version 20260902 --out "$TMP/out-u" --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY"
rc_is "unknown option -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" --frobnicate
rc_is "floor not semver -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-u" --floor not-a-version
mkdir -p "$TMP/out-e"
: > "$TMP/out-e/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb"
rc_is "artifact already exists -> 2" 2 env STUB_RAUC_LOG="$LOG" "$MKOK" "$TMP/out-e"
check "call errors never invoked rauc" "" "$(cat "$LOG")"

echo "# --- tool resolution and the window ---"
# --build-stamp is baked in here: the default would run `date` before the
# tools are resolved and mask the exit 3 under an emptied PATH.
rc_is "emptied PATH -> 3" 3 env PATH= "$MK" --version 20260902 --out "$TMP/out-u" \
    --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    --build-stamp "$STAMP"
mkdir -p "$TMP/bin-nomksq"
cp "$TMP/bin/rauc" "$TMP/bin-nomksq/"
env PATH="$TMP/bin-nomksq" "$MK" --version 20260902 --out "$TMP/out-u" \
    --rootfs-image "$PAYLOAD" --cert "$CERT" --key "$KEY" --keyring "$KEYRING" \
    --build-stamp "$STAMP" > "$TMP/nm.out" 2> "$TMP/nm.err"
check "missing mksquashfs -> 3" 3 "$?"
has "the message names the Debian package" "squashfs-tools" "$TMP/nm.err"
rc_is "rauc below the window -> 3" 3 env STUB_RAUC_VERSION=1.12 "$MKOK" "$TMP/out-u"
env PATH="$SPATH" "$MK" --check-tools > "$TMP/ct.out" 2>&1
check "--check-tools -> 0" 0 "$?"
has "check-tools reports rauc"       "tool.rauc.version="       "$TMP/ct.out"
has "check-tools reports mksquashfs" "tool.mksquashfs.version=" "$TMP/ct.out"
has "check-tools reports the window" "rauc.window=1.13..1.15.2" "$TMP/ct.out"
rc_is "--check-tools under the window -> 3" 3 env PATH="$SPATH" STUB_RAUC_VERSION=1.12 "$MK" --check-tools
rc_is "--require-rauc mismatch -> 3" 3 "$MKOK" "$TMP/out-u" --require-rauc 1.13
"$MKOK" "$TMP/out-u" --expect-rauc 1.13 --dry-run > /dev/null 2> "$TMP/er.err"
check "--expect-rauc mismatch only warns -> 0" 0 "$?"
has "expect-rauc warns" "expected '1.13'" "$TMP/er.err"

echo "# --- signing material (4) ---"
rc_is "no cert and no key -> 4" 4 env PATH="$SPATH" "$MK" --version 20260902 \
    --out "$TMP/out-u" --rootfs-image "$PAYLOAD" --keyring "$KEYRING" --build-stamp "$STAMP"
env PATH="$SPATH" "$MK" --version 20260902 --out "$TMP/out-u" \
    --rootfs-image "$PAYLOAD" --cert "$TMP/secret-missing.pem" --key "$KEY" \
    --keyring "$KEYRING" --build-stamp "$STAMP" > "$TMP/c4.out" 2> "$TMP/c4.err"
check "unreadable cert -> 4" 4 "$?"
lacks "the cert message withholds the path" "secret-missing" "$TMP/c4.err"
rc_is "empty keyring file -> 4" 4 "$MKOK" "$TMP/out-u" --keyring "$EMPTY_KEYRING"

echo "# --- source, hook (5) and the size guard (6) ---"
rc_is "payload does not exist -> 5" 5 "$MKOK" "$TMP/out-u" --rootfs-image "$TMP/nope.squashfs"
printf 'this is not a squashfs\n' > "$TMP/not-squashfs"
rc_is "payload with wrong magic -> 5" 5 "$MKOK" "$TMP/out-u" --rootfs-image "$TMP/not-squashfs"
rc_is "missing hook -> 5" 5 "$MKOK" "$TMP/out-u" --hook "$TMP/no-hook"
rc_is "payload over the slot size -> 6" 6 env FUS_SIZE_ROOT_MIB=0 "$MKOK" "$TMP/out-u"
# An unusable input (5) is reported ahead of a policy verdict (6): the
# caller has to fix the hook either way, and the slot number is only
# meaningful once the rest of the build could actually run.
rc_is "unusable hook outranks the slot guard -> 5" 5 env FUS_SIZE_ROOT_MIB=0 \
    "$MKOK" "$TMP/out-u" --hook "$TMP/no-hook"
# A deploy-style symlink: the target NAME is one byte long, the FILE holds
# ten. A guard that does not dereference would compare the wrong number.
printf '0123456789' > "$TMP/sizelink-f"
ln -s sizelink-f "$TMP/sizelink"
( . "$DIR/fus-bundle-lib.sh" && fus_check_slot_fit "$TMP/sizelink" 0 )
check "the slot guard dereferences symlinks" 6 "$?"
# A stat failure on a file the directory door just packed is the packer's
# fault, not a usage error: the call site passes 7, and the guard's default
# (2, for the image door, where the source was already validated readable)
# must not silently override it.
( . "$DIR/fus-bundle-lib.sh" && fus_check_slot_fit "$TMP/no-such-payload" 1 7 )
check "an unstattable directory-door payload -> 7, not the usage default" 7 "$?"

echo "# --- floor (10) ---"
rc_is "floor above the version -> 10" 10 "$MKOK" "$TMP/out-u" --floor 20260903
rc_is "floor equal -> passes preflight (dry run)" 0 "$MKOK" "$TMP/out-u" --floor 20260902 --dry-run

echo "# --- the directory door: uid guard, bypass, reproducible packing ---"
ROOTTREE="$TMP/rootfs-tree"
mkdir -p "$ROOTTREE/etc" "$ROOTTREE/usr/bin"
printf 'stub-host\n' > "$ROOTTREE/etc/hostname"
printf 'stub-app\n' > "$ROOTTREE/usr/bin/app"
EMPTYTREE="$TMP/empty-tree"; mkdir -p "$EMPTYTREE"
# The tool reads the uid with `id`, so BOTH verdicts are stubbed through
# PATH and neither depends on who runs the suite. Without this the whole
# block inverts inside a container that builds as root -- measured: nine
# assertions flip, starting with the 11 that is the point of the guard.
NONROOT_UID=1000
mkdir -p "$TMP/nonrootbin" "$TMP/rootbin"
printf '#!/bin/sh\necho %s\n' "$NONROOT_UID" > "$TMP/nonrootbin/id"
printf '#!/bin/sh\necho 0\n' > "$TMP/rootbin/id"
chmod +x "$TMP/nonrootbin/id" "$TMP/rootbin/id"
DPATH="$TMP/nonrootbin:$SPATH"
# A valid directory-door build, same pattern as MKOK; later flags override.
MKDOK="$TMP/mk-dir-ok"
cat > "$MKDOK" <<EOF
#!/bin/sh
_o=\$1; shift
exec env PATH="$DPATH" "$MK" --version 20260902 --out "\$_o" \\
    --rootfs-dir "$ROOTTREE" --payload-name fusys-image-eval-fsimx8mp.squashfs \\
    --cert "$CERT" --key "$KEY" \\
    --keyring "$KEYRING" --build-stamp "$STAMP" "\$@"
EOF
chmod +x "$MKDOK"
# The uid guard must fire BEFORE any mksquashfs invocation and before the
# source directory is touched.
MLOG="$TMP/mksq.log"; : > "$MLOG"
mkdir -p "$TMP/out-d11"
env STUB_MKSQ_LOG="$MLOG" "$MKDOK" "$TMP/out-d11" > "$TMP/d11.out" 2> "$TMP/d11.err"
check "non-root without the bypass -> 11" 11 "$?"
has "the refusal names the cause" "uid/gid of the packing process" "$TMP/d11.err"
has "the refusal names the way out" "--i-know-ownership-is-wrong" "$TMP/d11.err"
check "the guard fired before any mksquashfs call" "" "$(cat "$MLOG")"
check "no fragment after exit 11" "" "$(ls -A "$TMP/out-d11")"
# The guard outranks every source check: non-root and no bypass must answer
# 11 even when the directory does not exist either, not fall through to the
# source-error code (5) a source check further down would otherwise assign.
mkdir -p "$TMP/out-d11b"
rc_is "non-root, no bypass, missing source dir -> 11, not 5" 11 \
    "$MKDOK" "$TMP/out-d11b" --rootfs-dir "$TMP/no-such-tree"
# -all-root in the firmware argument list defeats the guard above rather than
# tripping it: the pack would discard the ownership even as real root, and the
# .info would still record a clean build. It has to be refused BEFORE the uid
# question, and before mksquashfs is ever called.
: > "$MLOG"
mkdir -p "$TMP/out-dar"
env STUB_MKSQ_LOG="$MLOG" FUS_MKSQUASHFS_ARGS="-noappend -all-root" \
    "$MKDOK" "$TMP/out-dar" --i-know-ownership-is-wrong \
    > "$TMP/dar.out" 2> "$TMP/dar.err"
check "-all-root in FUS_MKSQUASHFS_ARGS -> 11" 11 "$?"
has "the refusal names the variable" "FUS_MKSQUASHFS_ARGS" "$TMP/dar.err"
has "the refusal names the flag"     "-all-root"           "$TMP/dar.err"
check "refused before any mksquashfs call" "" "$(cat "$MLOG")"
check "no fragment after the -all-root refusal" "" "$(ls -A "$TMP/out-dar")"
# Word-wise, not substring: a flag that merely starts the same is not it.
mkdir -p "$TMP/out-dar2"
rc_is "-all-rootish is not -all-root (build proceeds) -> 0" 0 \
    env FUS_MKSQUASHFS_ARGS="-noappend -all-rootish" \
    "$MKDOK" "$TMP/out-dar2" --i-know-ownership-is-wrong
# The image door packs nothing and makes no ownership claim, so the same
# variable must not refuse it -- a guard that fires where it cannot matter
# would just teach people to unset it.
mkdir -p "$TMP/out-dar3"
rc_is "the image door ignores -all-root in the argument list -> 0" 0 \
    env FUS_MKSQUASHFS_ARGS="-noappend -all-root" "$MKOK" "$TMP/out-dar3"
# The bypass must be loud on stderr AND leave a mark in the .info.
mkdir -p "$TMP/out-db"
env STUB_CONTENT_LIST="$TMP/dcontent.list" "$MKDOK" "$TMP/out-db" \
    --i-know-ownership-is-wrong > "$TMP/db.out" 2> "$TMP/db.err"
check "bypassed non-root build -> 0" 0 "$?"
has "the bypass warns on stderr" "WARNING" "$TMP/db.err"
has "the warning names the uid" "uid $NONROOT_UID" "$TMP/db.err"
DINFO="$TMP/out-db/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
has "info records the bypass" "ownership.guard_bypassed=yes" "$DINFO"
has "info records the packing uid" "ownership.build_uid=$NONROOT_UID" "$DINFO"
has "info records the packing args" "const.FUS_MKSQUASHFS_ARGS=-noappend -comp zstd" "$DINFO"
# The directory door's epoch default is the SOURCE DIRECTORY's mtime, the
# same rule the image recipe applies to the same tree.
has "info records the source-dir epoch default" \
    "source_date_epoch=$(stat -Lc %Y "$ROOTTREE")" "$DINFO"
check "content holds exactly three entries" 3 "$(grep -c . "$TMP/dcontent.list")"
lacks "directory-door info holds no host paths" "$TMP" "$DINFO"
has "content: the packed payload" "fusys-image-eval-fsimx8mp.squashfs" "$TMP/dcontent.list"
has "content: the hook"     "install-check"  "$TMP/dcontent.list"
has "content: the manifest" "manifest.raucm" "$TMP/dcontent.list"
# The env twin opens the same bypass -- but only on an explicit yes. A CI
# exporting =0 to mean "off" must hit the guard, not sail past it, and a
# value that is neither is a usage error rather than a silent no.
# A fresh --out per case: these three share a build stamp, and a second run
# into the same directory would exit 2 on the existing artifact -- which
# would make the =0 case fail for the wrong reason and the bad-value case
# PASS for the wrong reason.
mkdir -p "$TMP/out-de1" "$TMP/out-de2" "$TMP/out-de3"
rc_is "env-twin bypass -> 0" 0 env FUS_I_KNOW_OWNERSHIP_IS_WRONG=1 \
    "$MKDOK" "$TMP/out-de1"
rc_is "env-twin =0 does NOT bypass -> 11" 11 env FUS_I_KNOW_OWNERSHIP_IS_WRONG=0 \
    "$MKDOK" "$TMP/out-de2"
env FUS_I_KNOW_OWNERSHIP_IS_WRONG=maybe "$MKDOK" "$TMP/out-de3" \
    > "$TMP/etw.out" 2> "$TMP/etw.err"
check "env-twin with an unusable value -> 2" 2 "$?"
has "the refusal names the variable" "FUS_I_KNOW_OWNERSHIP_IS_WRONG" "$TMP/etw.err"
# As root the guard passes without any bypass. Root is stubbed the same way
# as non-root above -- through PATH, not through an injectable uid variable
# inside the tool, which would be a production seam that exists only for
# the test. What stays unproven either way is that a REAL root run stamps
# ownership.build_uid=0: only the integration leg can show that, and it
# SKIPs unprivileged (see fus-mk-fw-bundle.integration.sh).
mkdir -p "$TMP/out-dr"
env PATH="$TMP/rootbin:$SPATH" "$MK" --version 20260902 --out "$TMP/out-dr" \
    --rootfs-dir "$ROOTTREE" --payload-name fusys-image-eval-fsimx8mp.squashfs \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP" \
    > "$TMP/dr.out" 2> "$TMP/dr.err"
check "root without the bypass -> 0" 0 "$?"
lacks "no ownership warning as root" "ownership" "$TMP/dr.err"
has "info records the guard as not bypassed" "ownership.guard_bypassed=no" \
    "$TMP/out-dr/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
# Reproducibility: two runs over the same tree with a fixed epoch must
# produce byte-identical squashfs payloads (the stub derives its output
# from source content + epoch, never from the clock).
mkdir -p "$TMP/out-r1" "$TMP/out-r2"
env STUB_CONTENT_COPY="$TMP/repro1" "$MKDOK" "$TMP/out-r1" \
    --i-know-ownership-is-wrong --source-date-epoch 1700000000 >/dev/null 2>&1
check "reproducibility run 1 -> 0" 0 "$?"
env STUB_CONTENT_COPY="$TMP/repro2" "$MKDOK" "$TMP/out-r2" \
    --i-know-ownership-is-wrong --source-date-epoch 1700000000 >/dev/null 2>&1
check "reproducibility run 2 -> 0" 0 "$?"
cmp -s "$TMP/repro1/fusys-image-eval-fsimx8mp.squashfs" \
    "$TMP/repro2/fusys-image-eval-fsimx8mp.squashfs"
check "fixed epoch -> byte-identical squashfs" 0 "$?"
# The counter-proof, without which the match above only shows that two runs
# of the same stub agree: a DIFFERENT epoch must change the payload, which
# is only true if the epoch actually reaches the packer.
mkdir -p "$TMP/out-r3"
env STUB_CONTENT_COPY="$TMP/repro3" "$MKDOK" "$TMP/out-r3" \
    --i-know-ownership-is-wrong --source-date-epoch 1700000001 >/dev/null 2>&1
check "reproducibility counter-run -> 0" 0 "$?"
cmp -s "$TMP/repro1/fusys-image-eval-fsimx8mp.squashfs" \
    "$TMP/repro3/fusys-image-eval-fsimx8mp.squashfs"
check "a different epoch -> a different squashfs" 1 "$?"
# And the layer's packing settings must reach the packer, not just any ones.
MLOG3="$TMP/mksq-args.log"; : > "$MLOG3"
mkdir -p "$TMP/out-r4"
env STUB_MKSQ_LOG="$MLOG3" "$MKDOK" "$TMP/out-r4" \
    --i-know-ownership-is-wrong >/dev/null 2>&1
has "the pack carries the layer's mksquashfs args" "-comp zstd" "$MLOG3"
has "the pack refuses to append" "-noappend" "$MLOG3"
# Directory-door source errors and pack failures.
rc_is "empty source directory -> 5" 5 "$MKDOK" "$TMP/out-u" \
    --i-know-ownership-is-wrong --rootfs-dir "$EMPTYTREE"
rc_is "source directory does not exist -> 5" 5 "$MKDOK" "$TMP/out-u" \
    --i-know-ownership-is-wrong --rootfs-dir "$TMP/no-such-tree"
mkdir -p "$TMP/out-d7"
rc_is "mksquashfs fails -> 7" 7 env STUB_MKSQ_RC=1 "$MKDOK" "$TMP/out-d7" \
    --i-know-ownership-is-wrong
check "no fragment after the pack failure" "" "$(ls -A "$TMP/out-d7")"
rc_is "mksquashfs writes no output -> 7" 7 env STUB_MKSQ_EMPTY=1 \
    "$MKDOK" "$TMP/out-d7" --i-know-ownership-is-wrong
rc_is "packed payload over the slot size -> 6" 6 env FUS_SIZE_ROOT_MIB=0 \
    "$MKDOK" "$TMP/out-d7" --i-know-ownership-is-wrong
# Dry run in directory mode: preflights (guard included) run, nothing packs.
mkdir -p "$TMP/out-dd"
MLOG2="$TMP/mksq-dry.log"; : > "$MLOG2"
env STUB_MKSQ_LOG="$MLOG2" "$MKDOK" "$TMP/out-dd" \
    --i-know-ownership-is-wrong --dry-run > "$TMP/dd.out" 2>&1
check "directory-door dry run -> 0" 0 "$?"
has "dry run prints the manifest" "[update]" "$TMP/dd.out"
check "dry run packs nothing" "" "$(cat "$MLOG2")"
check "dry run builds nothing" "" "$(ls -A "$TMP/out-dd")"
rc_is "dry run still enforces the guard -> 11" 11 "$MKDOK" "$TMP/out-dd" --dry-run
# The guard reads the uid with `id`, a PATH lookup: under an emptied PATH
# the documented tool error (3) must still win, never a false non-root 11
# derived from an unresolvable uid.
rc_is "emptied PATH in directory mode -> 3, not 11" 3 env PATH= "$MK" \
    --version 20260902 --out "$TMP/out-dd" --rootfs-dir "$ROOTTREE" \
    --payload-name fusys-image-eval-fsimx8mp.squashfs \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"

echo "# --- build failures leave no fragment in --out ---"
mkdir -p "$TMP/out-7"
rc_is "rauc bundle fails -> 7" 7 env STUB_BUNDLE_RC=1 "$MKOK" "$TMP/out-7"
check "no fragment after exit 7" "" "$(ls -A "$TMP/out-7")"
mkdir -p "$TMP/out-8"
rc_is "self-verification fails -> 8" 8 env STUB_RAUC_RC=1 "$MKOK" "$TMP/out-8"
check "no fragment after exit 8" "" "$(ls -A "$TMP/out-8")"

echo "# --- the happy path ---"
OUT="$TMP/out"; mkdir -p "$OUT"
LOG2="$TMP/rauc-build.log"; : > "$LOG2"
env STUB_RAUC_LOG="$LOG2" STUB_CONTENT_LIST="$TMP/content.list" \
    STUB_CONTENT_COPY="$TMP/content.copy" \
    "$MKOK" "$OUT" > "$TMP/ok.out" 2> "$TMP/ok.err"
check "build -> 0" 0 "$?"
has "stdout names the artifact"  "artifact=$OUT/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb" "$TMP/ok.out"
has "stdout reports the verdict" "result=pass" "$TMP/ok.out"
# The built-in verification of the bundle verb runs under rauc's default
# certificate purpose and rejects this PKI's codeSigning-only leaf; the
# property is covered by the mandatory self-verification instead.
lacks "bundle runs without --signing-keyring" "signing-keyring" "$LOG2"
check "stamped artifact exists" yes \
    "$([ -f "$OUT/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb" ] && echo yes)"
check "info rides the stamped name" yes \
    "$([ -f "$OUT/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info" ] && echo yes)"
check "symlink points at the stamped name" "ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb" \
    "$(readlink "$OUT/ext-fus-fw-bundle-fsimx8mp.raucb")"
check "content holds exactly three entries" 3 "$(grep -c . "$TMP/content.list")"
has "content: the payload (source basename)" "fusys-image-eval-fsimx8mp.squashfs" "$TMP/content.list"
has "content: the hook"     "install-check"  "$TMP/content.list"
has "content: the manifest" "manifest.raucm" "$TMP/content.list"
lacks "decoys next to the source are ignored" "fusys-image-other" "$TMP/content.list"
MF="$TMP/content.copy/manifest.raucm"
has "manifest: compatible"      "compatible=fus-update-fsimx8mp" "$MF"
has "manifest: version"         "version=20260902" "$MF"
has "manifest: build stamp"     "build=$STAMP" "$MF"
has "manifest: verity format"   "format=verity" "$MF"
has "manifest: hook filename"   "filename=install-check" "$MF"
has "manifest: rootfs image"    "[image.rootfs]" "$MF"
has "manifest: image hook"      "hooks=post-install" "$MF"
lacks "manifest carries no digest (rauc computes it)" "sha256" "$MF"
HOOKC="$TMP/content.copy/install-check"
has "staged hook: token substituted" "/data/app/images" "$HOOKC"
lacks "staged hook: no raw token left" "@@FUS_APP_IMG_DIR@@" "$HOOKC"
check "staged hook is executable" yes "$([ -x "$HOOKC" ] && echo yes)"
# The read-back stage itself, not only the staged copy: the integrity
# guarantee rests on it and nothing else in this tool set ever runs it. Regular
# files stand in for the slot device -- dd/sha256sum/wc are real, and
# drop_caches merely takes the hook's own warning branch when it is denied.
RB="$TMP/readback"; mkdir -p "$RB"
printf 'payload bytes for the read-back stage\n' > "$RB/img.squashfs"
cp "$RB/img.squashfs" "$RB/slot.raw"
# Run it without the power to flush the host page cache: the hook drops caches
# unconditionally, which as root would hit the whole machine and not just this
# suite. A user namespace denies the write, so the hook takes its own warning
# branch -- the same branch an unprivileged run takes.
RBNS=""
if unshare -r true 2>/dev/null; then
    RBNS="unshare -r"
elif [ "$(id -u)" = 0 ]; then
    # No namespace and real root: the drop actually happens. Loud, because a
    # silent host-wide cache flush out of a unit test is worse than a noisy one.
    echo "WARNING: no user namespace available and running as root --" \
         "the read-back stage will flush this machine's page cache" >&2
fi
rb_run() { # the read-back stage against the stub slot, one definition for both
    # shellcheck disable=SC2086  # empty or a two-word prefix, on purpose
    $RBNS env RAUC_SLOT_NAME=rootfs.0 RAUC_SLOT_DEVICE="$RB/slot.raw" \
        RAUC_IMAGE_NAME=img.squashfs RAUC_BUNDLE_MOUNT_POINT="$RB" \
        "$HOOKC" slot-post-install
}
rc_is "read-back: a faithful slot passes" 0 rb_run
printf 'X' | dd of="$RB/slot.raw" bs=1 seek=3 conv=notrunc 2>/dev/null
rb_run >/dev/null 2>"$RB/mismatch.err"
check "read-back: one flipped byte fails the install" 1 "$?"
has "read-back: the mismatch is named" "READ-BACK MISMATCH" "$RB/mismatch.err"
INFO="$OUT/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
has "info: rauc version"        "tool.rauc.version=rauc 1.15.2" "$INFO"
has "info: mksquashfs version"  "tool.mksquashfs.version=" "$INFO"
has "info: the window"          "rauc.window=1.13..1.15.2" "$INFO"
has "info: the format constant" "const.FUS_BUNDLE_FORMAT=verity" "$INFO"
has "info: source date epoch"   "source_date_epoch=" "$INFO"
has "info: floor not checked"   "floor.checked=no" "$INFO"
has "info: shape warning clear" "version.shape_warning=no" "$INFO"
has "info: identity travelled"  "compatible=fus-update-fsimx8mp" "$INFO"
has "info: chain subject"       "signature.subject=" "$INFO"
has "info: chain SPKI"          "signature.spki_sha256=" "$INFO"
lacks "info holds no host paths" "$TMP" "$INFO"
# The ownership lines belong to the directory door alone: this tool never
# touched the ownership inside a pre-built payload, so claiming anything
# about it here would be an unfounded positive-list entry.
lacks "image-door info carries no ownership claim" "ownership." "$INFO"

echo "# --- second build repoints the symlink, keeps the first artifact ---"
"$MKOK" "$OUT" --build-stamp 20260901120001 >/dev/null 2>&1
check "second build -> 0" 0 "$?"
check "symlink repointed" "ext-fus-fw-bundle-fsimx8mp-20260902-20260901120001.raucb" \
    "$(readlink "$OUT/ext-fus-fw-bundle-fsimx8mp.raucb")"
check "first artifact untouched" yes \
    "$([ -f "$OUT/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb" ] && echo yes)"

echo "# --- the compatible lever and the recorded floor ---"
OUT2="$TMP/out2"; mkdir -p "$OUT2"
env STUB_COMPAT=fus-update-wrongboard STUB_CONTENT_COPY="$TMP/content.wrong" \
    "$MKOK" "$OUT2" --compatible fus-update-wrongboard >/dev/null 2>&1
check "wrong-compat build -> 0 (the bench lever)" 0 "$?"
has "manifest carries the override" "compatible=fus-update-wrongboard" \
    "$TMP/content.wrong/manifest.raucm"
OUT3="$TMP/out3"; mkdir -p "$OUT3"
"$MKOK" "$OUT3" --floor 20260902 >/dev/null 2>&1
check "floored build -> 0" 0 "$?"
has "info records the floor check" "floor.checked=yes" \
    "$OUT3/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
has "info records the floor value" "floor.value=20260902" \
    "$OUT3/ext-fus-fw-bundle-fsimx8mp-20260902-$STAMP.raucb.info"
OUT4="$TMP/out4"; mkdir -p "$OUT4"
env STUB_VERSION=1.0 "$MKOK" "$OUT4" --version 1.0 > /dev/null 2> "$TMP/shape.err"
check "non-date version builds -> 0" 0 "$?"
has "the shape warning fired" "not date-shaped" "$TMP/shape.err"
has "info records the shape warning" "version.shape_warning=yes" \
    "$OUT4/ext-fus-fw-bundle-fsimx8mp-1.0-$STAMP.raucb.info"

echo "# --- dry run: preflights and manifest, no build ---"
OUT5="$TMP/out5"; mkdir -p "$OUT5"
LOG3="$TMP/rauc-dry.log"; : > "$LOG3"
env STUB_RAUC_LOG="$LOG3" "$MKOK" "$OUT5" --dry-run > "$TMP/dry.out" 2>&1
check "dry run -> 0" 0 "$?"
has "dry run prints the manifest"    "[update]" "$TMP/dry.out"
has "dry run resolves the defaults"  "compatible=fus-update-fsimx8mp" "$TMP/dry.out"
check "dry run builds nothing" "" "$(ls -A "$OUT5")"
lacks "dry run never calls rauc bundle" "bundle" "$LOG3"

echo "# --- a verify-child failure that is no verdict passes through ---"
mkdir -p "$TMP/out-p1"
# The child creates its work directory under TMPDIR; a vanished TMPDIR is
# its usage error (2) and must not surface as "verification failed" (8).
rc_is "verify child usage error -> 2, not 8" 2 env TMPDIR="$TMP/gone-tmp" "$MKOK" "$TMP/out-p1"
check "no fragment after the passthrough" "" "$(ls -A "$TMP/out-p1")"
# A verify companion that cannot run its check (exit 3) keeps its class.
mkdir -p "$TMP/alone3" "$TMP/out-p3"
cp "$DIR/fus-mk-fw-bundle.sh" "$DIR/fus-bundle-lib.sh" "$TMP/alone3/"
cp -L "$DIR/install-check" "$TMP/alone3/install-check"
printf '#!/bin/sh\nexit 3\n' > "$TMP/alone3/fus-verify-bundle.sh"
chmod +x "$TMP/alone3/fus-verify-bundle.sh"
rc_is "verify child tool error -> 3, not 8" 3 env PATH="$SPATH" "$TMP/alone3/fus-mk-fw-bundle.sh" \
    --version 20260902 --out "$TMP/out-p3" --rootfs-image "$PAYLOAD" \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"
# A companion that lost its exec bit in a copy must be a named tool error
# (3) at preflight -- never a raw 126 escaping the documented code table.
mkdir -p "$TMP/alone4" "$TMP/out-p4"
cp "$DIR/fus-mk-fw-bundle.sh" "$DIR/fus-bundle-lib.sh" "$TMP/alone4/"
cp -L "$DIR/install-check" "$TMP/alone4/install-check"
cp "$DIR/fus-verify-bundle.sh" "$TMP/alone4/fus-verify-bundle.sh"
chmod -x "$TMP/alone4/fus-verify-bundle.sh"
rc_is "verify companion without exec bit -> 3" 3 env PATH="$SPATH" "$TMP/alone4/fus-mk-fw-bundle.sh" \
    --version 20260902 --out "$TMP/out-p4" --rootfs-image "$PAYLOAD" \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"

echo "# --- a relative tool override is pinned before validation ---"
# A slashless FUS_MKSQUASHFS used to leave the PATH prefix a no-op, so the
# preflight validated a different binary than rauc would later find. The
# pin alone is only half the invariant: rauc invokes mksquashfs BY NAME, so
# an override under any other basename still splits preflight and build --
# it must be refused, not blessed.
mkdir -p "$TMP/relbin"
cp "$TMP/bin/mksquashfs" "$TMP/relbin/mksq-local"
( cd "$TMP/relbin" && env PATH="$SPATH" FUS_MKSQUASHFS=mksq-local "$MK" --check-tools ) \
    > "$TMP/rel.out" 2> "$TMP/rel.err"
check "an override under a foreign basename -> 3" 3 "$?"
has "the refusal names the basename rule" "basename" "$TMP/rel.err"
lacks "no blessed path line for the refused override" "tool.mksquashfs.path=" "$TMP/rel.out"
cp "$TMP/bin/mksquashfs" "$TMP/relbin/mksquashfs"
( cd "$TMP/relbin" && env PATH="$SPATH" FUS_MKSQUASHFS=mksquashfs "$MK" --check-tools ) \
    > "$TMP/rel2.out" 2>&1
check "a correctly named relative override -> 0" 0 "$?"
has "the reported path is absolute" "tool.mksquashfs.path=$TMP/relbin/mksquashfs" "$TMP/rel2.out"

echo "# --- payload names off the device glob warn, loudly but green ---"
printf 'hsqs odd payload\n' > "$TMP/odd-name.squashfs"
mkdir -p "$TMP/out-w"
"$MKOK" "$TMP/out-w" --rootfs-image "$TMP/odd-name.squashfs" > /dev/null 2> "$TMP/warn.err"
check "off-glob payload builds -> 0" 0 "$?"
has "the warning names the mismatch" "does not match" "$TMP/warn.err"
# The basename default must never collide with the bundle's own entries --
# a payload staged as install-check would be overwritten by the hook.
printf 'hsqs reserved-name payload\n' > "$TMP/install-check"
rc_is "payload named like a reserved entry -> 2" 2 "$MKOK" "$TMP/out-u" --rootfs-image "$TMP/install-check"

echo "# --- standalone: the tool set works copied away from the layer ---"
mkdir -p "$TMP/standalone" "$TMP/out-s"
cp "$DIR/fus-bundle-lib.sh" "$DIR/fus-verify-bundle.sh" "$DIR/fus-mk-fw-bundle.sh" "$TMP/standalone/"
cp -L "$DIR/install-check" "$TMP/standalone/install-check"
rc_is "copied set builds -> 0" 0 env PATH="$SPATH" "$TMP/standalone/fus-mk-fw-bundle.sh" \
    --version 20260902 --out "$TMP/out-s" --rootfs-image "$PAYLOAD" \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"
mkdir -p "$TMP/alone" "$TMP/out-a"
cp "$DIR/fus-mk-fw-bundle.sh" "$DIR/fus-bundle-lib.sh" "$TMP/alone/"
rc_is "mk without the verify companion -> 3" 3 env PATH="$SPATH" "$TMP/alone/fus-mk-fw-bundle.sh" \
    --version 20260902 --out "$TMP/out-a" --rootfs-image "$PAYLOAD" \
    --cert "$CERT" --key "$KEY" --keyring "$KEYRING" --build-stamp "$STAMP"

echo "# --- help and pkcs11 ---"
"$MK" --help > "$TMP/help.out" 2> "$TMP/help.err"
check "--help exits 0" 0 "$?"
has "--help prints usage on stdout" "Usage:" "$TMP/help.out"
has "--help documents the directory door" "--rootfs-dir" "$TMP/help.out"
has "--help documents the ownership bypass" "--i-know-ownership-is-wrong" "$TMP/help.out"
has "--help lists the environment code" "11 environment precondition" "$TMP/help.out"
lacks "--help no longer refuses the directory door" "refused with exit 2" "$TMP/help.out"
check "--help prints nothing on stderr" "" "$(cat "$TMP/help.err")"
# --help and --check-tools read nothing that FUS_I_KNOW_OWNERSHIP_IS_WRONG
# feeds -- a malformed value must not stop them from answering.
rc_is "a malformed env twin does not break --help" 0 \
    env FUS_I_KNOW_OWNERSHIP_IS_WRONG=maybe "$MK" --help
rc_is "a malformed env twin does not break --check-tools" 0 \
    env FUS_I_KNOW_OWNERSHIP_IS_WRONG=maybe PATH="$SPATH" "$MK" --check-tools
OUT6="$TMP/out6"; mkdir -p "$OUT6"
LOG4="$TMP/rauc-p11.log"; : > "$LOG4"
env STUB_RAUC_LOG="$LOG4" "$MKOK" "$OUT6" \
    --cert "pkcs11:token=stub;object=cert" --key "pkcs11:token=stub;object=key" \
    >/dev/null 2>&1
check "pkcs11 specs are accepted -> 0" 0 "$?"
has "the URI reaches rauc untouched" "pkcs11:token=stub" "$LOG4"

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
