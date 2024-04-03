FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} = "\
	${sysconfdir}/modprobe.d/mxm-wifiex.conf \
"

SRC_URI += " file://001-Create-module.aliases-for-the-sdio-devices.patch \
			 file://mxm-wifiex.conf"

SOC_FAMILY                    = "INVALID"
SOC_FAMILY:mx93-generic-bsp   = "mx93"
SOC_FAMILY:mx8ulp-generic-bsp   = "mx93"

do_install:append () {
    install -d ${D}${sysconfdir}/modprobe.d/
    install -m 0755 ${WORKDIR}/mxm-wifiex.conf ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf

    do_install_${SOC_FAMILY}
}

do_install_mx93 () {
    # use moal driver by default.
    # comment blacklist entries
    sed -i '3,5 s/^/#/' ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
    # uncomment options to use wifi_mod_para.conf for moal driver
    sed -i '16 s/^#//' ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
}

