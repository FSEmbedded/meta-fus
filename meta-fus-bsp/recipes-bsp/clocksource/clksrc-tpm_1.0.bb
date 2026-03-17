SUMMARY = "Clocksource suspend/wakeup handling"
DESCRIPTION = "Sets custom clocksource on boot/resume and restores default on suspend"
LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/{PN}:"

SRC_URI = "file://clocksource.sh \
           file://clocksource.service \
           file://clocksource-hook.sh \
"

S = "${WORKDIR}"

inherit systemd

SYSTEMD_SERVICE:${PN} = "clocksource.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

do_install() {
    # install script
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/clocksource.sh ${D}${sbindir}/clocksource.sh

    # install systemd services/hooks
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/clocksource.service \
        ${D}${systemd_system_unitdir}/clocksource.service
	install -d ${D}${systemd_unitdir}/system-sleep
	install -m 0755 ${WORKDIR}/clocksource-hook.sh \
        ${D}${systemd_unitdir}/system-sleep/clocksource-hook.sh
}

FILES:${PN} += " \
    ${sbindir}/clocksource.sh \
    ${systemd_system_unitdir}/clocksource.service \
    ${systemd_unitdir}/system-sleep/clocksource-hook.sh \
"

