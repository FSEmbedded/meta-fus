#!/bin/sh
# fus-mk-fw-bundle.sh -- build a firmware RAUC bundle from a finished
# rootfs squashfs or from a rootfs directory, without Yocto and without
# bitbake.
#
# The directory door packs the source itself, and a packed filesystem keeps
# the uid/gid of the packing process: it therefore refuses to run as a
# non-root user (exit 11) unless the ownership is explicitly accepted, and
# that acceptance is recorded in the .info beside the artifact.
#
# The content directory is ALWAYS built by this script inside its own work
# directory, and rauc is never pointed at a foreign directory: rauc bundle
# creates its workdir INSIDE the input directory (measured -- a read-only
# source directory can never work), and a deploy directory must never become
# rauc's scratch space. Nothing next to the named inputs is looked at.
#
# The result is self-verified with fus-verify-bundle.sh before it is
# published; publication is atomic and never overwrites, and a .info file
# with the build evidence travels beside the stamped artifact.
#
# Output: key=value on stdout, diagnostics on stderr.
# Exit codes: 0 ok, 2 usage, 3 tool missing or outside the measured window,
# 4 signing material or keyring unusable, 5 source or hook unusable,
# 6 size guard, 7 rauc bundle or mksquashfs failed, 8 self-verification
# failed, 10 version/floor policy violated, 11 environment precondition not
# met (packing as non-root); 1 is never assigned deliberately. A 2,
# 3 or 4 can also be passed through from the self-verification child when
# IT could not run its check -- stderr names that case explicitly.
# Env twins for every option are listed in --help; the PKCS#11 PIN travels
# only in RAUC_PKCS11_PIN, never as an argument.
set -u

# Builtins only until the tools are resolved: an emptied PATH has to end in
# exit 3 naming the missing tool, not in an unrelated failure.
case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
SCRIPT_DIR=$(CDPATH='' cd -- "$_self_dir" && pwd) || {
    printf '%s\n' "${0##*/}: cannot resolve the script directory" >&2
    exit 3
}
for _companion in fus-bundle-lib.sh fus-verify-bundle.sh; do
    [ -f "$SCRIPT_DIR/$_companion" ] || {
        printf '%s\n' "${0##*/}: $_companion not found next to this script (the tool set is copied as one directory)" >&2
        exit 3
    }
done
# The verify companion is executed, not sourced; a copy that lost the exec
# bit would otherwise surface as a raw 126 after the build instead of a
# named tool error before it.
[ -x "$SCRIPT_DIR/fus-verify-bundle.sh" ] || {
    printf '%s\n' "${0##*/}: fus-verify-bundle.sh is not executable (copy lost the exec bit?)" >&2
    exit 3
}
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fus-bundle-lib.sh"

