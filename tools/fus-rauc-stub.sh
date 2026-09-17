#!/bin/sh
# fus-rauc-stub.sh -- THE canned rauc for the hermetic suites, installed
# into a temporary PATH by fus_test_install_rauc_stub. This file is the
# single source of the canned answer block: field names, quoting and the
# 0-based image indices mirror a measured rauc (identical on 1.13 and
# 1.15.2), which is also what fus_identity_from_shell parses -- if a future
# rauc differs, this file and that parser are corrected together, nowhere
# else. fus-test-lib.test.sh proves the single-source property via
# STUB_TAINT.
#
# Knobs (all optional):
#   STUB_RAUC_LOG      append each invocation's "$*" here
#   STUB_RAUC_VERSION  what --version reports (default 1.15.2)
#   STUB_RAUC_RC       exit code of any info call; the block is STILL
#                      printed first, which is what catches an
#                      implementation that pipes
#   STUB_CONF_COPY     copy a --conf argument's file here
#   STUB_BUNDLE_RC     exit code of the bundle verb (default 0)
#   STUB_CONTENT_LIST  write `ls` of the bundle content dir here
#   STUB_CONTENT_COPY  copy the whole bundle content dir here
#   STUB_OMIT          drop this KEY= line from the canned block
#   STUB_COMPAT / STUB_VERSION / STUB_BUILD / STUB_FORMAT / STUB_HOOKS /
#   STUB_IMAGE_NAME / STUB_IMAGE_CLASS
#                      override single canned values. STUB_HOOKS defaults to
#                      empty: a fw bundle has no bundle-level hooks (measured;
#                      only the app manifest sets one), and the default keeps
#                      the empty-but-present parser path exercised
#   STUB_IMAGES        image count: 1 (default) or 2 (adds a boot image)
#   STUB_IMAGE_HOOKS   override the per-image hook (default post-install).
#                      STUB_IMAGE_CLASS is the slot class of image 0 (default
#                      rootfs); an app bundle reports appfs there
#   STUB_REF_VERSION / STUB_REF_BUILD / STUB_REF_IMAGE_HOOKS
#                      overrides when the bundle FILENAME
#                      contains "reference" (the path is not consulted: a
#                      TMPDIR component named reference must not trigger it)
#   STUB_TAINT         corrupt the canned version: every suite consuming
#                      the block must fail -- the single-source proof
[ -n "${STUB_RAUC_LOG:-}" ] && printf '%s\n' "$*" >> "$STUB_RAUC_LOG"
case "$*" in *--version*) echo "rauc ${STUB_RAUC_VERSION-1.15.2}"; exit 0 ;; esac
_conf=''; _verb=''; _prev=''; _last=''
for _a in "$@"; do
    [ "$_last" = "--conf" ] && _conf=$_a
    case "$_a" in
    bundle|info) [ -n "$_verb" ] || _verb=$_a ;;
    esac
    _prev=$_last
    _last=$_a
done
[ -n "$_conf" ] && [ -n "${STUB_CONF_COPY:-}" ] && cp "$_conf" "$STUB_CONF_COPY"
if [ "$_verb" = "bundle" ]; then
    [ -n "${STUB_CONTENT_LIST:-}" ] && ls "$_prev" > "$STUB_CONTENT_LIST" 2>/dev/null
    [ -n "${STUB_CONTENT_COPY:-}" ] && cp -r "$_prev" "$STUB_CONTENT_COPY" 2>/dev/null
    _rc=${STUB_BUNDLE_RC:-0}
    if [ "$_rc" -ne 0 ]; then
        echo "stub-rauc: bundle failed" >&2
        exit "$_rc"
    fi
    printf 'stub bundle payload\n' > "$_last"
    exit 0
fi
case "$*" in
*--output-format=shell*)
    _ver=${STUB_VERSION-20260902}
    _build=${STUB_BUILD-20260901120000}
    _ihooks=${STUB_IMAGE_HOOKS-post-install}
    case "${_last##*/}" in
    *reference*)
        _ver=${STUB_REF_VERSION-$_ver}
        _build=${STUB_REF_BUILD-$_build}
        _ihooks=${STUB_REF_IMAGE_HOOKS-$_ihooks}
        ;;
    esac
    [ -n "${STUB_TAINT:-}" ] && _ver=0.0.0-tainted
    _block=$(cat <<INFO
RAUC_MF_COMPATIBLE='${STUB_COMPAT-fus-update-fsimx8mp}'
RAUC_MF_VERSION='$_ver'
RAUC_MF_DESCRIPTION='stub bundle for the self-tests'
RAUC_MF_BUILD='$_build'
RAUC_MF_HASH='0106ce651b3cca6f0d38a43c697b176e21620c909fd5aef67f95f1ab0b1c6c0c'
RAUC_MF_FORMAT='${STUB_FORMAT-verity}'
RAUC_MF_IMAGES='${STUB_IMAGES-1}'
RAUC_MF_HOOKS='${STUB_HOOKS-}'
RAUC_IMAGE_NAME_0='${STUB_IMAGE_NAME-fusys-image-fsimx8mp.squashfs}'
RAUC_IMAGE_CLASS_0='${STUB_IMAGE_CLASS-rootfs}'
RAUC_IMAGE_ARTIFACT_0=''
RAUC_IMAGE_VARIANT_0=''
RAUC_IMAGE_DIGEST_0='4a5b6c7d8e9f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b'
RAUC_IMAGE_SIZE_0='146800640'
RAUC_IMAGE_HOOKS_0='$_ihooks'
INFO
)
    if [ "${STUB_IMAGES-1}" = "2" ]; then
        _block="$_block
RAUC_IMAGE_NAME_1='boot.vfat'
RAUC_IMAGE_CLASS_1='boot'
RAUC_IMAGE_ARTIFACT_1=''
RAUC_IMAGE_VARIANT_1=''
RAUC_IMAGE_DIGEST_1='b007b007b007b007b007b007b007b007b007b007b007b007b007b007b007b007'
RAUC_IMAGE_SIZE_1='92274688'
RAUC_IMAGE_HOOKS_1=''"
    fi
    if [ -n "${STUB_OMIT:-}" ]; then
        printf '%s\n' "$_block" | grep -v "^${STUB_OMIT}="
    else
        printf '%s\n' "$_block"
    fi
    _rc=${STUB_RAUC_RC:-0}
    [ "$_rc" -ne 0 ] && echo "stub-rauc: verification rejected" >&2
    exit "$_rc"
    ;;
*)
    # readable info -- only the chain labels the .info extraction reads
    cat <<READABLE
Certificate Chain:
 0 Subject: O = Stub, CN = stub bundle signer
   SPKI sha256: AA:BB:CC:DD
 1 Subject: O = Stub, CN = stub CA
   SPKI sha256: EE:FF:00:11
READABLE
    _rc=${STUB_RAUC_RC:-0}
    [ "$_rc" -ne 0 ] && echo "stub-rauc: info rejected" >&2
    exit "$_rc"
    ;;
esac
