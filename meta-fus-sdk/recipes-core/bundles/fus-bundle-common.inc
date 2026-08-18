# fus-bundle-common.inc
#
# Shared policy for every F&S RAUC bundle recipe (fus-update-bundle,
# fus-fw-bundle, fus-app-bundle): version source, bundle format, signing
# wiring + guard, the shared bundle hook script (read-back verification +
# container-mode staging + compatible override), and the OS slot definitions.
# A bundle recipe composes its RAUC_BUNDLE_SLOTS from the slot tokens;
# RAUC_SLOT_* definitions not listed there are inert (the same idiom as
# fus-app-slot.inc), so carrying the OS slots here is harmless for the
# app-only bundle.
#
# RAUC_BUNDLE_COMPATIBLE is inherited from the globally-parsed
# conf/distro/include/fus-update-features.inc so it matches the device's
# system.conf without restating it per recipe.

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit bundle fus-selfcheck

# Without the update policy the layout variables are empty, and the bundle
# class then reports an unresolved slot name -- a message that points nowhere.
# Say what is actually missing.
python __anonymous() {
    if not d.getVar("RAUC_BUNDLE_COMPATIBLE") or not d.getVar("FUS_UPDATE_DATA_MOUNT"):
        bb.fatal("fus-bundle-common.inc: the update policy is not active in this "
                 "build, so the bundle has no layout to describe -- it comes with "
                 "the fus distro family; on a foreign DISTRO require it "
                 "explicitly:\n  require conf/distro/include/fus-update-features.inc")
}

# Firmware version (single source: FUS_UPDATE_FW_VERSION, date-based YYYYMMDD)
# so the device's min-bundle-version floor can reject older bundles. Override
# the source per release to pin.
RAUC_BUNDLE_VERSION ?= "${FUS_UPDATE_FW_VERSION}"

# verity bundle format (RAUC's recommendation for new projects): a dm-verity
# hash tree over the bundle squashfs gives cryptographically verified random
# access to the images during install. Needs dm-verity + loop on the device
# (kernel: CONFIG_DM_VERITY=m, CONFIG_BLK_DEV_LOOP=y, CONFIG_SQUASHFS=y).
RAUC_BUNDLE_FORMAT = "verity"

# The shared bundle hook script: for post-install-hooked slots it re-reads the
# slot device after each write and compares its hash to the just-installed
# image, failing the install on a mismatch (requires raw slots, see
# system.conf); in container mode it also stages the app image and replaces
# the bundle-level compatible check (see fus-app-slot.inc / fus-app-bundle.bb).
# Every slot-carrying bundle ships the hook executable.
SRC_URI = "file://install-check"
RAUC_BUNDLE_HOOKS[file] = "install-check"

# Template the container app-image staging destination in the install hook from
# the layout variable, so the hook, the runtime and the lib all resolve the same
# directory from one source instead of a drifting literal. Runs after the file
# is unpacked and before bundle.bbclass's do_configure copies it into the bundle
# dir. Guarded on the file existing so a hook-less bundle stays buildable.
do_template_install_hook() {
    if [ -f "${WORKDIR}/install-check" ]; then
        sed -i "s|@@FUS_APP_IMG_DIR@@|${FUS_UPDATE_APP_IMG_DIR}|g" "${WORKDIR}/install-check"
    fi
}
addtask template_install_hook after do_unpack before do_configure

# --- OS slot definitions (inert unless listed in RAUC_BUNDLE_SLOTS) --------
# rootfs: the read-only squashfs rootfs slot image. Defaults to the evaluation
# image, which is also what makes the bundle as large as it is; a product build
# points this at its own image instead of editing this include.
FUS_BUNDLE_ROOTFS_IMAGE ?= "fusys-image-eval"
RAUC_SLOT_rootfs = "${FUS_BUNDLE_ROOTFS_IMAGE}"
RAUC_SLOT_rootfs[fstype] = "squashfs"
RAUC_SLOT_rootfs[hooks] = "post-install"

# boot: the standalone vfat boot image (kernel + DTBs + TEE), written raw to
# the BOOT_x slot (system.conf type=raw); see fus-update-boot-image.bb. In
# boot=rootfs the kernel rides the rootfs slot and FUS_BUNDLE_BOOT_SLOT is
# empty, so this definition stays inert there.
RAUC_SLOT_boot = "fus-update-boot-image"
RAUC_SLOT_boot[type] = "image"
RAUC_SLOT_boot[file] = "fus-boot-${MACHINE}.vfat"
RAUC_SLOT_boot[depends] = "fus-update-boot-image:do_deploy"
RAUC_SLOT_boot[hooks] = "post-install"

# Sign with the external dev signing material (paths from features.inc).
# Generated out of band (meta-fus-sdk/scripts/fus-update-gen-certs.sh); never committed to git.
RAUC_KEYRING_FILE ?= "${FUS_UPDATE_KEYRING_FILE}"
RAUC_KEY_FILE     ?= "${FUS_UPDATE_SIGN_KEY_FILE}"
RAUC_CERT_FILE    ?= "${FUS_UPDATE_SIGN_CERT_FILE}"

# Rebuild if the keyring changes (cert+key are already tracked by
# bundle.bbclass; the keyring is our addition).
do_bundle[file-checksums] += "${RAUC_KEYRING_FILE}:False"

# Fail with clear guidance if the signing material is absent (task-time,
# before signing), instead of a cryptic openssl error.
do_bundle:prepend() {
    fus_selfcheck_signing_material "${PN}" "${RAUC_KEY_FILE}" "${RAUC_CERT_FILE}"
    # The same variable rauc-conf checks, so it takes the same gate: the keyring
    # ships as a rootfs file, and a token URI here cannot be honoured downstream.
    fus_selfcheck_keyring_material "${PN}" "${RAUC_KEYRING_FILE}"
    fus_selfcheck_production_material "${PN}" "${FUS_UPDATE_CERT_VARIANT}" \
        "${RAUC_KEY_FILE}" "${RAUC_CERT_FILE}" "${RAUC_KEYRING_FILE}"
}