usage() {
    printf '%s\n' \
        'Usage: fus-mk-fw-bundle.sh [options]' \
        '' \
        'Build a firmware RAUC bundle (rootfs slot, verity format) from a' \
        'finished squashfs image or from a rootfs directory. The content' \
        'directory is built inside the work directory in --out; nothing is' \
        'searched for and rauc is never pointed at a foreign directory.' \
        '' \
        'Required:' \
        '  --version <v>          bundle version (semver-parsable) [FUS_VERSION]' \
        '  --out <dir>            existing output directory [FUS_OUT]' \
        '  --rootfs-image <file>  the rootfs squashfs payload; exactly one of' \
        '  --rootfs-dir <dir>     this pair is required. The directory door packs' \
        '                         the tree itself and needs root, or an ownership-' \
        '                         faking session wrapped around BOTH the unpack and' \
        '                         this call, e.g. fakeroot (see below).' \
        '  --cert <spec>          signing cert: path or pkcs11: URI [FUS_UPDATE_CERT]' \
        '  --key <spec>           signing key: path or pkcs11: URI [FUS_UPDATE_KEY]' \
        '  --keyring <pem>        CA the device trusts; the mandatory self-' \
        '                         verification runs against it [FUS_UPDATE_KEYRING]' \
        '' \
        'Options:' \
        '  --certs <dir>          shorthand for <dir>/sign.cert.pem + <dir>/sign.key.pem' \
        '                         [FUS_UPDATE_CERT_DIR]' \
        '  --machine <m>          machine name (default fsimx8mp) [FUS_MACHINE]' \
        '  --compatible <s>       override the full compatible string [FUS_COMPATIBLE]' \
        '  --payload-name <name>  payload filename inside the bundle (default:' \
        '                         the basename of --rootfs-image; a name not' \
        '                         matching fusys-image-*.squashfs warns).' \
        '                         Required with --rootfs-dir: a directory has no' \
        '                         payload basename to inherit.' \
        '  --i-know-ownership-is-wrong  pack a directory as a non-root user' \
        '                         anyway. Warns on stderr and is recorded in the' \
        '                         .info; every file then carries the packing' \
        '                         uid/gid instead of the intended ownership.' \
        '                         [FUS_I_KNOW_OWNERSHIP_IS_WRONG]' \
        '  --floor <v>            refuse to build below this version (exit 10) [FUS_FLOOR]' \
        '  --hook <file>          hook script (default install-check next to this' \
        '                         script) [FUS_HOOK]' \
        '  --build-stamp <s>      build stamp (default UTC now) [FUS_BUILD_STAMP]' \
        '  --description <s>      manifest description [FUS_DESCRIPTION]' \
        '  --source-date-epoch <n>  reproducibility epoch (default: the mtime of' \
        '                         the payload file or of the source directory)' \
        '                         [SOURCE_DATE_EPOCH]' \
        '  --expect-rauc <v>      warn when the resolved rauc version differs' \
        '  --require-rauc <v>     exit 3 when the resolved rauc version differs' \
        '  --dry-run              run all preflights, print the manifest, build' \
        '                         nothing. With --rootfs-dir the slot fit stays' \
        '                         unchecked: nothing is packed, and the packed' \
        '                         size is the only comparable one.' \
        '  --check-tools          resolve rauc and mksquashfs, print versions and the' \
        '                         measured window, exit 0 (or 3)' \
        '  --help                 this text' \
        '' \
        'The directory door: the tree is packed with the layer settings' \
        '(FUS_MKSQUASHFS_ARGS) under a pinned SOURCE_DATE_EPOCH, into the work' \
        'directory, never into --out. The packed image keeps the packing uid/gid,' \
        'so this needs real root, or an ownership-faking wrapper such as fakeroot' \
        'around BOTH the source-tree preparation (e.g. unsquashfs) and this call in' \
        'the SAME session -- unsquashfs outside it, packed inside it, fakes every' \
        'file as uid 0 instead of the ones that really are. Neither -- exit 11.' \
        'Note that the uid is all this can check: under fakeroot or pseudo it' \
        'reads 0 whether or not the tree was prepared in that same session.' \
        'FUS_MKSQUASHFS_ARGS must not carry -all-root (exit 11): it would' \
        'discard the very ownership the guard above vouches for.' \
        '' \
        'Artifacts in --out:' \
        '  ext-fus-fw-bundle-<machine>-<version>-<stamp>.raucb (+ .info beside it)' \
        '  ext-fus-fw-bundle-<machine>.raucb -> symlink to the newest build' \
        '' \
        'Exit codes: 0 ok, 2 usage, 3 tool, 4 signing material, 5 source/hook,' \
        '6 size guard, 7 rauc bundle or mksquashfs failed, 8 self-verification' \
        'failed, 10 floor violated, 11 environment precondition not met' \
        '(packing as non-root). A 1 is a script defect, never a verdict.'
}

version="${FUS_VERSION:-}"
out="${FUS_OUT:-}"
cert="${FUS_UPDATE_CERT:-}"
key="${FUS_UPDATE_KEY:-}"
keyring="${FUS_UPDATE_KEYRING:-}"
certs_dir="${FUS_UPDATE_CERT_DIR:-}"
machine="${FUS_MACHINE:-fsimx8mp}"
compatible="${FUS_COMPATIBLE:-}"
floor="${FUS_FLOOR:-}"
hook="${FUS_HOOK:-}"
stamp="${FUS_BUILD_STAMP:-}"
description="${FUS_DESCRIPTION:-}"
sde="${SOURCE_DATE_EPOCH:-}"
rootfs_image=''; rootfs_dir=''; payload_name=''
expect_rauc=''; require_rauc=''; dry_run=0; check_tools=0
own_bypass=0

