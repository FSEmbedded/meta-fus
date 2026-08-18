SUMMARY = "Mode-invariant update confirm: external commit/reject door, rollback finalize, deadline reboot"
DESCRIPTION = "Externalized confirm step for pending fs-updater update states: \
an outside caller (script, integrator application or human) decides whether a \
rebooted-into update is committed or rejected -- no in-platform health probe. \
The unattended parts keep only the fail-safe convergence: the boot-time \
confirm service finalizes already-decided states (rollback reboots taken, \
failed installs, a detected bootloader fallback past a never-booted update) \
and deliberately leaves pending updates pending; the \
deadline timer reboots if nothing decided in time, so the attempt counters \
(app bootguard, U-Boot firmware bootcount) keep eroding toward an automatic \
rollback. Also ships the shared pending-state predicate library and the \
fw-guard ExecCondition helper that gates rauc-mark-good on the firmware \
dimension. fs-updater remains the sole actor for state transitions \
(--commit_update / --rollback_update)."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
    file://fus-update-confirm \
    file://pending-state.sh \
    file://fus-update-confirm.service \
    file://fus-update-confirm-deadline.service \
    file://fus-update-confirm-deadline.timer \
    file://test-pending-state.sh \
    file://test-update-confirm.sh \
"
S = "${WORKDIR}"

# allarch: shell + units only, no arch-specific content.
inherit allarch systemd

# host-side contract tests; nothing test-related is installed or shipped. The
# second one covers the verbs. Its boot-guard cases need the container runtime,
# which another recipe owns and this work directory does not hold, so they are
# skipped here and covered by tools/test-update-door.sh, which runs the same
# file against all three sources.
do_compile() {
    sh ${WORKDIR}/test-pending-state.sh ${WORKDIR}/pending-state.sh
    sh ${WORKDIR}/test-update-confirm.sh ${WORKDIR}/fus-update-confirm \
        ${WORKDIR}/pending-state.sh
}

# fs-updater-cli provides the fs-updater actor the predicates and verbs drive.
RDEPENDS:${PN} += "systemd fs-updater-cli"

SYSTEMD_SERVICE:${PN} = " \
    fus-update-confirm.service \
    fus-update-confirm-deadline.service \
    fus-update-confirm-deadline.timer \
"

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/fus-update-confirm ${D}${bindir}/fus-update-confirm

    # Sourced, not executed -- hence 0644 and a lib path, not bindir.
    install -d ${D}${nonarch_libdir}/fus-update
    install -m 0644 ${WORKDIR}/pending-state.sh ${D}${nonarch_libdir}/fus-update/pending-state.sh

    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/fus-update-confirm.service          ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/fus-update-confirm-deadline.service ${D}${systemd_system_unitdir}/
    install -m 0644 ${WORKDIR}/fus-update-confirm-deadline.timer   ${D}${systemd_system_unitdir}/
    sed -i 's|@@DATA_MOUNT@@|${FUS_UPDATE_DATA_MOUNT}|' \
        ${D}${systemd_system_unitdir}/fus-update-confirm.service
    sed -i 's|@@HEALTH_TIMEOUT@@|${FUS_UPDATE_HEALTH_TIMEOUT}|' \
        ${D}${systemd_system_unitdir}/fus-update-confirm-deadline.timer
}

FILES:${PN} += " \
    ${bindir}/fus-update-confirm \
    ${nonarch_libdir}/fus-update/pending-state.sh \
    ${systemd_system_unitdir}/fus-update-confirm.service \
    ${systemd_system_unitdir}/fus-update-confirm-deadline.service \
    ${systemd_system_unitdir}/fus-update-confirm-deadline.timer \
"
