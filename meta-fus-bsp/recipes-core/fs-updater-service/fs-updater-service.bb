# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SUMMARY = "F&S update framework D-Bus service"
DESCRIPTION = "Persistent D-Bus daemon owning de.fsembedded.fsupdate1. Serialises \
update operations (InstallLocal and the cloud flow) and relays RAUC install \
progress to clients. The single install door for the CLI and the hawkBit bridge."

# the version embeds the source commit hash, which does not sort
# monotonically, so a legitimate bump reads as a downgrade to the feed
# check. demoted to a warning; matches the library and client recipes.
ERROR_QA:remove = "version-going-backwards"
WARN_QA:append = " version-going-backwards"

# v2.4.0, in lockstep with the library and the client (FUS_COMPONENT_VERSION).
SRCREV ?= "6f97c3437c7a809e18714bca68fa1175017a0756"
FSUPSERVICE_SRC_URI ?= "git://github.com/FSEmbedded/fs-updater-service.git;protocol=https"
FSUPSERVICE_GIT_BRANCH ?= "master"
SRC_URI = "${FSUPSERVICE_SRC_URI};branch=${FSUPSERVICE_GIT_BRANCH}"

S = "${WORKDIR}/git"
PV = "${FUS_COMPONENT_VERSION}+git${SRCPV}"

inherit cmake pkgconfig systemd

DEPENDS = " \
    fs-updater-lib \
    systemd \
    jsoncpp \
    libarchive \
    botan \
    libubootenv \
    zlib \
    pkgconfig-native \
"

# fs-updater-lib sysroot prefix: enables the real updater backend (HAVE_FUS_LIB).
EXTRA_OECMAKE += "-DFUS_LIB_DIR=${RECIPE_SYSROOT}${prefix}"

SYSTEMD_SERVICE:${PN} = "fs-updater.service"
SYSTEMD_AUTO_ENABLE:${PN} = "enable"

# the image store and the RAUC scratch live on the persistent partition;
# an install must never run against an unmounted /data.
do_install:append() {
    install -d ${D}${systemd_system_unitdir}/fs-updater.service.d
    printf '[Unit]\nRequiresMountsFor=%s\n' "${FUS_UPDATE_DATA_MOUNT}" \
        > ${D}${systemd_system_unitdir}/fs-updater.service.d/10-fus-data-mount.conf
}

FILES:${PN} += " \
    ${sbindir}/fs-updater-service \
    ${systemd_system_unitdir}/fs-updater.service.d/10-fus-data-mount.conf \
    ${datadir}/dbus-1/system.d/de.fsembedded.fsupdate1.conf \
    ${sysconfdir}/polkit-1/rules.d/50-fsupdate.rules \
    ${datadir}/dbus-1/system-services/de.fsembedded.fsupdate1.service \
    ${datadir}/dbus-1/interfaces/de.fsembedded.fsupdate1.xml \
    ${datadir}/polkit-1/actions/de.fsembedded.fsupdate1.policy \
"
