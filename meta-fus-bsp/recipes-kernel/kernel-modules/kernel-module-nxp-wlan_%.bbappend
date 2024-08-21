FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} = "\
    ${sysconfdir}/modprobe.d/mxm-wifiex.conf \
    ${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf \
"

SRC_URI += " file://001-Create-module.aliases-for-the-sdio-devices.patch \
    file://mxm-wifiex.conf \
    file://mxm-wifiex-filters.conf \
"

SOC_FAMILY                    = "INVALID"
SOC_FAMILY:mx93-generic-bsp   = "mx93"
SOC_FAMILY:mx8ulp-generic-bsp   = "mx93"

do_install:append () {
    # install mxm-wifiex to install, blacklist supported driver
    install -d ${D}${sysconfdir}/modprobe.d/
    install -m 0755 ${WORKDIR}/mxm-wifiex.conf ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
    # install mxm-wifiex-filters to define loading sequency
    # first wifi and second bluetooth
    install -d ${D}${sysconfdir}/modules-load.d/
    install -m 0644 ${WORKDIR}/mxm-wifiex-filters.conf ${D}${sysconfdir}/modules-load.d/mxm-wifiex-filters.conf

    do_install_${SOC_FAMILY}
}

do_install_mx93 () {
    # use moal driver by default.
    # comment blacklist entries
    sed -i '3,5 s/^/#/' ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
    # uncomment options to use wifi_mod_para.conf for moal driver
    sed -i '16 s/^#//' ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
}

