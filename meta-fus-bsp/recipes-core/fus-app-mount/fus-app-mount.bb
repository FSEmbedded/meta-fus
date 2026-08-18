SUMMARY = "Mount the active A/B application slot read-only at the app mount point"
DESCRIPTION = "A oneshot systemd service that resolves the booted A/B slot from \
the active rootfs partition label and mounts the matching application slot \
(App_A/App_B) read-only at the app mount point. Partition identity and the \
mount point come from conf/include/fus-update-layout.inc."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fus-app-mount file://fus-app-mount.service"
S = "${WORKDIR}"

inherit systemd allarch

SYSTEMD_SERVICE:${PN} = "fus-app-mount.service"
SYSTEMD_AUTO_ENABLE = "enable"

# Runtime tools: blkid resolves the PARTLABEL; mount/awk/readlink/logger/
# mountpoint come from busybox.
RDEPENDS:${PN} = "util-linux-blkid"

FILES:${PN} = "${sbindir}/fus-app-mount ${systemd_system_unitdir}/fus-app-mount.service"

do_install() {
    install -d ${D}${sbindir}
    sed \
        -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
        -e 's|@@ROOT_A@@|${FUS_UPDATE_PARTLABEL_ROOT_A}|g' \
        -e 's|@@ROOT_B@@|${FUS_UPDATE_PARTLABEL_ROOT_B}|g' \
        -e 's|@@APP_A@@|${FUS_UPDATE_PARTLABEL_APP_A}|g' \
        -e 's|@@APP_B@@|${FUS_UPDATE_PARTLABEL_APP_B}|g' \
        ${WORKDIR}/fus-app-mount > ${D}${sbindir}/fus-app-mount
    chmod 0755 ${D}${sbindir}/fus-app-mount

    install -d ${D}${systemd_system_unitdir}
    sed \
        -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
        -e 's|@@SBINDIR@@|${sbindir}|g' \
        ${WORKDIR}/fus-app-mount.service > ${D}${systemd_system_unitdir}/fus-app-mount.service
    chmod 0644 ${D}${systemd_system_unitdir}/fus-app-mount.service
}
