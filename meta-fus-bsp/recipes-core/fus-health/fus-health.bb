SUMMARY = "Runtime application-health gate for the A/B update"
DESCRIPTION = "Runs health probes before boot-complete.target so a degraded-but-booting \
slot is not confirmed; the bootloader trial counter then reverts it."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://fus-health-check \
    file://fus-health-check.service \
    file://10-fus-watchdog.conf \
    file://fus-health-confirm.service \
    file://fus-health-confirm.timer \
    file://fus-health-monitor.conf \
"
S = "${WORKDIR}"

inherit allarch systemd
SYSTEMD_SERVICE:${PN} = "fus-health-check.service fus-health-confirm.timer"
RDEPENDS:${PN} += "systemd rauc-mark-good"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/fus-health-check ${D}${bindir}/fus-health-check

    # the probe dir ships empty: probes are app-specific and dropped in by
    # the launcher packages.
    install -d ${D}${FUS_UPDATE_HEALTH_DIR}

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/fus-health-check.service ${D}${systemd_system_unitdir}/
    sed -i 's|@@HEALTH_DIR@@|${FUS_UPDATE_HEALTH_DIR}|' \
        ${D}${systemd_system_unitdir}/fus-health-check.service

    # systemd-boot-check-no-failures is deliberately not wired into the
    # gate: benign BSP units fail on a real image and would force a revert
    # on every boot. the gate runs app-specific probes only.
    install -d ${D}${sysconfdir}/systemd/system.conf.d
    install -m 0644 ${WORKDIR}/10-fus-watchdog.conf ${D}${sysconfdir}/systemd/system.conf.d/
    sed -i 's|@@WATCHDOG_SEC@@|${FUS_UPDATE_WATCHDOG_SEC}|' \
        ${D}${sysconfdir}/systemd/system.conf.d/10-fus-watchdog.conf

    install -m 0644 ${WORKDIR}/fus-health-confirm.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/fus-health-confirm.timer   ${D}${systemd_system_unitdir}/
    sed -i 's|@@HEALTH_TIMEOUT@@|${FUS_UPDATE_HEALTH_TIMEOUT}|' \
        ${D}${systemd_system_unitdir}/fus-health-confirm.timer
}

# container mode is monitor-only: an app fault must not ping-pong the
# healthy OS slot; the app dimension has its own auto-revert (bootguard)
# and external commit/reject.
do_install:append:app-container() {
    install -d ${D}${systemd_system_unitdir}/fus-health-check.service.d
    install -m 0644 ${WORKDIR}/fus-health-monitor.conf \
        ${D}${systemd_system_unitdir}/fus-health-check.service.d/monitor-only.conf
}
FILES:${PN} += " \
    ${systemd_system_unitdir}/fus-health-check.service \
    ${FUS_UPDATE_HEALTH_DIR} \
    ${sysconfdir}/systemd/system.conf.d \
    ${systemd_system_unitdir}/fus-health-confirm.service \
    ${systemd_system_unitdir}/fus-health-confirm.timer \
"
FILES:${PN} += "${systemd_system_unitdir}/fus-health-check.service.d"
