#!/bin/sh
# fus-mk-app-bundle.sh -- build an application RAUC bundle (appfs slot,
# container mode) from a finished application directory, without Yocto and
# without bitbake. The sister tool to fus-mk-fw-bundle.sh; same structure,
# same option style, same exit-code table.
#
# There is exactly ONE source door, the directory: the three dm-verity
# sidecars are derived from the sha256 of the image THIS RUN packed, so a
# pre-built squashfs handed in from outside could not be given a sidecar set
# that provably belongs to it.
#
# No ownership guard, unlike the firmware directory door: the app payload is
# packed -all-root (FUS_APP_MKSQUASHFS_ARGS), so the packing process's uid
# never reaches the image and there is nothing to refuse. That constant is
# overridable, so the premise itself is asserted (exit 2) instead of assumed.
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
# 4 signing material or keyring unusable, 5 app tree, payload contract or
# hook unusable, 7 rauc bundle, mksquashfs, veritysetup, openssl or sha256sum
# failed, 8 self-verification failed; 1 is never assigned deliberately. A 2, 3 or 4
# can also be passed through from the self-verification child when IT could
# not run its check -- stderr names that case explicitly.
# Env twins for every option are listed in --help.
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
        'Usage: fus-mk-app-bundle.sh [options]' \
        '' \
        'Build an application RAUC bundle (appfs slot, verity format) from a' \
        'finished application directory. The tree is packed, its three' \
        'dm-verity sidecars are derived from the packed image, and all four' \
        'files plus the install-check hook become the bundle content. The' \
        'content directory is built inside the work directory in --out;' \
        'nothing is searched for and rauc is never pointed at a foreign' \
        'directory.' \
        '' \
        'Required:' \
        '  --version <v>          bundle version (semver-parsable) [FUS_VERSION]' \
        '  --out <dir>            existing output directory [FUS_OUT]' \
        '  --app-dir <dir>        the application tree to pack (the only source' \
        '                         door: the sidecars are derived from the image' \
        '                         packed here, so a pre-built squashfs cannot be' \
        '                         given a sidecar set that belongs to it)' \
        '                         [FUS_APP_DIR]' \
        '  --app-binaries <list>  space-separated executables the payload must' \
        '                         carry; each is asserted present and executable' \
        '                         in the tree. No default: the layer ships' \
        '                         fus-demo-app as its REFERENCE app, and' \
        '                         defaulting to it would let a bring-your-own-app' \
        '                         payload pass a check that measured nothing' \
        '                         about it. [FUS_APP_BINARIES]' \
        '  --app-id <id>          the identity etc/app-release must carry as' \
        '                         IMAGE_ID. No default, for the same reason.' \
        '                         [FUS_APP_ID]' \
        '  --cert <path>          signing certificate [FUS_UPDATE_CERT]' \
        '  --key <path>           signing key [FUS_UPDATE_KEY]' \
        '  --keyring <pem>        CA the device trusts; the mandatory self-' \
        '                         verification runs against it [FUS_UPDATE_KEYRING]' \
        '' \
        'Options:' \
        '  --certs <dir>          shorthand for <dir>/sign.cert.pem + <dir>/sign.key.pem' \
        '                         [FUS_UPDATE_CERT_DIR]' \
        '  --verity-cert <path>   certificate that signs the verity root hash; the' \
        '                         device must pin this one (default: --cert)' \
        '                         [FUS_APP_CONTAINER_SIGN_CERT]' \
        '  --verity-key <path>    its key (default: --key) [FUS_APP_CONTAINER_SIGN_KEY]' \
        '  --machine <m>          machine name (default fsimx8mp) [FUS_MACHINE]' \
        '  --compatible <s>       override the full compatible string; the default' \
        '                         is <prefix><machine><app-suffix>, and the -appfs' \
        '                         suffix is what the install-check bundle hook' \
        '                         accepts on the device [FUS_COMPATIBLE]' \
        '  --hook <file>          hook script (default install-check next to this' \
        '                         script). A replacement must serve BOTH stages' \
        '                         this manifest declares: the install-check' \
        '                         bundle hook and the appfs slot-install hook.' \
        '                         [FUS_HOOK]' \
        '  --build-stamp <s>      build stamp (default UTC now) [FUS_BUILD_STAMP]' \
        '  --description <s>      manifest description [FUS_DESCRIPTION]' \
        '  --source-date-epoch <n>  reproducibility epoch (default: the mtime of' \
        '                         the application directory) [SOURCE_DATE_EPOCH]' \
        '  --expect-rauc <v>      warn when the resolved rauc version differs' \
        '  --require-rauc <v>     exit 3 when the resolved rauc version differs' \
        '  --dry-run              run all preflights, print the manifest, build' \
        '                         nothing' \
        '  --check-tools          resolve every tool, print versions and the' \
        '                         measured rauc window, exit 0 (or 3)' \
        '  --help                 this text' \
        '' \
        'Signing material: file paths only. Unlike the firmware door, a pkcs11:' \
        'URI is REFUSED here -- this tool signs the verity root hash with' \
        'openssl itself, which cannot take a URI without an engine/provider' \
        'setup this tool does not build.' \
        '' \
        'The application payload is packed -all-root, so no ownership guard' \
        'applies and no root privileges are needed. FUS_APP_MKSQUASHFS_ARGS' \
        'must therefore keep -all-root; without it the build is refused (2).' \
        '' \
        'Artifacts in --out:' \
        '  ext-fus-app-bundle-<machine>-<version>-<stamp>.raucb (+ .info beside it)' \
        '  ext-fus-app-bundle-<machine>.raucb -> symlink to the newest build' \
        '' \
        'Exit codes: 0 ok, 2 usage, 3 tool, 4 signing material, 5 app tree,' \
        'payload contract or hook, 7 rauc bundle/mksquashfs/veritysetup/' \
        'openssl/sha256sum failed, 8 self-verification failed. A 1 is a' \
        'script defect, never a verdict.'
}