while [ $# -gt 0 ]; do
    case "$1" in
    --help)
        usage
        exit 0 ;;
    --check-tools) check_tools=1 ;;
    --dry-run)     dry_run=1 ;;
    --i-know-ownership-is-wrong) own_bypass=1 ;;
    --version|--out|--cert|--key|--keyring|--certs|--machine|--compatible|--payload-name|--floor|--hook|--build-stamp|--description|--source-date-epoch|--expect-rauc|--require-rauc|--rootfs-image|--rootfs-dir)
        [ $# -ge 2 ] || fus_die 2 "option $1 requires a value"
        case "$1" in
        --version)           version=$2 ;;
        --out)               out=$2 ;;
        --cert)              cert=$2 ;;
        --key)               key=$2 ;;
        --keyring)           keyring=$2 ;;
        --certs)             certs_dir=$2 ;;
        --machine)           machine=$2 ;;
        --compatible)        compatible=$2 ;;
        --payload-name)      payload_name=$2 ;;
        --floor)             floor=$2 ;;
        --hook)              hook=$2 ;;
        --build-stamp)       stamp=$2 ;;
        --description)       description=$2 ;;
        --source-date-epoch) sde=$2 ;;
        --expect-rauc)       expect_rauc=$2 ;;
        --require-rauc)      require_rauc=$2 ;;
        --rootfs-image)      rootfs_image=$2 ;;
        --rootfs-dir)        rootfs_dir=$2 ;;
        esac
        shift ;;
    -*)
        fus_die 2 "unknown option: $1 (see --help)" ;;
    *)
        fus_die 2 "unexpected operand: $1 (this tool takes options only)" ;;
    esac
    shift
done

if [ "$check_tools" -eq 1 ]; then
    # The job preflight: report first, so a CI log shows what was found, then
    # enforce the measured window (under the minimum -> 3, above -> warning).
    fus_tools_report rauc FUS_RAUC rauc - \
        mksquashfs FUS_MKSQUASHFS squashfs-tools byname
    ct_rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
    ct_ver=$(fus_rauc_version "$ct_rauc")
    printf 'rauc.version=%s\n' "${ct_ver:-unknown}"
    printf 'rauc.window=%s..%s\n' "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    fus_rauc_version_gate "$ct_rauc" "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    exit 0
fi

# Validated here, after --help and --check-tools have already had their
# chance to exit: neither reads $own_bypass, so neither should be able to
# die on a malformed environment variable it never uses. The env twin takes
# an explicit affirmative, not "any non-empty string" -- this one variable
# disables the guard the directory door exists for, and a CI exporting =0 to
# mean "off" must not open it. Anything else is refused rather than silently
# read as no -- a misspelt yes would otherwise look like a working opt-out
# until the ownership reaches a device.
case "${FUS_I_KNOW_OWNERSHIP_IS_WRONG:-}" in
'')            : ;;
1|yes|true)    own_bypass=1 ;;
0|no|false)    : ;;
*) fus_die 2 "FUS_I_KNOW_OWNERSHIP_IS_WRONG must be 1/yes/true or 0/no/false" ;;
esac

# --- usage (2) -------------------------------------------------------------
[ -n "$version" ] || fus_die 2 "--version is required (no date default)"
fus_check_semver "$version"
shape_warned=no
fus_check_version_shape "$version" || shape_warned=yes

[ -n "$out" ] || fus_die 2 "--out is required"
[ -d "$out" ] || fus_die 2 "--out does not exist (it is not created; this catches typos): $out"

# Exactly one source: two doors lead to the same bundle, and a run that
# named both would silently pack one and ignore the other.
if [ -n "$rootfs_image" ] && [ -n "$rootfs_dir" ]; then
    fus_die 2 "two sources given: --rootfs-image and --rootfs-dir are mutually exclusive"
