FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://config.conf.in \
            file://0001-Change-interface-name-to-fs.patch "

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