version="${FUS_VERSION:-}"
out="${FUS_OUT:-}"
app_dir="${FUS_APP_DIR:-}"
app_binaries="${FUS_APP_BINARIES:-}"
app_id="${FUS_APP_ID:-}"
cert="${FUS_UPDATE_CERT:-}"
key="${FUS_UPDATE_KEY:-}"
keyring="${FUS_UPDATE_KEYRING:-}"
certs_dir="${FUS_UPDATE_CERT_DIR:-}"
verity_cert="${FUS_APP_CONTAINER_SIGN_CERT:-}"
verity_key="${FUS_APP_CONTAINER_SIGN_KEY:-}"
machine="${FUS_MACHINE:-fsimx8mp}"
compatible="${FUS_COMPATIBLE:-}"
hook="${FUS_HOOK:-}"
stamp="${FUS_BUILD_STAMP:-}"
description="${FUS_DESCRIPTION:-}"
sde="${SOURCE_DATE_EPOCH:-}"
expect_rauc=''; require_rauc=''; dry_run=0; check_tools=0

while [ $# -gt 0 ]; do
    case "$1" in
    --help)
        usage
        exit 0 ;;
    --check-tools) check_tools=1 ;;
    --dry-run)     dry_run=1 ;;
    --version|--out|--app-dir|--app-binaries|--app-id|--cert|--key|--keyring|--certs|--verity-cert|--verity-key|--machine|--compatible|--hook|--build-stamp|--description|--source-date-epoch|--expect-rauc|--require-rauc)
        [ $# -ge 2 ] || fus_die 2 "option $1 requires a value"
        case "$1" in
        --version)           version=$2 ;;
        --out)               out=$2 ;;
        --app-dir)           app_dir=$2 ;;
        --app-binaries)      app_binaries=$2 ;;
        --app-id)            app_id=$2 ;;
        --cert)              cert=$2 ;;
        --key)               key=$2 ;;
        --keyring)           keyring=$2 ;;
        --certs)             certs_dir=$2 ;;
        --verity-cert)       verity_cert=$2 ;;
        --verity-key)        verity_key=$2 ;;
        --machine)           machine=$2 ;;
        --compatible)        compatible=$2 ;;
        --hook)              hook=$2 ;;
        --build-stamp)       stamp=$2 ;;
        --description)       description=$2 ;;
        --source-date-epoch) sde=$2 ;;
        --expect-rauc)       expect_rauc=$2 ;;
        --require-rauc)      require_rauc=$2 ;;
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
    # mksquashfs is the one launched BY NAME (by rauc, over the PATH prefix
    # built from the resolved path); veritysetup, openssl and sha256sum are
    # only ever invoked by path from here.
    fus_tools_report rauc FUS_RAUC rauc - \
        mksquashfs FUS_MKSQUASHFS squashfs-tools byname \
        veritysetup FUS_VERITYSETUP cryptsetup-bin - \
        openssl FUS_OPENSSL openssl - \
        sha256sum FUS_SHA256SUM coreutils -
    ct_rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
    ct_ver=$(fus_rauc_version "$ct_rauc")
    printf 'rauc.version=%s\n' "${ct_ver:-unknown}"
    printf 'rauc.window=%s..%s\n' "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    fus_rauc_version_gate "$ct_rauc" "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    exit 0
