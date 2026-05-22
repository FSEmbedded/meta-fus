FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} = "\
    ${sysconfdir}/modprobe.d/mxm-wifiex.conf \
    ${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf \
"

SRC_URI += " \
    file://mxm-wifiex.conf \
    file://mxm-wifiex-filters.conf \
"

SOC_FAMILY                    = "INVALID"
SOC_FAMILY:mx93-generic-bsp   = "mx93"
SOC_FAMILY:mx8ulp-generic-bsp   = "mx93"
SOC_FAMILY:mx8-generic-bsp   = "mx8"
SOC_FAMILY:mx6-generic-bsp   = "mx6"

do_install:append () {
    install -d ${D}${sysconfdir}/modules-load.d/
    install -d ${D}${sysconfdir}/modprobe.d/
    # install mxm-wifiex to install, blacklist supported driver
    install -m 0755 ${WORKDIR}/mxm-wifiex.conf ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
    # install mxm-wifiex-filters to define loading sequency
    install -m 0644 ${WORKDIR}/mxm-wifiex-filters.conf ${D}${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf
}


