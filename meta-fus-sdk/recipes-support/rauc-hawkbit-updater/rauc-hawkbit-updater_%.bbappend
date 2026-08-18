FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://config.conf.in"

# the templated configuration carries machine-specific values (product,
# model, target name), so the package cannot be shared between machines of
# one architecture.
PACKAGE_ARCH = "${MACHINE_ARCH}"

# replace the upstream example config with one templated from the F&S
# hawkBit variables; runs after the recipe's own do_install:append.
# secrets stay out of git: an empty server/token leaves the file inert.
do_install:append() {
    sed \
        -e 's|@@SERVER@@|${FUS_UPDATE_HAWKBIT_SERVER}|g' \
        -e 's|@@SSL@@|${FUS_UPDATE_HAWKBIT_SSL}|g' \
        -e 's|@@SSL_VERIFY@@|${FUS_UPDATE_HAWKBIT_SSL_VERIFY}|g' \
        -e 's|@@TENANT@@|${FUS_UPDATE_HAWKBIT_TENANT}|g' \
        -e 's|@@TARGET@@|${FUS_UPDATE_HAWKBIT_TARGET}|g' \
        -e 's|@@TOKEN@@|${FUS_UPDATE_HAWKBIT_TOKEN}|g' \
        -e 's|@@MACHINE@@|${MACHINE}|g' \
        ${WORKDIR}/config.conf.in > ${D}${sysconfdir}/${PN}/config.conf
}

# ship the service but auto-enable it only once a hawkBit server is
# configured, so the standard image does not poll a non-existent endpoint.
SYSTEMD_AUTO_ENABLE:${PN} = "${@'enable' if d.getVar('FUS_UPDATE_HAWKBIT_SERVER') else 'disable'}"

# --- fs-updater door: route installs through the F&S updater --------------
# with door=fsupdater, fs-updater-lib is the sole update/state actor: a
# RAUC-direct install would bypass its pending/commit/rollback state (in
# container mode an app bundle would be staged but never activated). swap
# the daemon's installer backend for one that shells out to
# `fs-updater --install_update`; door=stock keeps the stock upstream
# backend byte-identical.
SRC_URI:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' file://rauc-installer-fsupdater.c file://10-fsupdater-backend.conf', '', d)}"

do_configure:prepend() {
    if [ "${FUS_UPDATE_INSTALL_DOOR}" = "fsupdater" ]; then
        # the replacement implements include/rauc-installer.h's
        # rauc_install() contract; refuse to build against an upstream
        # whose contract header drifted (a version bump is invisible to
        # this % bbappend).
        if ! grep -q 'gboolean rauc_install(const gchar \*bundle' ${S}/include/rauc-installer.h; then
            bbfatal "rauc-installer.h contract changed upstream; re-verify rauc-installer-fsupdater.c"
        fi
        cp ${WORKDIR}/rauc-installer-fsupdater.c ${S}/src/rauc-installer.c
    fi
}

do_install:append() {
    if [ "${FUS_UPDATE_INSTALL_DOOR}" = "fsupdater" ]; then
        install -d ${D}${systemd_system_unitdir}/rauc-hawkbit-updater.service.d
        install -m 0644 ${WORKDIR}/10-fsupdater-backend.conf \
            ${D}${systemd_system_unitdir}/rauc-hawkbit-updater.service.d/

        # without the raised no-progress watchdog a large, slow-but-healthy
        # install is misreported as hung; assert the setting survived.
        if ! grep -q '^Environment=FSUP_INSTALL_WAIT_MS=' \
                ${D}${systemd_system_unitdir}/rauc-hawkbit-updater.service.d/10-fsupdater-backend.conf; then
            bbfatal "10-fsupdater-backend.conf lost the FSUP_INSTALL_WAIT_MS override"
        fi
    fi
}

FILES:${PN}:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' ${systemd_system_unitdir}/rauc-hawkbit-updater.service.d', '', d)}"
RDEPENDS:${PN}:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' fs-updater-cli', '', d)}"

# the two installer backends are distinguishable only by backend-private
# log strings; a gating mistake shipping the wrong backend would surface
# only on the device, as a staged-but-never-activated install reported to
# hawkBit as success.
python fus_selfcheck_backend_variant() {
    binpath = d.expand('${D}${bindir}/rauc-hawkbit-updater')
    if not os.path.isfile(binpath):
        bb.fatal('fus-selfcheck: %s not installed' % binpath)
    with open(binpath, 'rb') as f:
        blob = f.read()
    stock = b'Creating RAUC DBUS proxy' in blob
    fsup = b'delegating to' in blob
    container = d.getVar('FUS_UPDATE_INSTALL_DOOR') == 'fsupdater'
    if container and (stock or not fsup):
        bb.fatal('fus-selfcheck: fs-updater-door rauc-hawkbit-updater does not carry the '
                 'fs-updater exec backend (stock backend present: %s, exec backend present: %s)'
                 % (stock, fsup))
    if not container and (fsup or not stock):
        bb.fatal('fus-selfcheck: stock-door rauc-hawkbit-updater is not the stock upstream '
                 'backend (stock backend present: %s, exec backend present: %s) -- the backend '
                 'swap leaked across the door gate' % (stock, fsup))
}
do_install[postfuncs] += "fus_selfcheck_backend_variant"

# contract test: recompile the exec backend with the build toolchain
# against a stub CLI and assert the exit-code -> install-verdict mapping.
# host side; nothing ships to the device.
SRC_URI:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' file://test-rauc-installer-fsupdater.c file://fake-fs-updater file://run-backend-contract.sh', '', d)}"

DEPENDS:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' glib-2.0-native', '', d)}"

do_compile:append() {
    if [ "${FUS_UPDATE_INSTALL_DOOR}" = "fsupdater" ]; then
        # query glib against the native sysroot only: the target recipe
        # environment's PKG_CONFIG_PATH/SYSROOT_DIR would resolve the
        # target glib .pc and mismatch glibconfig.h; clear them so only
        # PKG_CONFIG_LIBDIR (native) is consulted.
        _cflags=$(PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH= \
                  PKG_CONFIG_LIBDIR=${STAGING_LIBDIR_NATIVE}/pkgconfig \
                  pkg-config --cflags glib-2.0)
        _libs=$(PKG_CONFIG_SYSROOT_DIR= PKG_CONFIG_PATH= \
                PKG_CONFIG_LIBDIR=${STAGING_LIBDIR_NATIVE}/pkgconfig \
                pkg-config --libs glib-2.0)
        chmod 0755 ${WORKDIR}/fake-fs-updater
        ${BUILD_CC} ${BUILD_CFLAGS} \
            -DFSUPDATER_CLI="\"${WORKDIR}/fake-fs-updater\"" \
            -I${S}/include $_cflags \
            ${WORKDIR}/test-rauc-installer-fsupdater.c \
            ${WORKDIR}/rauc-installer-fsupdater.c \
            ${BUILD_LDFLAGS} $_libs \
            -o ${B}/test-rauc-installer-fsupdater
        sh ${WORKDIR}/run-backend-contract.sh ${B}/test-rauc-installer-fsupdater
    fi
}
