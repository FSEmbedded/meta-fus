# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license
SUMMARY = "F&S update framework CLI (state-guarded update verbs)"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# v2.4.0, in lockstep with the library (FUS_COMPONENT_VERSION). the
# exit-code selfcheck below fails the build if the fetched source does not
# carry the expected contract.
SRCREV ?= "a760601da874bc2560d7388af9f140c5795799e3"

FSUPCLI_SRC_URI ?= "git://github.com/FSEmbedded/fs-updater-cli.git;protocol=https"
FSUPCLI_GIT_BRANCH ?= "master"
SRC_URI = " \
    ${FSUPCLI_SRC_URI};branch=${FSUPCLI_GIT_BRANCH} \
    file://fsup-framework-cli \
"

S = "${WORKDIR}/git"
PV = "${FUS_COMPONENT_VERSION}+git${SRCPV}"

# the version embeds the source commit hash, which does not sort
# monotonically, so a legitimate bump reads as a downgrade to the feed
# check. demoted to a warning.
ERROR_QA:remove = "version-going-backwards"
WARN_QA:append = " version-going-backwards"

inherit cmake pkgconfig

DEPENDS = " \
    libubootenv \
    botan \
    jsoncpp \
    zlib \
    boost \
    fs-updater-lib \
    libarchive \
    systemd \
    bash-completion \
    pkgconfig-native \
"

EXTRA_OECMAKE += "-Dupdate_version_type=string"
EXTRA_OECMAKE += "-DBUILD_DBUS_SUPPORT=ON"
# hand the pinned revision to the client so it reports the build it runs.
EXTRA_OECMAKE += "-DFUS_SOURCE_ID=${SRCREV}"

do_install:append() {
    install -D -m 0644 ${WORKDIR}/fsup-framework-cli ${D}${sysconfdir}/bash_completion.d/fs_updater
}

# rootfs mode: front the CLI with a gate that rejects any bundle carrying
# an application dimension (by -appfs compatible suffix or an appfs image
# member) before fs-updater-lib writes any pending state. residual: a
# direct D-Bus client bypassing this CLI is not covered.
SRC_URI:append:app-rootfs = " \
    file://fs-updater-guard-rootfs \
    file://test-fs-updater-guard-rootfs.sh \
"

# host-side contract test for the gate; nothing test-related is shipped.
do_compile:append:app-rootfs() {
    sh ${WORKDIR}/test-fs-updater-guard-rootfs.sh ${WORKDIR}/fs-updater-guard-rootfs
}

do_install:append:app-rootfs() {
    mv ${D}${sbindir}/fs-updater ${D}${sbindir}/fs-updater.real
    install -m 0755 ${WORKDIR}/fs-updater-guard-rootfs ${D}${sbindir}/fs-updater
}

inherit fus-selfcheck
do_configure[postfuncs] += "fus_selfcheck_cli_exit_codes"