fi
[ -n "$rootfs_image" ] || [ -n "$rootfs_dir" ] || \
    fus_die 2 "no source given: --rootfs-image or --rootfs-dir is required"
# The bypass says something about packing; on the image door this tool packs
# nothing and would be claiming an ownership property it never touched.
if [ "$own_bypass" -eq 1 ] && [ -z "$rootfs_dir" ]; then
    fus_die 2 "--i-know-ownership-is-wrong applies to --rootfs-dir only: the image door does not pack and makes no ownership claim"
fi

[ -n "$keyring" ] || fus_die 2 "--keyring is required; self-verification is not optional"
[ -f "$keyring" ] || fus_die 2 "keyring: no such file (path withheld; check --keyring)"

case "$machine" in ''|*/*) fus_die 2 "unusable machine name" ;; esac
# No invented default: the payload name inside the bundle is the basename of
# the named source (deploy publishes the canonical unstamped name as the
# symlink's own name), overridable with --payload-name. The directory door
# has no such basename -- the source directory's own name is a build-tree
# artifact, not a payload name, and the name is a device contract (the
# hook's fallback lookup matches it), so it is demanded rather than invented.
[ -n "$payload_name" ] || payload_name=${rootfs_image##*/}
# Named for the door actually in use: an image path ending in a slash also
# leaves the basename empty, and blaming --payload-name there would name a
# flag the caller never passed.
if [ -z "$payload_name" ]; then
    [ -z "$rootfs_dir" ] && fus_die 2 \
        "--rootfs-image has no filename component: $rootfs_image"
    fus_die 2 \
        "--payload-name is required with --rootfs-dir: a directory carries no payload basename to inherit"
fi
case "$payload_name" in ''|*/*) fus_die 2 "payload name must not contain '/'" ;; esac
case "$payload_name" in
install-check|manifest.raucm) fus_die 2 "payload name collides with a reserved bundle entry: $payload_name" ;;
esac
# shellcheck disable=SC2254  # the constant is a glob on purpose
case "$payload_name" in
$FUS_FW_PAYLOAD_GLOB) : ;;
*) printf '%s\n' "${0##*/}: WARNING: payload name '$payload_name' does not match $FUS_FW_PAYLOAD_GLOB; only the device hook's FALLBACK lookup would miss it -- the primary lookup goes by the manifest name and still works" >&2 ;;
esac

[ -n "$stamp" ] || stamp=$(date -u +%Y%m%d%H%M%S)
case "$stamp" in ''|*/*) fus_die 2 "unusable build stamp" ;; esac

[ -z "$floor" ] || { fus_check_semver "$floor"; fus_check_version_shape "$floor" || true; }

if [ -n "$sde" ]; then
    case "$sde" in ''|*[!0-9]*) fus_die 2 "--source-date-epoch must be a decimal epoch" ;; esac
fi

[ -n "$compatible" ] || compatible="${FUS_COMPAT_PREFIX}${machine}"
[ -n "$description" ] || description="$FUS_FW_DESCRIPTION"
[ -n "$hook" ] || hook="$SCRIPT_DIR/install-check"

base="ext-fus-fw-bundle-$machine-$version-$stamp.raucb"
final="${out%/}/$base"
final_info="$final.info"
link="${out%/}/ext-fus-fw-bundle-$machine.raucb"
# Refuse before any work, not only at publish time: a stamped artifact is
# never overwritten.
[ ! -e "$final" ] || fus_die 2 "artifact already exists, not overwriting: $final"
[ ! -e "$final_info" ] || fus_die 2 "artifact info already exists, not overwriting: $final_info"

# --- tools (3) -------------------------------------------------------------
rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
mksq=$(fus_tool_resolve mksquashfs FUS_MKSQUASHFS squashfs-tools byname) || exit $?
fus_rauc_version_gate "$rauc" "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
rauc_ver=$(fus_rauc_version "$rauc")
if [ -n "$expect_rauc" ] && [ "$rauc_ver" != "$expect_rauc" ]; then
    printf '%s\n' "${0##*/}: WARNING: rauc is '${rauc_ver:-unknown}', expected '$expect_rauc'" >&2