fi

# --- usage (2) -------------------------------------------------------------
[ -n "$version" ] || fus_die 2 "--version is required (no date default)"
fus_check_semver "$version"
shape_warned=no
fus_check_version_shape "$version" || shape_warned=yes

[ -n "$out" ] || fus_die 2 "--out is required"
[ -d "$out" ] || fus_die 2 "--out does not exist (it is not created; this catches typos): $out"

[ -n "$app_dir" ] || fus_die 2 "--app-dir is required: the application tree is the only source door"
# The two contract inputs are demanded, never defaulted. The layer's own
# default (fus-demo-app for both) belongs to its REFERENCE application; a
# general tool inheriting it would hand a bring-your-own-app payload a green
# contract check that measured nothing about the caller's app -- and the id
# mismatch is exactly the class the contract exists to catch.
[ -n "$app_binaries" ] || fus_die 2 \
    "--app-binaries is required: the executables the payload must carry have no sensible default"
[ -n "$app_id" ] || fus_die 2 \
    "--app-id is required: the identity etc/app-release must carry has no sensible default"

# This door carries no uid guard, and the ONLY reason it needs none is that
# the payload is flattened to uid 0. The constant is overridable, so the
# premise is checked rather than assumed -- otherwise a single environment
# variable ships the builder's ownership with nothing refusing it.
fus_args_contain "$FUS_APP_MKSQUASHFS_ARGS" -all-root || fus_die 2 \
    "FUS_APP_MKSQUASHFS_ARGS lacks -all-root: the app payload would keep the packing uid/gid, and this door has no ownership guard because it relies on -all-root"

[ -n "$keyring" ] || fus_die 2 "--keyring is required; self-verification is not optional"
[ -f "$keyring" ] || fus_die 2 "keyring: no such file (path withheld; check --keyring)"
# A dedicated verity pair comes whole: half of one would sign with a
# mismatched key and fail only at the signing step, mid-build.
case "${verity_cert:+c}${verity_key:+k}" in
c|k) fus_die 2 "--verity-cert and --verity-key go together (FUS_APP_CONTAINER_SIGN_CERT/_KEY)" ;;
esac

