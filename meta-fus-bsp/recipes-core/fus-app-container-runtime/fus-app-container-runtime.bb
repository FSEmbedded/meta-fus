SUMMARY = "Container app-update runtime: verity-verified loop-mount + OverlayFS merge, boot-attempt guard"
DESCRIPTION = "Runtime for the container application update mode where the app \
is a loop-mounted, dm-verity-checked squashfs file on the persistent /data \
partition (app_a.squashfs / app_b.squashfs, selected by the U-Boot \
`application` A/B variable), merged read-only via OverlayFS over \
/opt/fus-app. Container updates always ride a real reboot. This recipe owns \
the mechanism only: fs-updater \
remains the sole actor for state transitions (--commit_update / \
--rollback_update); this recipe adds the boot-attempt counter that \
guarantees a wedging app update ever reaches --rollback_update at all \
(application-only updates are not covered by U-Boot's native firmware \
bootcount, which only tracks BOOT_ORDER)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://fus-app-container-runtime \
    file://fus-app-container-bootguard.service \
    file://fus-app-container-mount.service \
"
S = "${WORKDIR}"

# allarch: shell + units + a text cert, no arch-specific content.
inherit allarch systemd fus-selfcheck

# Build-time contract test for the boot guard, host side; nothing test-related
# is installed or shipped. The harness and the predicate library live with the
# confirm recipe, which owns the door's other half, and the boot-guard cases
# need all three files at once: read them from the layer instead of unpacking
# copies here, so one set of sources gates both recipes.
CONFIRM_FILES = "${THISDIR}/../fus-update-confirm/files"
do_compile[file-checksums] += "${CONFIRM_FILES}/test-update-confirm.sh:True \
                               ${CONFIRM_FILES}/fus-update-confirm:True \
                               ${CONFIRM_FILES}/pending-state.sh:True"

do_compile() {
    sh ${CONFIRM_FILES}/test-update-confirm.sh \
        ${CONFIRM_FILES}/fus-update-confirm \
        ${CONFIRM_FILES}/pending-state.sh \
        ${WORKDIR}/fus-app-container-runtime
}

# fus-update-confirm supplies the shared pending-state library and pulls
# in fs-updater-cli; cryptsetup, openssl and libubootenv-bin serve the
# mount verb and the slot lookup.
RDEPENDS:${PN} += "systemd fus-update-confirm cryptsetup openssl-bin libubootenv-bin util-linux"

SYSTEMD_SERVICE:${PN} = " \
    fus-app-container-bootguard.service \
    fus-app-container-mount.service \
"

# verity verification cert for the app-purpose signing chain. installed
# to a dedicated path, not /etc/verity.d/ -- that is systemd's reserved
# directory, and this recipe does its own veritysetup-based verification.
VERITY_CERT ?= "${FUS_APP_CONTAINER_SIGN_CERT}"
# rebuild when the external, non-SRC_URI signing material rotates.
do_install[file-checksums] += "${VERITY_CERT}:False"

do_install() {
    fus_selfcheck_signing_material "fus-app-container-runtime (verity cert)" "${VERITY_CERT}"

    install -d ${D}${bindir}
    sed \
        -e 's|@@CONTAINER_BASE@@|${FUS_UPDATE_APP_CONTAINER_BASE}|g' \
        -e 's|@@IMG_DIR@@|${FUS_UPDATE_APP_IMG_DIR}|g' \
        -e 's|@@CURRENT@@|${FUS_UPDATE_APP_CURRENT}|g' \
        -e 's|@@OVERLAY_UPPER@@|${FUS_UPDATE_APP_OVERLAY_UPPER}|g' \
        -e 's|@@OVERLAY_WORK@@|${FUS_UPDATE_APP_OVERLAY_WORK}|g' \
        -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
        ${WORKDIR}/fus-app-container-runtime > ${D}${bindir}/fus-app-container-runtime
    chmod 0755 ${D}${bindir}/fus-app-container-runtime

    install -d ${D}${systemd_system_unitdir}
    sed \
        -e 's|@@DATA_MOUNT@@|${FUS_UPDATE_DATA_MOUNT}|g' \
        ${WORKDIR}/fus-app-container-bootguard.service \
        > ${D}${systemd_system_unitdir}/fus-app-container-bootguard.service
    sed \
        -e 's|@@DATA_MOUNT@@|${FUS_UPDATE_DATA_MOUNT}|g' \
        -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
        ${WORKDIR}/fus-app-container-mount.service \
        > ${D}${systemd_system_unitdir}/fus-app-container-mount.service
    chmod 0644 ${D}${systemd_system_unitdir}/fus-app-container-bootguard.service
    chmod 0644 ${D}${systemd_system_unitdir}/fus-app-container-mount.service

    install -d ${D}${sysconfdir}/fus-app-container
    install -m 0644 ${VERITY_CERT} ${D}${sysconfdir}/fus-app-container/verity.crt
}

FILES:${PN} += " \
    ${bindir}/fus-app-container-runtime \
    ${systemd_system_unitdir}/fus-app-container-bootguard.service \
    ${systemd_system_unitdir}/fus-app-container-mount.service \
    ${sysconfdir}/fus-app-container/verity.crt \
"
