#!/bin/sh
# fus-verify-bundle.sh -- verify a RAUC bundle without a build system.
#
# There is exactly ONE verification mode, and it always runs under a
# generated minimal system.conf carrying the device's certificate rules
# (check-purpose=codesign, use-bundle-signing-time=true). A configuration-
# free `rauc info --keyring` cannot verify these bundles: rauc's default
# certificate purpose is stricter than codesign and rejects the signing
# leaf (measured: "unsuitable certificate purpose"). The output therefore
# never suggests a configuration-free stage.
#
# Output: key=value on stdout, diagnostics on stderr.
# Exit codes: 0 ok, 2 usage, 3 tool missing, 4 keyring unusable,
# 8 verification failed, 10 version/floor policy violated; 1 is never
# assigned deliberately.
# Env: FUS_RAUC overrides the rauc binary; TMPDIR hosts the work directory.
set -u

# Builtins only until the tools are resolved: an emptied PATH has to end in
# exit 3 naming rauc, not in an unrelated failure from dirname or mktemp.
case "$0" in
*/*) _self_dir=${0%/*} ;;
*)   _self_dir=. ;;
esac
SCRIPT_DIR=$(CDPATH='' cd -- "$_self_dir" && pwd) || {
    printf '%s\n' "${0##*/}: cannot resolve the script directory" >&2
    exit 3
}
[ -f "$SCRIPT_DIR/fus-bundle-lib.sh" ] || {
    printf '%s\n' "${0##*/}: fus-bundle-lib.sh not found next to this script (the tool set is copied as one directory)" >&2
    exit 3
}
# shellcheck disable=SC1091
. "$SCRIPT_DIR/fus-bundle-lib.sh"

usage() {
    printf '%s\n' \
        'Usage: fus-verify-bundle.sh [options] <bundle.raucb>' \
        '' \
        'Verify a RAUC bundle the way the device would: signature chain against' \
        '--keyring under a generated minimal system.conf with' \
        'check-purpose=codesign and use-bundle-signing-time=true. There is no' \
        'configuration-free mode -- without these rules rauc rejects the signing' \
        'certificate outright ("unsuitable certificate purpose").' \
        '' \
        'Options:' \
        '  --keyring <pem>          CA the device trusts (required; no default,' \
        '                           no derivation from any certificate directory)' \
        '  --expect-compatible <s>  exit 8 unless the manifest compatible equals <s>' \
        '  --expect-version <v>     exit 8 unless the manifest version equals <v>' \
        '  --expect-format <s>      exit 8 unless the bundle format equals <s>' \
        '  --floor <v>              exit 10 unless bundle version >= <v> (equality' \
        '                           passes, as on the device)' \
        '  --reference <bundle>     exit 8 unless compatible/version/format/hooks and' \
        '                           every image filename/sha256/size/hooks match' \
        '                           the reference; build may differ' \
        '  --identity-out <file>    write the machine-readable identity to <file>' \
        '  --check-tools            resolve the tools this script needs, print' \
        '                           paths and versions, exit 0 (or 3 when missing)' \
        '  --help                   this text' \
        '' \
        'Output is key=value on stdout (verify=pass, purpose=codesign, the' \
        'bundle identity, one line per requested check, result=pass),' \
        'diagnostics on stderr.' \
        '' \
        'Exit codes: 0 ok, 2 usage, 3 tool missing, 4 keyring unusable,' \
        '8 verification failed, 10 version/floor policy violated. A 1 is a' \
        'script defect, never a verdict.' \
        '' \
        'Environment: FUS_RAUC overrides the rauc binary; TMPDIR hosts the' \
        'work directory.'
}

bundle=''; keyring=''; expect_compatible=''; expect_version=''
expect_format=''; floor=''; reference=''; identity_out=''; check_tools=0

while [ $# -gt 0 ]; do
    case "$1" in
    --help)
        usage
        exit 0 ;;
    --check-tools)
        check_tools=1 ;;
    --keyring|--expect-compatible|--expect-version|--expect-format|--floor|--reference|--identity-out)
        [ $# -ge 2 ] || fus_die 2 "option $1 requires a value"
        case "$1" in
        --keyring)           keyring=$2 ;;
        --expect-compatible) expect_compatible=$2 ;;
        --expect-version)    expect_version=$2 ;;
        --expect-format)     expect_format=$2 ;;
        --floor)             floor=$2 ;;
        --reference)         reference=$2 ;;
        --identity-out)      identity_out=$2 ;;
        esac
        shift ;;
    -*)
        fus_die 2 "unknown option: $1 (see --help)" ;;
    *)
        [ -z "$bundle" ] || fus_die 2 "more than one bundle operand: '$bundle' and '$1'"
        bundle=$1 ;;
    esac
    shift
done

if [ "$check_tools" -eq 1 ]; then
    # The job preflight: report first, so a CI log shows what was found, then
    # enforce the measured window (under the minimum -> 3, above -> warning).
    fus_tools_report rauc FUS_RAUC rauc -
    ct_rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
    ct_ver=$(fus_rauc_version "$ct_rauc")
    printf 'rauc.version=%s\n' "${ct_ver:-unknown}"
    printf 'rauc.window=%s..%s\n' "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    fus_rauc_version_gate "$ct_rauc" "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"
    exit 0
fi

# A missing or unreadable input is a usage error (2), never a verification
# verdict (8): none of these checks says anything about a bundle.
[ -n "$bundle" ] || fus_die 2 "no bundle given (see --help)"
fus_require_file "$bundle" 2 "bundle not found or not readable: $bundle"