case "$machine" in ''|*/*) fus_die 2 "unusable machine name" ;; esac

# The payload name is a constant here, not an option -- but every constant in
# the library is overridable from the environment, and an override is the one
# way this name can go wrong. A name carrying a '/' would write outside the
# content directory, and one colliding with a reserved bundle entry would be
# overwritten by the hook or the manifest a few lines later: the bundle would
# build, publish and then fail on the device. The firmware door guards its
# --payload-name the same way.
case "$FUS_APP_PAYLOAD_NAME" in
''|*/*) fus_die 2 "FUS_APP_PAYLOAD_NAME must be a plain filename: '$FUS_APP_PAYLOAD_NAME'" ;;
install-check|manifest.raucm) fus_die 2 "FUS_APP_PAYLOAD_NAME collides with a reserved bundle entry: $FUS_APP_PAYLOAD_NAME" ;;
esac

[ -n "$stamp" ] || stamp=$(date -u +%Y%m%d%H%M%S)
case "$stamp" in ''|*/*) fus_die 2 "unusable build stamp" ;; esac

if [ -n "$sde" ]; then
    case "$sde" in ''|*[!0-9]*) fus_die 2 "--source-date-epoch must be a decimal epoch" ;; esac
fi

# The -appfs suffix is not decoration: rauc compares a bundle's compatible to
# the device's for exact equality, and the app bundle's own install-check
# bundle hook is what accepts the suffixed form instead.
[ -n "$compatible" ] || compatible="${FUS_COMPAT_PREFIX}${machine}${FUS_APP_COMPAT_SUFFIX}"
# An override that drops the suffix builds and self-verifies happily -- the
# self-verification compares the manifest against the very same variable --
# and is then refused by the bundle's own install-check hook ON THE DEVICE,
# which accepts exactly the suffixed form. Warned rather than refused, like
# the fw door's off-glob payload name: deliberately building a bundle the
# device must reject is a legitimate bench lever.
compat_warned=no
case "$compatible" in
*"$FUS_APP_COMPAT_SUFFIX") : ;;
*)
    printf '%s\n' "${0##*/}: WARNING: compatible '$compatible' does not end in '$FUS_APP_COMPAT_SUFFIX'; the bundle's own install-check hook accepts only the suffixed form, so the device will reject this bundle" >&2
    compat_warned=yes ;;
esac
[ -n "$description" ] || description="$FUS_APP_DESCRIPTION"
[ -n "$hook" ] || hook="$SCRIPT_DIR/install-check"

base="ext-fus-app-bundle-$machine-$version-$stamp.raucb"
final="${out%/}/$base"
final_info="$final.info"
link="${out%/}/ext-fus-app-bundle-$machine.raucb"
# Refuse before any work, not only at publish time: a stamped artifact is
# never overwritten.
[ ! -e "$final" ] || fus_die 2 "artifact already exists, not overwriting: $final"
[ ! -e "$final_info" ] || fus_die 2 "artifact info already exists, not overwriting: $final_info"

# --- tools (3) -------------------------------------------------------------
rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
mksq=$(fus_tool_resolve mksquashfs FUS_MKSQUASHFS squashfs-tools byname) || exit $?
veritysetup=$(fus_tool_resolve veritysetup FUS_VERITYSETUP cryptsetup-bin) || exit $?
openssl=$(fus_tool_resolve openssl FUS_OPENSSL openssl) || exit $?
sha256=$(fus_tool_resolve sha256sum FUS_SHA256SUM coreutils) || exit $?
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
[ -n "$verity_cert" ] || verity_cert=$cert
[ -n "$verity_key" ] || verity_key=$key
# Refused here, not left to openssl: this door signs the verity roothash with
# openssl smime itself, and a pkcs11 URI would reach it as a filename and
# fail with a confusing "no such file" one step into the build. The firmware
# door has no such restriction -- there only rauc ever touches the key.
for _c in "$cert" "$verity_cert"; do
    case "$_c" in
    pkcs11:*) fus_die 4 "signing certificate: a pkcs11 URI is not usable in this door -- the verity roothash signature is made with openssl here, which needs a certificate file" ;;
    esac
