# Update 11-imx93-pxp.rules
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append:mx93-nxp-bsp = " file://11-imx93-pxp.rules "

do_install:append:mx93-nxp-bsp () {
    install -D -m 0644 ${WORKDIR}/11-imx93-pxp.rules  \
                       ${D}${sysconfdir}/udev/rules.d/11-imx93-pxp.rules
}