fi
if [ -n "$require_rauc" ] && [ "$rauc_ver" != "$require_rauc" ]; then
    fus_die 3 "rauc is '${rauc_ver:-unknown}' but --require-rauc demands '$require_rauc'"
fi

# --- signing material (4) --------------------------------------------------
if [ -n "$certs_dir" ]; then
    [ -n "$cert" ] || cert="${certs_dir%/}/sign.cert.pem"
    [ -n "$key" ] || key="${certs_dir%/}/sign.key.pem"
fi
fus_require_signing "$cert" "$key"
[ -r "$keyring" ] && [ -s "$keyring" ] || fus_die 4 "keyring: unreadable or empty (path withheld)"

# --- environment (11), source and hook (5), size guard (6) -----------------
# The uid guard sits after tool resolution on purpose: `id` is a PATH lookup,
# so under an emptied PATH the documented tool error (3) has to win over a
# uid this script could not read at all. It still runs before anything looks
# at the source tree.
FUS_BUILD_UID=''
if [ -n "$rootfs_dir" ]; then
    # Before the uid guard, because -all-root would make that guard's promise
    # false: it discards the ownership even for a real root run, and the guard
    # would still record a clean build. Only the directory door packs, so only
    # it can lose the ownership -- the image door makes no such claim.
    if fus_args_contain "$FUS_MKSQUASHFS_ARGS" -all-root; then
        fus_die 11 \
            "FUS_MKSQUASHFS_ARGS carries -all-root: the firmware payload would be flattened to uid 0 and the ownership guard could not mean anything; -all-root belongs to the app door only"
    fi
    fus_require_root "$own_bypass" "packing a rootfs directory"
    [ -d "$rootfs_dir" ] || fus_die 5 "rootfs directory not found: $rootfs_dir"
    # Both bits, and named apart from "empty": an unlistable or untraversable
    # tree would otherwise reach the emptiness check below and be reported as
    # empty, which is a different finding entirely.
    [ -r "$rootfs_dir" ] && [ -x "$rootfs_dir" ] || \
        fus_die 5 "rootfs directory is not readable and traversable: $rootfs_dir"
    # An empty tree packs into a valid but useless squashfs; the device would
    # boot nothing. Same class as the image door's bad-magic refusal. The
    # listing is captured into the test, not piped: its emptiness is the
    # verdict, never a command's exit status.
    [ -n "$(ls -A "$rootfs_dir" 2>/dev/null)" ] || \
        fus_die 5 "rootfs directory is empty: $rootfs_dir"
else
    fus_require_file "$rootfs_image" 5 "rootfs image not found or not readable: $rootfs_image"
    # Cheap contract check on the source: a squashfs starts with 'hsqs'. This
    # catches handing a .raucb or a tarball to the image door.
    magic=$(head -c 4 "$rootfs_image" 2>/dev/null) || magic=''
    [ "$magic" = "hsqs" ] || fus_die 5 "rootfs image is not a squashfs (bad magic): $rootfs_image"
fi
fus_require_file "$hook" 5 "hook not found or not readable: $hook"

# The named payload is checkable before any work is done, so the image door
# keeps the slot fit as a preflight -- --dry-run promises exactly that. It
# stays BEHIND the hook check: an unusable input (5) outranks a policy
# verdict (6), and that was the order before the directory door existed.
# The directory door has nothing to measure until it has packed, and checks
# the packed result instead.
[ -n "$rootfs_dir" ] || fus_check_slot_fit "$rootfs_image" "$FUS_SIZE_ROOT_MIB"

# --- floor (10) ------------------------------------------------------------
floor_checked=no
if [ -n "$floor" ]; then
    fus_check_floor "$version" "$floor"
    floor_checked=yes
fi

# The directory door mirrors what the image recipe does for the same tree:
# SOURCE_DATE_EPOCH defaults to the source's own mtime.
[ -n "$sde" ] || sde=$(stat -Lc %Y "${rootfs_dir:-$rootfs_image}" 2>/dev/null) || \
    fus_die 5 "cannot read the source mtime for SOURCE_DATE_EPOCH"

