# Copyright 2017-2020 F&S Elektronik Systeme

FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

# Firmware for atmel mxt touches
SRC_URI += " file://mxt224.cfg \
		   file://mxt224e_v2.cfg \
		   file://mxt1066.cfg \
		   file://mxt336u-gloves.cfg \
		   file://mxt336u-extra-glass.cfg"

do_install_append () {
    install -d ${D}${nonarch_base_libdir}/firmware/atmel
    # Install Atmel MXT Touch firmware
    install -m 0644 ${WORKDIR}/mxt224.cfg ${D}${nonarch_base_libdir}/firmware/atmel
    install -m 0644 ${WORKDIR}/mxt224e_v2.cfg ${D}${nonarch_base_libdir}/firmware/atmel
    install -m 0644 ${WORKDIR}/mxt1066.cfg ${D}${nonarch_base_libdir}/firmware/atmel
    install -m 0644 ${WORKDIR}/mxt336u-gloves.cfg ${D}${nonarch_base_libdir}/firmware/atmel
    install -m 0644 ${WORKDIR}/mxt336u-extra-glass.cfg ${D}${nonarch_base_libdir}/firmware/atmel
}

PACKAGES =+ " ${PN}-atmel-mxt"

FILES_${PN}-atmel-mxt = " \
       ${nonarch_base_libdir}/firmware/atmel/mxt224.cfg \
       ${nonarch_base_libdir}/firmware/atmel/mxt224e_v2.cfg \
       ${nonarch_base_libdir}/firmware/atmel/mxt1066.cfg \
       ${nonarch_base_libdir}/firmware/atmel/mxt336u-gloves.cfg \
       ${nonarch_base_libdir}/firmware/atmel/mxt336u-extra-glass.cfg \
"
