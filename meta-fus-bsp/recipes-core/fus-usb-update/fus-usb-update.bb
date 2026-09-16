SUMMARY = "Automatic update from a removable medium"
DESCRIPTION = "Udev rule, systemd unit and wrapper that install a signed \
firmware bundle found on a labelled removable medium, through the updater door \
this image was built with."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

require conf/include/fus-update-layout.inc

SRC_URI = " \
    file://99-fus-usb-update.rules \
    file://fus-usb-update.service \
    file://fus-usb-update.sh \
"

S = "${WORKDIR}"

inherit systemd allarch fus-selfcheck

# The door delegates to the updater CLI, so this package only makes sense where
# that door is the one the image was built with.
RDEPENDS:${PN} = "systemd udev rauc fs-updater-cli"

SYSTEMD_SERVICE:${PN} = "fus-usb-update.service"
# The udev rule is the only trigger, so it is also the only switch: the unit is
# never enabled on its own.
SYSTEMD_AUTO_ENABLE:${PN} = "disable"

do_install() {
    install -d ${D}${nonarch_base_libdir}/udev/rules.d
    install -d ${D}${systemd_system_unitdir}
    install -d ${D}${libexecdir}
    # Shipped empty: the door runs whatever the image drops in here, and the
    # directory being the image's is what keeps a hook off the medium.
    install -d ${D}${libexecdir}/fus-usb-update.d

    # Not under ${sysconfdir}: /etc is a writable overlay whose upper outlives
    # every later image, and this rule is the feature switch.
    install -m 0644 ${WORKDIR}/99-fus-usb-update.rules ${D}${nonarch_base_libdir}/udev/rules.d/
    install -m 0644 ${WORKDIR}/fus-usb-update.service  ${D}${systemd_system_unitdir}/
    install -m 0755 ${WORKDIR}/fus-usb-update.sh       ${D}${libexecdir}/
}

# The unit's mount namespace and its start rate limit are load-bearing; both
# fail silently on a device rather than at build time.
do_install[postfuncs] += "fus_selfcheck_usb_door_unit"

FILES:${PN} += " \
    ${nonarch_base_libdir}/udev/rules.d/99-fus-usb-update.rules \
    ${systemd_system_unitdir}/fus-usb-update.service \
    ${libexecdir}/fus-usb-update.sh \
    ${libexecdir}/fus-usb-update.d \
"

# Skip rather than fail: an anonymous fatal would stop every parse in the layer,
# including builds this recipe has nothing to do with.
python () {
    if d.getVar("FUS_UPDATE_INSTALL_DOOR") == "stock":
        raise bb.parse.SkipRecipe("this door drives the updater CLI; a stock-door "
                                  "image has no updater to drive")
}