# --- dry run: all preflights done, print the manifest, build nothing -------
if [ "$dry_run" -eq 1 ]; then
    fus_manifest_begin "$compatible" "$version" "$description" "$stamp" \
        "$FUS_BUNDLE_FORMAT" install-check
    fus_manifest_image "$FUS_FW_SLOT_CLASS" "$payload_name" "$FUS_FW_IMAGE_HOOK"
    exit 0
fi

# --- build -----------------------------------------------------------------
fus_workdir "$out"
content="$FUS_WORKDIR/content"
mkdir "$content" || fus_die 2 "cannot create the content directory"

# Both doors converge here: from the staged payload on, the two paths run
# the same lines -- hook, manifest, bundle, self-verification, .info,
# publish. The directory door packs straight into the content directory,
# which lives inside the work directory; nothing is ever written next to
# --out before the atomic publish.
if [ -n "$rootfs_dir" ]; then
    fus_squashfs_from_dir "$rootfs_dir" "$content/$payload_name" "$mksq" \
        "$sde" "$FUS_WORKDIR/mksquashfs.log" "$FUS_MKSQUASHFS_ARGS"
    # A stat failure here is on a file this script just packed -- the
    # packer's fault, not a usage error: 7, not the default 2.
    fus_check_slot_fit "$content/$payload_name" "$FUS_SIZE_ROOT_MIB" 7
else
    # Hardlink where possible (146 MB per run is not worth copying), plain
    # copy as the fallback; -L because deploy publishes payloads behind
    # symlinks.
    if ! cp -l -L "$rootfs_image" "$content/$payload_name" 2>/dev/null; then
        cp -p -L "$rootfs_image" "$content/$payload_name" || \
            fus_die 5 "cannot stage the payload"
    fi
fi

fus_install_hook "$hook" "$content/install-check" "$FUS_APP_IMG_DIR"

{
    fus_manifest_begin "$compatible" "$version" "$description" "$stamp" \
        "$FUS_BUNDLE_FORMAT" install-check
    fus_manifest_image "$FUS_FW_SLOT_CLASS" "$payload_name" "$FUS_FW_IMAGE_HOOK"
} > "$content/manifest.raucm" || fus_die 2 "cannot write the manifest"

work_bundle="$FUS_WORKDIR/$base"
SOURCE_DATE_EPOCH="$sde" export SOURCE_DATE_EPOCH
fus_rauc_bundle "$content" "$work_bundle" "$rauc" "$mksq" \
    "$cert" "$key" "$FUS_WORKDIR/rauc-bundle.log"

# --- mandatory self-verification (8) ---------------------------------------
"$SCRIPT_DIR/fus-verify-bundle.sh" \
    --keyring "$keyring" \
    --expect-compatible "$compatible" \
    --expect-version "$version" \
    --expect-format "$FUS_BUNDLE_FORMAT" \
    --identity-out "$FUS_WORKDIR/identity" \
    "$work_bundle" > "$FUS_WORKDIR/verify.out" 2> "$FUS_WORKDIR/verify.err"
verify_rc=$?
if [ "$verify_rc" -ne 0 ]; then
    cat "$FUS_WORKDIR/verify.err" >&2
    if [ "$verify_rc" -eq 8 ]; then
        fus_die 8 "self-verification failed (exit 8)"
    fi
    # Anything else is not a verdict about the bundle: the child could not
    # run its check. Its own class passes through unchanged rather than
    # masquerading as a failed verification -- but only classes the child
    # actually assigns; an exec-level code (126/127) must not escape the
    # documented table and is a tool error here.
    # 10 is deliberately absent: the child only assigns it for --floor, and
    # mk passes none -- whoever adds a floor passthrough extends this case.
    case "$verify_rc" in
    2|3|4) fus_die "$verify_rc" "self-verification could not run (verify exit $verify_rc)" ;;
    esac
    fus_die 3 "self-verification tool could not be executed (exit $verify_rc)"
