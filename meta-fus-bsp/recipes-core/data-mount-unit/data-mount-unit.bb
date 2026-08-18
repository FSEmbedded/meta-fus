SUMMARY = "systemd mount unit for the persistent data partition"
DESCRIPTION = "Provides a <mount>.mount unit so post-boot services can depend \
on the persistent partition being tracked by systemd. The partition is \
initially mounted by the overlayfs-etc preinit script; this unit picks up \
the existing mount for fsck integration and dependency anchoring. Mount \
point and partition identity come from conf/include/fus-update-layout.inc."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://data.mount.in"

S = "${WORKDIR}"

inherit systemd allarch

# systemd derives a .mount unit's name from its mount path (escaped). The
# simple transform below is exact for plain paths (/data, /mnt/<name>);
# mount points containing dashes or unicode would need real systemd-escape.
FUS_UPDATE_DATA_UNIT = "${@d.getVar('FUS_UPDATE_DATA_MOUNT').strip('/').replace('/', '-') + '.mount'}"

SYSTEMD_SERVICE:${PN} = "${FUS_UPDATE_DATA_UNIT}"
SYSTEMD_AUTO_ENABLE = "enable"

FILES:${PN} = "${systemd_system_unitdir}/${FUS_UPDATE_DATA_UNIT}"

# The by-partlabel device dash in the fsck unit ("by-partlabel") is escaped
# as the literal \x2d in data.mount.in; only the partlabel value (kept plain
# alphanumeric per the layout include) is substituted here.
do_install() {
    install -d ${D}${systemd_system_unitdir}
    sed \
        -e 's|@@WHERE@@|${FUS_UPDATE_DATA_MOUNT}|g' \
        -e 's|@@PARTLABEL@@|${FUS_UPDATE_PARTLABEL_DATA}|g' \
        -e 's|@@FSTYPE@@|${FUS_UPDATE_DATA_FSTYPE}|g' \
        -e 's|@@OPTIONS@@|${FUS_UPDATE_DATA_MOUNT_OPTIONS}|g' \
        ${WORKDIR}/data.mount.in > ${D}${systemd_system_unitdir}/${FUS_UPDATE_DATA_UNIT}
    chmod 0644 ${D}${systemd_system_unitdir}/${FUS_UPDATE_DATA_UNIT}
}
