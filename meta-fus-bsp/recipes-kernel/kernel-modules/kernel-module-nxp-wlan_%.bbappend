FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} = "\
    ${sysconfdir}/modprobe.d/mxm-wifiex.conf \
    ${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf \
"

SRC_URI += " \
    file://mxm-wifiex.conf \
    file://mxm-wifiex-filters.conf \
"

do_install:append () {
    install -d ${D}${sysconfdir}/modules-load.d/
    install -d ${D}${sysconfdir}/modprobe.d/
    # install mxm-wifiex to install, blacklist supported driver
    install -m 0755 ${WORKDIR}/mxm-wifiex.conf ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
    # install mxm-wifiex-filters to define loading sequency
    install -m 0644 ${WORKDIR}/mxm-wifiex-filters.conf ${D}${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf
}