fi

# --- signature chain for the .info (subject + SPKI per member) -------------
keyring_abs=$(fus_abspath "$keyring")
fus_write_verify_conf "$keyring_abs" "$FUS_WORKDIR/system.conf"
"$rauc" --conf "$FUS_WORKDIR/system.conf" info "$work_bundle" \
    > "$FUS_WORKDIR/info.readable" 2> "$FUS_WORKDIR/info.readable.err"
info_rc=$?
if [ "$info_rc" -ne 0 ]; then
    cat "$FUS_WORKDIR/info.readable.err" >&2
    fus_die 8 "signature summary: rauc info failed (exit $info_rc)"
fi
# Line labels measured on rauc 1.13 ("N Subject: ..." / "SPKI sha256: ...").
sed -n 's/^ *[0-9]* *Subject: */signature.subject=/p; s/^ *SPKI sha256: */signature.spki_sha256=/p' \
    "$FUS_WORKDIR/info.readable" > "$FUS_WORKDIR/chain"
[ -s "$FUS_WORKDIR/chain" ] || printf 'signature.chain=unavailable\n' > "$FUS_WORKDIR/chain"

# --- .info: the build evidence, a positive list ----------------------------
# Deliberately absent: key/cert paths, environment variables, host paths.
mksq_ver=$(fus_tool_version_line "$mksq" -version)
rauc_ver_raw=$(fus_tool_version_line "$rauc" --version)
{
    printf '# build evidence for %s\n' "$base"
    printf 'tool.rauc.version=%s\n' "${rauc_ver_raw:-unknown}"
    printf 'tool.mksquashfs.version=%s\n' "${mksq_ver:-unknown}"
    printf 'rauc.window=%s..%s\n' "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    printf 'const.FUS_COMPAT_PREFIX=%s\n' "$FUS_COMPAT_PREFIX"
    printf 'const.FUS_BUNDLE_FORMAT=%s\n' "$FUS_BUNDLE_FORMAT"
    printf 'const.FUS_FW_SLOT_CLASS=%s\n' "$FUS_FW_SLOT_CLASS"
    printf 'const.FUS_FW_IMAGE_HOOK=%s\n' "$FUS_FW_IMAGE_HOOK"
    printf 'const.FUS_APP_IMG_DIR=%s\n' "$FUS_APP_IMG_DIR"
    printf 'const.FUS_SIZE_ROOT_MIB=%s\n' "$FUS_SIZE_ROOT_MIB"
    printf 'source_date_epoch=%s\n' "$sde"
    # Ownership is claimed only where this tool actually packed a tree; the
    # image door never touched the payload's ownership and says nothing.
    if [ -n "$rootfs_dir" ]; then
        printf 'const.FUS_MKSQUASHFS_ARGS=%s\n' "$FUS_MKSQUASHFS_ARGS"
        printf 'ownership.build_uid=%s\n' "$FUS_BUILD_UID"
        if [ "$FUS_BUILD_UID" -eq 0 ]; then
            printf 'ownership.guard_bypassed=no\n'
        else
            printf 'ownership.guard_bypassed=yes\n'
        fi
    fi
    printf 'floor.checked=%s\n' "$floor_checked"
    [ "$floor_checked" = no ] || printf 'floor.value=%s\n' "$floor"
    printf 'version.shape_warning=%s\n' "$shape_warned"
    printf '# identity (from the self-verification)\n'
    cat "$FUS_WORKDIR/identity"
    printf '# signature chain\n'
    cat "$FUS_WORKDIR/chain"
} > "$FUS_WORKDIR/info" || fus_die 2 "cannot write the .info file"

# --- publish: bundle, then its evidence, then the latest-pointer -----------
fus_publish "$work_bundle" "$final"
fus_publish "$FUS_WORKDIR/info" "$final_info"
fus_symlink_flip "$base" "$link"

printf 'artifact=%s\n' "$final"
printf 'artifact_info=%s\n' "$final_info"
printf 'artifact_link=%s\n' "$link"
echo "result=pass"
exit 0