done
for _k in "$key" "$verity_key"; do
    case "$_k" in
    pkcs11:*) fus_die 4 "signing key: a pkcs11 URI is not usable in this door -- the verity roothash signature is made with openssl here, which needs a key file" ;;
    esac
done
fus_require_signing "$cert" "$key"
if [ "$verity_cert" != "$cert" ] || [ "$verity_key" != "$key" ]; then
    [ -f "$verity_cert" ] && [ -r "$verity_cert" ] ||
        fus_die 4 "verity certificate: not a readable file (path withheld; check --verity-cert)"
    [ -f "$verity_key" ] && [ -r "$verity_key" ] ||
        fus_die 4 "verity key: not a readable file (path withheld; check --verity-key)"
fi
[ -r "$keyring" ] && [ -s "$keyring" ] || fus_die 4 "keyring: unreadable or empty (path withheld)"

# --- the app tree and its payload contract (5) -----------------------------
[ -d "$app_dir" ] || fus_die 5 "application directory not found: $app_dir"
# Both bits, and named apart from "empty": an unlistable or untraversable
# tree would otherwise reach the emptiness check below and be reported as
# empty, which is a different finding entirely.
[ -r "$app_dir" ] && [ -x "$app_dir" ] || \
    fus_die 5 "application directory is not readable and traversable: $app_dir"
# An empty tree packs into a valid but useless squashfs; the device would
# mount nothing. The listing is captured into the test, not piped: its
# emptiness is the verdict, never a command's exit status.
[ -n "$(ls -A "$app_dir" 2>/dev/null)" ] || \
    fus_die 5 "application directory is empty: $app_dir"

app_payload_contract() { # app_payload_contract <tree> <binaries> <app-id>
    # fus_selfcheck_app_payload (fus-selfcheck.bbclass), as a preflight before
    # anything is packed. Three guards, each catching a class that otherwise
    # only surfaces in the field. Files are located BY NAME rather than at a
    # fixed path, exactly as the reference does: the install prefix differs
    # between app modes, and a hardcoded etc/... would false-fire.
    # find's output is the verdict here, never its exit status -- a search
    # that could not run reads as "not found", which is the same refusal.
    # shellcheck disable=SC2086  # the binary list is a word list on purpose
    for _apc_bin in $2; do
        _apc_p=$(find "$1" -type f -name "$_apc_bin" -perm -u+x 2>/dev/null | sed -n 1p)
        [ -n "$_apc_p" ] || fus_die 5 \
            "app binary '$_apc_bin' not found as an executable file in the application tree: the app payload would ship with no program to run (--app-binaries lists the executables an app image must carry)"
    done
    _apc_ver=$(find "$1" -type f -name app_version 2>/dev/null | sed -n 1p)
    if [ -z "$_apc_ver" ] || [ ! -s "$_apc_ver" ]; then
        fus_die 5 \
            "etc/app_version missing or empty in the application tree: the app-only update path reports the running app version from it across a slot switch"
    fi
    _apc_rel=$(find "$1" -type f -name app-release 2>/dev/null | sed -n 1p)
    [ -n "$_apc_rel" ] || fus_die 5 \
        "etc/app-release missing in the application tree: the app payload must ship its self-describing metadata"
    # The LAST IMAGE_ID line wins, as the reference's `tail -n1` does: a file
    # with two of them must be judged identically here and in the build, or a
    # payload one side accepts the other rejects.
    _apc_id=$(sed -n 's/^IMAGE_ID=\(.*\)$/\1/p' "$_apc_rel" | sed -n '$p')
    [ "$_apc_id" = "$3" ] || fus_die 5 \
        "etc/app-release IMAGE_ID='$_apc_id' does not match the configured app id '$3' (--app-id): the metadata must identify the app it ships"
}
app_payload_contract "$app_dir" "$app_binaries" "$app_id"

fus_require_file "$hook" 5 "hook not found or not readable: $hook"

