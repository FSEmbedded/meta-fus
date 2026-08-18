SUMMARY = "fw_env.config for userspace/RAUC access to the U-Boot environment"
DESCRIPTION = "Ships the location of the U-Boot environment for libubootenv \
(fw_printenv / fw_setenv, used by RAUC and the fs-updater). The values come \
from the machine table in fus-uboot-env.inc; a boot-time service renders them \
for the running board into /run and /etc/fw_env.config links there."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI = " \
    file://fus-fw-env-render \
    file://90-fus-uboot-env-rw.rules \
    file://fus-uboot-env-setup \
    file://fus-uboot-env-setup.service \
"
S = "${WORKDIR}"

inherit systemd

# the template bakes the machine's FUS_ENV_* values.
PACKAGE_ARCH = "${MACHINE_ARCH}"

RDEPENDS:${PN} = "libubootenv-bin mmc-utils udev util-linux-findmnt"

SYSTEMD_SERVICE:${PN} = "fus-uboot-env-setup.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    [ -n "${FUS_ENV_OFFSETS}" ] ||
        bbfatal "no FUS_ENV_OFFSETS for ${MACHINE}; add it to conf/machine/include/fus-uboot-env.inc"
    install -d ${D}${nonarch_libdir}/fus-update
    template=${D}${nonarch_libdir}/fus-update/fw_env.config.in
    {
        printf '%s\n' '# Rendered by fus-uboot-env-setup into /run/fus-update/fw_env.config.'
        printf '%s\n' '# device offset env-size sector-size [sectors]'
        sh ${WORKDIR}/fus-fw-env-render "${FUS_ENV_MEDIUM}" "${FUS_ENV_SIZE}" \
            "${FUS_ENV_SECT}" "${FUS_ENV_NSECT}" ${FUS_ENV_OFFSETS}
    } > "$template"

    # One device line per offset; a mismatch is a different on-disk format.
    lines=$(grep -c '^@@' "$template")
    want=$(set -- ${FUS_ENV_OFFSETS}; echo $#)
    [ "$lines" -eq "$want" ] || bbfatal "fw_env.config template has $lines device lines, want $want"

    install -d ${D}${sysconfdir}
    ln -sf /run/fus-update/fw_env.config ${D}${sysconfdir}/fw_env.config

    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/90-fus-uboot-env-rw.rules \
        ${D}${sysconfdir}/udev/rules.d/90-fus-uboot-env-rw.rules

    install -d ${D}${sbindir}
    sed -e 's|@@LIBDIR@@|${nonarch_libdir}|g' \
        -e 's|@@MEDIUM@@|${FUS_ENV_MEDIUM}|g' \
        -e 's|@@MTD_NAME@@|${FUS_ENV_MTD_NAME}|g' \
        ${WORKDIR}/fus-uboot-env-setup > ${D}${sbindir}/fus-uboot-env-setup
    chmod 0755 ${D}${sbindir}/fus-uboot-env-setup

    install -d ${D}${systemd_system_unitdir}
    sed -e 's|@@LIBDIR@@|${nonarch_libdir}|g' \
        ${WORKDIR}/fus-uboot-env-setup.service \
        > ${D}${systemd_system_unitdir}/fus-uboot-env-setup.service
    chmod 0644 ${D}${systemd_system_unitdir}/fus-uboot-env-setup.service
}

FILES:${PN} = " \
    ${sysconfdir}/fw_env.config \
    ${sysconfdir}/udev/rules.d/90-fus-uboot-env-rw.rules \
    ${nonarch_libdir}/fus-update/fw_env.config.in \
    ${sbindir}/fus-uboot-env-setup \
    ${systemd_system_unitdir}/fus-uboot-env-setup.service \
"