[ -n "$keyring" ] || fus_die 2 "--keyring is required; there is no default and no derivation"
# Key/cert paths never appear in output that can end up in a CI log.
[ -f "$keyring" ] || fus_die 2 "keyring: no such file (path withheld; check --keyring)"
[ -r "$keyring" ] && [ -s "$keyring" ] || fus_die 4 "keyring: unreadable or empty (path withheld)"

[ -z "$reference" ] || \
    fus_require_file "$reference" 2 "reference bundle not found or not readable: $reference"

if [ -n "$identity_out" ]; then
    case "$identity_out" in
    */*) identity_out_dir=${identity_out%/*} ;;
    *)   identity_out_dir=. ;;
    esac
    [ -d "$identity_out_dir" ] || \
        fus_die 2 "identity-out directory does not exist: $identity_out_dir"
fi

# Version arguments get a shape warning on top of the semver check: a
# semver-small value against date-shaped bundle versions is the typo the
# device reports worst.
[ -z "$floor" ] || { fus_check_semver "$floor"; fus_check_version_shape "$floor"; }
[ -z "$expect_version" ] || fus_check_version_shape "$expect_version"

rauc=$(fus_tool_resolve rauc FUS_RAUC rauc) || exit $?
fus_rauc_version_gate "$rauc" "$FUS_RAUC_MIN" "$FUS_RAUC_MAX_TESTED"

fus_workdir "${TMPDIR:-/tmp}"

# The compatible check further down is this script's own comparison: `info`
# reports the field, the configuration does not enforce it.
keyring_abs=$(fus_abspath "$keyring")
conf="$FUS_WORKDIR/system.conf"
fus_write_verify_conf "$keyring_abs" "$conf"

# The verification; it also yields the parsed identity for every later check.
identity_file="$FUS_WORKDIR/identity"
fus_bundle_identity "$bundle" "$rauc" "$conf" "$FUS_WORKDIR" verify > "$identity_file"
echo "verify=pass"
echo "purpose=codesign"

# The bundle's identity, as parsed from the verification run.
cat "$identity_file"

compatible_val=$(sed -n 's/^compatible=//p' "$identity_file")
version_val=$(sed -n 's/^version=//p' "$identity_file")
format_val=$(sed -n 's/^format=//p' "$identity_file")

if [ -n "$expect_compatible" ]; then
    [ "$compatible_val" = "$expect_compatible" ] || fus_die 8 \
        "expectation failed: compatible is '$compatible_val', expected '$expect_compatible'"
    echo "expect_compatible=pass"
fi
if [ -n "$expect_version" ]; then
    [ "$version_val" = "$expect_version" ] || fus_die 8 \
        "expectation failed: version is '$version_val', expected '$expect_version'"
    echo "expect_version=pass"
fi
if [ -n "$expect_format" ]; then
    [ "$format_val" = "$expect_format" ] || fus_die 8 \
        "expectation failed: format is '$format_val', expected '$expect_format'"
    echo "expect_format=pass"
fi

if [ -n "$floor" ]; then
    fus_check_floor "$version_val" "$floor"
    echo "floor=pass"
fi

if [ -n "$reference" ]; then
    ref_identity="$FUS_WORKDIR/identity.ref"
    fus_bundle_identity "$reference" "$rauc" "$conf" "$FUS_WORKDIR" reference > "$ref_identity"
    # Manifest diff: compatible, version, format, hooks and every image's
    # filename/sha256/size/hooks must match; build may differ.
    sed '/^build=/d' "$identity_file" > "$FUS_WORKDIR/diff.bundle"
    sed '/^build=/d' "$ref_identity"  > "$FUS_WORKDIR/diff.ref"
    mismatch=0
    while IFS= read -r ref_line; do
        ref_key=${ref_line%%=*}
        ref_want=${ref_line#*=}
        # ref_key (a manifest-derived key such as image.<class>.filename) is a
        # BRE search pattern here, not a literal -- an unescaped '.' matches any
        # character, so a slot class carrying a regex metacharacter could make
        # this match the wrong line and pass a real drift as reference=match.
        ref_key_esc=$(printf '%s\n' "$ref_key" | \
            sed -e 's/\\/\\\\/g' -e 's/\./\\./g' -e 's/\*/\\*/g' \
                -e 's/\[/\\[/g' -e 's/\^/\\^/g' -e 's/\$/\\$/g')
        got=$(sed -n "s/^$ref_key_esc=//p" "$FUS_WORKDIR/diff.bundle" | sed -n 1p)
        if [ "$got" != "$ref_want" ]; then
            printf '%s\n' \
                "reference mismatch: $ref_key: bundle '$got' vs reference '$ref_want'" >&2
            mismatch=1
        fi
    done < "$FUS_WORKDIR/diff.ref"
    bundle_lines=$(wc -l < "$FUS_WORKDIR/diff.bundle")
    ref_lines=$(wc -l < "$FUS_WORKDIR/diff.ref")
    if [ "$bundle_lines" -ne "$ref_lines" ]; then
        printf '%s\n' \
            "reference mismatch: different field sets ($bundle_lines vs $ref_lines lines)" >&2
        mismatch=1
    fi
    [ "$mismatch" -eq 0 ] || fus_die 8 "reference: manifest differs from the reference bundle"
    echo "reference=match"
fi

if [ -n "$identity_out" ]; then
    identity_tmp="$identity_out_dir/.fus-identity.$$"
    cat "$identity_file" > "$identity_tmp" || fus_die 2 "cannot write the identity file"
    mv "$identity_tmp" "$identity_out" || fus_die 2 "cannot move the identity file into place"
    echo "identity_out=$identity_out"
fi

echo "result=pass"
exit 0
