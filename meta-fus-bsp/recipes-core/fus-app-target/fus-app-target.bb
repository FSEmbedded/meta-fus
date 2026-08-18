SUMMARY = "Synchronization target signalling that the app filesystem is populated"
DESCRIPTION = "A passive systemd target that decouples the application service \
from how the app filesystem is delivered (a mounted A/B slot in slot mode, a \
verity loop+overlay merge in container mode). The mode-specific provider orders \
itself Before= this target; the application service orders itself \
After=/Requires= it. Present in every mode so the application service is \
mode-agnostic."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fus-app.target"
S = "${WORKDIR}"

inherit allarch

# A target only — nothing to enable. It is pulled into the boot transaction by
# the application service's Requires=fus-app.target.
FILES:${PN} = "${systemd_system_unitdir}/fus-app.target"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/fus-app.target ${D}${systemd_system_unitdir}/fus-app.target
}
