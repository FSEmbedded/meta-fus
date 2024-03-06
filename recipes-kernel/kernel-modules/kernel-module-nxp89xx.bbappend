FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

FILES:${PN} = "\
	${sysconfdir}/modprobe.d/mxm-wifiex.conf \
"

SRC_URI += " file://001-Create-module.aliases-for-the-sdio-devices.patch \
			 file://mxm-wifiex.conf"


# fsimx6ul does not support PCIE
EXTRA_OEMAKE:append:fsimx6ul =" CONFIG_PCIE8997=n CONFIG_PCIE9098=n"

do_install:append () {
    install -d ${D}${sysconfdir}/modprobe.d/
    install -m 0755 ${WORKDIR}/mxm-wifiex.conf ${D}${sysconfdir}/modprobe.d/mxm-wifiex.conf
}
