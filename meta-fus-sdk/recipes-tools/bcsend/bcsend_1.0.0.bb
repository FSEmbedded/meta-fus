SUMMARY = "F&S board information broadcast tool"
DESCRIPTION = "Simple F&S tool to broadcast board information over network. The broadcast can be received with the software FSDeviceSpy"

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://bcsend_linux.cpp;beginline=2;endline=20;md5=27a7285f52f670c4f98ebaaf5b2b0e2e"

SRC_URI = "git://github.com/FSEmbedded/bcsend-linux;branch=main;protocol=https \
           file://bcsend.service \
           file://systemd-networkd-wait-online-any.conf \
"

SRCREV = "766463bd97ee8950d3e6c0c19c208457a367259f"

S = "${WORKDIR}/git"

inherit systemd

SYSTEMD_SERVICE:${PN} = "bcsend.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_compile() {
    oe_runmake
}

FILES:${PN}:append = " \
    ${sbindir}/bcsend \
    ${systemd_system_unitdir}/bcsend.service \
    ${systemd_system_unitdir}/systemd-networkd-wait-online.service.d/systemd-networkd-wait-online-any.conf \
"

do_install() {
    install -d ${D}/${sbindir}
    install -m 0755 ${S}/bcsend ${D}/${sbindir}/bcsend

    install -d ${D}${systemd_system_unitdir}
    install -d ${D}${systemd_system_unitdir}/systemd-networkd-wait-online.service.d
    install -m 0644 ${WORKDIR}/bcsend.service ${D}${systemd_system_unitdir}/bcsend.service

    install -m 0644 ${WORKDIR}/systemd-networkd-wait-online-any.conf \
        ${D}${systemd_system_unitdir}/systemd-networkd-wait-online.service.d/systemd-networkd-wait-online-any.conf

}