# No size guard here, deliberately: FUS_SIZE_ROOT_MIB is the rootfs SLOT
# limit, and container mode's appfs is a mounted directory on the data
# partition, not a fixed raw slot. There is no measured app limit to check
# against, and inventing one would refuse builds on a number nobody measured.

# The epoch defaults to the source tree's own mtime, the same rule as the fw
# door. It is NOT what the image recipe used: the deployed container was
# packed with OE's SOURCE_DATE_EPOCH_FALLBACK, so reproducing those bytes
# needs an explicit --source-date-epoch, never this default.
[ -n "$sde" ] || sde=$(stat -Lc %Y "$app_dir" 2>/dev/null) || \
    fus_die 5 "cannot read the application directory mtime for SOURCE_DATE_EPOCH"

# --- dry run: all preflights done, print the manifest, build nothing -------
if [ "$dry_run" -eq 1 ]; then
    fus_manifest_begin "$compatible" "$version" "$description" "$stamp" \
        "$FUS_BUNDLE_FORMAT" install-check "$FUS_APP_BUNDLE_HOOK"
    fus_manifest_image "$FUS_APP_SLOT_CLASS" "$FUS_APP_PAYLOAD_NAME" "$FUS_APP_IMAGE_HOOK"
    exit 0
fi

# --- build -----------------------------------------------------------------
fus_workdir "$out"
content="$FUS_WORKDIR/content"
mkdir "$content" || fus_die 2 "cannot create the content directory"

# Packed STRAIGHT into the content directory, so the sidecars written beside
# the image land there too, under the image-keyed names the device's mount
# verb looks up. No copy step, and no way to publish a bundle whose sidecars
# were built from some other image.
payload="$content/$FUS_APP_PAYLOAD_NAME"
fus_squashfs_from_dir "$app_dir" "$payload" "$mksq" \
    "$sde" "$FUS_WORKDIR/mksquashfs.log" "$FUS_APP_MKSQUASHFS_ARGS"
fus_verity_sidecars "$payload" "$verity_cert" "$verity_key" \
    "$veritysetup" "$openssl" "$sha256" "$FUS_WORKDIR/sidecars.log"

fus_install_hook "$hook" "$content/install-check" "$FUS_APP_IMG_DIR"

{
    fus_manifest_begin "$compatible" "$version" "$description" "$stamp" \
        "$FUS_BUNDLE_FORMAT" install-check "$FUS_APP_BUNDLE_HOOK"
    fus_manifest_image "$FUS_APP_SLOT_CLASS" "$FUS_APP_PAYLOAD_NAME" "$FUS_APP_IMAGE_HOOK"
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
    case "$verify_rc" in
    2|3|4) fus_die "$verify_rc" "self-verification could not run (verify exit $verify_rc)" ;;
    esac
    fus_die 3 "self-verification tool could not be executed (exit $verify_rc)"
fi

# The wiring this door exists to add is NOT covered by the verify child: it
# can pin compatible, version and format, and nothing else. A bundle whose
# [hooks] verb, image hook or image filename had drifted would verify clean,
# publish, and only fail on the device -- so the three fields are compared
# here, against the identity the child just wrote from `rauc info`. Fixed
# strings (-F) and whole lines (-x): the keys contain dots, and a substring
# match would accept image.appfs.hooks=install-something.
grep -qxF "hooks=$FUS_APP_BUNDLE_HOOK" "$FUS_WORKDIR/identity" || fus_die 8 \
    "self-verification: the bundle declares no '$FUS_APP_BUNDLE_HOOK' bundle hook; without it rauc applies its own compatible check and the device refuses the '$FUS_APP_COMPAT_SUFFIX' suffix"
# The two checks below are keyed on the appfs section, so a payload rauc
# reports under another slot class would trip them with the payload-name
# message -- the wrong cause. The missing section is refused on its own terms.
grep -q "^image\\.$FUS_APP_SLOT_CLASS\\." "$FUS_WORKDIR/identity" || fus_die 8 \
    "self-verification: the bundle carries no '$FUS_APP_SLOT_CLASS' image; rauc reports the payload under a different slot class, so the device's $FUS_APP_SLOT_CLASS slot would stay unwritten"
