# reference implementation of the app-integration contract: the
# two-package split, the launcher/health-probe convention, and the
# etc/app-release + etc/app_version metadata an app payload must ship.
SUMMARY = "Example versioned application for the configurable app update mode"
DESCRIPTION = "A tiny versioned demo app split across two outputs: the payload \
(delivered at the app mount under /opt — an A/B slot, a container image, or baked \
into the rootfs depending on the mode) and a launcher systemd service \
(installed into the standard rootfs) that runs the payload from the app mount. \
Demonstrates application and combined firmware+application updates."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://fus-demo-app file://fus-demo-app.service file://health.d/10-fus-demo-app"
S = "${WORKDIR}"

inherit allarch systemd

# date-based version (YYYYMMDD), baked into the payload so an app-only
# update is visible across a slot switch. override per release.
FUS_DEMO_APP_VERSION ?= "${DATE}"

# DATE flows in through this variable's expansion, so the exclude must sit
# on the variable (a task-level vardepsexclude does not prune it); without
# this a build spanning midnight trips "metadata is not deterministic".
# a pinned override still changes the hash and rebuilds.
FUS_DEMO_APP_VERSION[vardepsexclude] = "DATE"

# systemd ARCHITECTURE= identifier for etc/app-release (architecture(7)
# naming, not the GNU triplet); "allarch" is honest for a script payload.
FUS_DEMO_APP_ARCH ?= "${@{'aarch64': 'arm64', 'x86_64': 'x86-64', 'i686': 'x86', 'arm': 'arm'}.get(d.getVar('TARGET_ARCH'), d.getVar('TARGET_ARCH'))}"

# where the payload tree is rooted so it resolves at the app mount in
# every mode (binary at <mount>${bindir}):
#   slot/container — image root; the whole app image becomes the mount.
#   rootfs         — under the app prefix in the main rootfs.
FUS_DEMO_APP_INSTALL_PREFIX            = ""
FUS_DEMO_APP_INSTALL_PREFIX:app-rootfs = "${FUS_UPDATE_APP_MOUNT}"

# two outputs:
#   ${PN}           — payload; app image (slot/container) or main rootfs
#   ${PN}-launcher  — systemd service; goes into the rootfs, runs the app
PACKAGES = "${PN} ${PN}-launcher"

FILES:${PN} = "${FUS_DEMO_APP_INSTALL_PREFIX}${bindir}/fus-demo-app ${FUS_DEMO_APP_INSTALL_PREFIX}${sysconfdir}/app_version ${FUS_DEMO_APP_INSTALL_PREFIX}${sysconfdir}/app-release"
FILES:${PN}-launcher = "${systemd_system_unitdir}/fus-demo-app.service"
FILES:${PN}-launcher += "${FUS_UPDATE_HEALTH_DIR}/10-fus-demo-app"

SYSTEMD_PACKAGES = "${PN}-launcher"
SYSTEMD_SERVICE:${PN}-launcher = "fus-demo-app.service"
SYSTEMD_AUTO_ENABLE:${PN}-launcher = "enable"

do_install() {
    install -d ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${bindir}
    install -m 0755 ${WORKDIR}/fus-demo-app ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${bindir}/fus-demo-app
    sed -i -e 's|@@VERSION@@|${FUS_DEMO_APP_VERSION}|' \
           -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
           ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${bindir}/fus-demo-app

    install -d ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${sysconfdir}
    echo "${FUS_DEMO_APP_VERSION}" > ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${sysconfdir}/app_version

    # self-describing app metadata (os-release-style KEY=VALUE).
    # informational only, never a trust boundary; the runtime reads
    # APP_VERSION, the selfcheck asserts IMAGE_ID.
    printf 'APP_ID=%s\nAPP_VERSION=%s\nARCHITECTURE=%s\nIMAGE_ID=%s\nIMAGE_VERSION=%s\nPRETTY_NAME=%s\n' \
        "${FUS_UPDATE_APP_ID}" "${FUS_DEMO_APP_VERSION}" "${FUS_DEMO_APP_ARCH}" \
        "${FUS_UPDATE_APP_ID}" "${FUS_DEMO_APP_VERSION}" "${FUS_UPDATE_APP_DESCRIPTION}" \
        > ${D}${FUS_DEMO_APP_INSTALL_PREFIX}${sysconfdir}/app-release

    install -d ${D}${systemd_system_unitdir}
    sed -e 's|@@APP_MOUNT@@|${FUS_UPDATE_APP_MOUNT}|g' \
        -e 's|@@APP_BINDIR@@|${FUS_UPDATE_APP_MOUNT}${bindir}|g' \
        ${WORKDIR}/fus-demo-app.service > ${D}${systemd_system_unitdir}/fus-demo-app.service

    install -d ${D}${FUS_UPDATE_HEALTH_DIR}
    install -m 0755 ${WORKDIR}/health.d/10-fus-demo-app ${D}${FUS_UPDATE_HEALTH_DIR}/10-fus-demo-app
}
