FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# fs-updater door only: gate rauc-mark-good's BOOT_<slot>_LEFT reset on the
# firmware dimension of the fs-updater state door. While a firmware update or
# rollback is pending-and-unconfirmed, mark-good must NOT run -- the trial
# counter has to keep eroding toward a real U-Boot fallback instead of a
# stale mark-good silently absorbing an unhealthy update. The drop-in also
# orders mark-good after the confirm run, so the precondition reads a settled
# state instead of racing the unit that settles it. The base unit is
# untouched whenever FUS_UPDATE_INSTALL_DOOR is stock.
SRC_URI:append = " file://10-fw-confirm-gate.conf"

# Close the stock RAUC bus door to root. The upstream policy allows the default
# context to send to de.pengutronix.rauc, so any local user reaches every
# method -- verified on a device, an unprivileged InstallBundle call was
# accepted and failed only on the missing file. Not door-gated: all callers run
# as root under either door, and the permissive default is worth removing
# regardless of which door drives the update.
#
# It REPLACES the upstream file rather than overriding it from ${sysconfdir}.
# /etc is a writable overlay whose upper lives on the data partition and is
# slot-independent, so a policy shipped there can be copied up once and then
# beats every later image, silently reopening the door. Replacing the file the
# daemon's own package already lists (rauc-target.inc FILES:${PN}-service)
# keeps it in that package, leaves exactly one policy in the image, and leaves
# /etc/dbus-1/system.d free for a deliberate administrator override.
SRC_URI:append = " file://de.pengutronix.rauc.conf"

do_install:append() {
    install -d ${D}${datadir}/dbus-1/system.d
    install -m 0644 ${WORKDIR}/de.pengutronix.rauc.conf \
        ${D}${datadir}/dbus-1/system.d/

    if [ "${FUS_UPDATE_INSTALL_DOOR}" = "fsupdater" ]; then
        install -d ${D}${systemd_system_unitdir}/rauc-mark-good.service.d
        install -m 0644 ${WORKDIR}/10-fw-confirm-gate.conf \
            ${D}${systemd_system_unitdir}/rauc-mark-good.service.d/
    fi
}

# Build-time guard for the policy above: assert the hardened text is what
# actually ships, in the read-only location and nowhere else. The check itself
# lives in the fus-selfcheck.bbclass catalog.
inherit fus-selfcheck
do_install[postfuncs] += "fus_selfcheck_dbus_policy"

FILES:${PN}-mark-good:append = " ${systemd_system_unitdir}/rauc-mark-good.service.d"

# Whatever ships the ExecCondition gate above must also ship the binary it
# names, on every image that ships rauc-mark-good at all -- including
# fusys-image-core, which installs packagegroup-fus-update-base but not
# packagegroup-fus-app. Door-gated (not :app-container-only): the fsupdater
# door is valid for rootfs mode too, not just container.
RDEPENDS:${PN}-mark-good:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' fs-updater-cli fs-updater-service fus-update-confirm', '', d)}"