grep -qxF "image.$FUS_APP_SLOT_CLASS.filename=$FUS_APP_PAYLOAD_NAME" "$FUS_WORKDIR/identity" || fus_die 8 \
    "self-verification: the bundle's $FUS_APP_SLOT_CLASS image is not named '$FUS_APP_PAYLOAD_NAME'; the install hook's sidecar lookup is keyed on that name"
grep -qxF "image.$FUS_APP_SLOT_CLASS.hooks=$FUS_APP_IMAGE_HOOK" "$FUS_WORKDIR/identity" || fus_die 8 \
    "self-verification: the bundle's $FUS_APP_SLOT_CLASS image carries no '$FUS_APP_IMAGE_HOOK' hook; rauc does not write this slot itself, so nothing would stage the payload"

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
# The verity salt IS the payload digest, so recording payload.sha256 and the
# derived uuid/root hash makes a rebuild's reproducibility checkable without
# unpacking the bundle again.
mksq_ver=$(fus_tool_version_line "$mksq" -version)
rauc_ver_raw=$(fus_tool_version_line "$rauc" --version)
vs_ver=$(fus_tool_version_line "$veritysetup" --version)
ssl_ver=$(fus_tool_version_line "$openssl" version)
sha_ver=$(fus_tool_version_line "$sha256" --version)
{
    printf '# build evidence for %s\n' "$base"
    printf 'tool.rauc.version=%s\n' "${rauc_ver_raw:-unknown}"
    printf 'tool.mksquashfs.version=%s\n' "${mksq_ver:-unknown}"
    printf 'tool.veritysetup.version=%s\n' "${vs_ver:-unknown}"
    printf 'tool.openssl.version=%s\n' "${ssl_ver:-unknown}"
    # The salt contract rests on this one: the verity salt IS whatever this
    # binary printed for the packed image, so its identity belongs in the
    # evidence beside the digest it produced.
    printf 'tool.sha256sum.version=%s\n' "${sha_ver:-unknown}"
    printf 'rauc.window=%s..%s\n' "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    printf 'const.FUS_COMPAT_PREFIX=%s\n' "$FUS_COMPAT_PREFIX"
    printf 'const.FUS_APP_COMPAT_SUFFIX=%s\n' "$FUS_APP_COMPAT_SUFFIX"
    printf 'const.FUS_BUNDLE_FORMAT=%s\n' "$FUS_BUNDLE_FORMAT"
    printf 'const.FUS_APP_SLOT_CLASS=%s\n' "$FUS_APP_SLOT_CLASS"
    printf 'const.FUS_APP_IMAGE_HOOK=%s\n' "$FUS_APP_IMAGE_HOOK"
    printf 'const.FUS_APP_BUNDLE_HOOK=%s\n' "$FUS_APP_BUNDLE_HOOK"
    printf 'const.FUS_APP_PAYLOAD_NAME=%s\n' "$FUS_APP_PAYLOAD_NAME"
    printf 'const.FUS_APP_IMG_DIR=%s\n' "$FUS_APP_IMG_DIR"
    printf 'const.FUS_APP_MKSQUASHFS_ARGS=%s\n' "$FUS_APP_MKSQUASHFS_ARGS"
    printf 'source_date_epoch=%s\n' "$sde"
    printf 'app.id=%s\n' "$app_id"
    printf 'app.binaries=%s\n' "$app_binaries"
    printf 'payload.sha256=%s\n' "$FUS_VERITY_SALT"
    printf 'verity.uuid=%s\n' "$FUS_VERITY_UUID"
    printf 'verity.roothash=%s\n' "$FUS_VERITY_ROOTHASH"
    printf 'version.shape_warning=%s\n' "$shape_warned"
    printf 'compatible.suffix_warning=%s\n' "$compat_warned"
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
