# fus-app-container.bbclass
#
# Build the container-mode application payload as a bare squashfs + verity
# SIDECAR set (no systemd-sysext, no tar packing — the files ship as direct
# RAUC bundle members). Runs as an IMAGE_POSTPROCESS_COMMAND function over
# ${IMAGE_ROOTFS} (the already-populated app tree). Container needs no
# extension-release marker (not a systemd-sysext) and no tar step (the bundle
# recipe references the 4 files directly via RAUC_SLOT_appfs[file] +
# RAUC_BUNDLE_EXTRA_FILES, not one packed artifact).
#
# Output (into ${DEPLOY_DIR_IMAGE}, flat — no subdir, so the primary slot
# image and its sidecars land at the same bundle-payload level; RAUC's
# bundle.bbclass basename-flattens the primary slot image to bundle root but
# preserves RAUC_BUNDLE_EXTRA_FILES' deploy subdir, so a flat deploy avoids a
# root-vs-subdir mismatch the install hook would otherwise have to handle):
#   <name>-<version>.squashfs          — app image
#   <name>-<version>.squashfs.verity       — dm-verity hash tree
#   <name>-<version>.squashfs.roothash     — hex root hash
#   <name>-<version>.squashfs.roothash.p7s — PKCS7 signature over the root hash (DER)
#   + stable symlinks <name>.squashfs{,.verity,.roothash,.roothash.p7s} -> versioned set
#
# Sidecar names are IMAGE-keyed (the full squashfs filename plus a suffix,
# e.g. fus-app-container.squashfs.verity) — NOT stem-keyed (fus-app-container.verity)
# — matching the already-shipped fus-app-container-runtime mount verb, which
# looks up "$img.verity"/"$img.roothash"/"$img.roothash.p7s" for
# $img = the (renamed) squashfs path.
#
# Integrity model: dm-verity is checked at RUNTIME by fus-app-container-runtime's
# `mount` verb (veritysetup open against the pinned app-purpose leaf cert),
# not by RAUC or systemd — see that recipe's do_install for the matching
# verification side (openssl smime -verify -noverify -nointern).

inherit fus-selfcheck

DEPENDS += "squashfs-tools-native cryptsetup-native openssl-native"

# Fallback name; the global default in fus-update-features.inc normally wins.
FUS_APP_CONTAINER_NAME ?= "${PN}"

# squashfs compression — same weak defaults as fus-update.bbclass,
# so every squashfs image in the layer shares one policy.
SQUASHFS_COMPRESSOR     ?= "zstd"
SQUASHFS_EXTRA_IMAGECMD ?= "-comp ${SQUASHFS_COMPRESSOR} -Xcompression-level 19"

# Signing material: FUS_APP_CONTAINER_SIGN_KEY / _CERT, defaulted in
# fus-update-features.inc next to the bundle material, because the device side
# pins the same certificate.

# Rebuild when the signing material changes (external, not a SRC_URI input).
do_image[file-checksums] += "${FUS_APP_CONTAINER_SIGN_KEY}:False ${FUS_APP_CONTAINER_SIGN_CERT}:False"

fus_app_container_build() {
    set -e

    fus_selfcheck_signing_material "fus-app-container" "${FUS_APP_CONTAINER_SIGN_KEY}" "${FUS_APP_CONTAINER_SIGN_CERT}"

    # The app payload carries its own key pair, which may be pointed at a
    # dedicated app-purpose leaf. That leaf can lag behind: production RAUC
    # material in place, the app leaf still the development one. Without this
    # the image would declare itself production and ship an app container
    # signed with a laboratory key.
    fus_selfcheck_production_material "fus-app-container" "${FUS_UPDATE_CERT_VARIANT}" \
        "${FUS_APP_CONTAINER_SIGN_KEY}" "${FUS_APP_CONTAINER_SIGN_CERT}"

    # Purpose-separation advisory: warn on a production build that still signs
    # the app with the bundle's own key (no dedicated app-signing leaf yet).
    fus_selfcheck_pki_purpose_separation "fus-app-container" \
        "${FUS_UPDATE_CERT_VARIANT}" \
        "${FUS_APP_CONTAINER_SIGN_CERT}" "${FUS_UPDATE_SIGN_CERT_FILE}"

    O="${DEPLOY_DIR_IMAGE}"
    install -d "$O"
    N="${FUS_APP_CONTAINER_NAME}-${PV}"

    # 1. squashfs (compression policy shared with the OS slots).
    mksquashfs "${IMAGE_ROOTFS}" "$O/$N.squashfs" -noappend -all-root ${SQUASHFS_EXTRA_IMAGECMD}

    # 2. dm-verity hash tree + root hash. Salt/uuid derived from the image's
    #    own sha256 (not random) for a bit-reproducible artifact.
    salt="$(sha256sum "$O/$N.squashfs" | cut -d' ' -f1)"
    uuid="$(printf '%s' "$salt" | sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/')"
    veritysetup format "$O/$N.squashfs" "$O/$N.squashfs.verity" \
        --salt="$salt" \
        --uuid="$uuid" \
        --root-hash-file="$O/$N.squashfs.roothash"

    # 3. Detached PKCS7 signature over the root hash (DER-encoded). Verified
    #    at runtime by fus-app-container-runtime's `mount` verb with
    #    `openssl smime -verify -noverify -nointern` against the pinned leaf
    #    cert (the NOINTERN|NOVERIFY discipline systemd's own image verifier
    #    uses, replicated manually here since container does its own
    #    veritysetup-based verification, not systemd's).
    openssl smime -sign -noattr -binary \
        -in "$O/$N.squashfs.roothash" \
        -inkey "${FUS_APP_CONTAINER_SIGN_KEY}" \
        -signer "${FUS_APP_CONTAINER_SIGN_CERT}" \
        -outform der -out "$O/$N.squashfs.roothash.p7s"

    # 4. Stable symlinks — what the bundle recipe (RAUC_SLOT_appfs[file] +
    #    RAUC_BUNDLE_EXTRA_FILES) actually references; bundle.bbclass
    #    dereferences symlinks when copying files into the bundle payload.
    ln -sf "$N.squashfs"             "$O/${FUS_APP_CONTAINER_NAME}.squashfs"
    ln -sf "$N.squashfs.verity"      "$O/${FUS_APP_CONTAINER_NAME}.squashfs.verity"
    ln -sf "$N.squashfs.roothash"    "$O/${FUS_APP_CONTAINER_NAME}.squashfs.roothash"
    ln -sf "$N.squashfs.roothash.p7s" "$O/${FUS_APP_CONTAINER_NAME}.squashfs.roothash.p7s"

    # 5. Build-time completeness assertion — all 4 sidecars present/non-empty
    #    before the artifact leaves the build (fus-selfcheck.bbclass catalog).
    fus_selfcheck_container_artifact "$O" "$N.squashfs"

    # 6. App-payload contract: binaries executable, app_version non-empty,
    #    app-release present with a matching identity — over the app tree
    #    (${IMAGE_ROOTFS}) this squashfs was just built from.
    fus_selfcheck_app_payload
}

IMAGE_POSTPROCESS_COMMAND += "fus_app_container_build;"
