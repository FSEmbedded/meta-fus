SUMMARY = "Confirm the booted A/B slot without the update framework"
DESCRIPTION = "Resets the booted slot's U-Boot boot-attempt counter once the \
               boot is complete, as rauc-mark-good does with the update \
               framework. Without it the bootloader falls back to the other \
               slot once the attempts are used up. Only the counter is \
               written; the boot order stays as it is."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fus-ab-mark-good \
           file://fus-ab-mark-good.service"

S = "${WORKDIR}"

inherit systemd allarch

SYSTEMD_SERVICE:${PN} = "fus-ab-mark-good.service"

do_install() {
    install -d ${D}${sbindir} ${D}${systemd_system_unitdir}
    install -m 0755 ${WORKDIR}/fus-ab-mark-good ${D}${sbindir}/
    install -m 0644 ${WORKDIR}/fus-ab-mark-good.service ${D}${systemd_system_unitdir}/
}

# fw_printenv/fw_setenv. The environment location comes with the A/B base.
RDEPENDS:${PN} = "libubootenv-bin"
