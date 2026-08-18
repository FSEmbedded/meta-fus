# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/GPL-2.0-only;md5=801f80980d171dd6425610833a22dbe6"

SUMMARY = "F&S update framework library (update orchestrator, sole U-Boot state actor)"
SECTION = "libs"

# the version embeds the source commit hash, which does not sort
# monotonically, so a legitimate bump reads as a downgrade to the feed
# check. demoted to a warning; matches the sibling CLI recipe.
ERROR_QA:remove = "version-going-backwards"
WARN_QA:append = " version-going-backwards"

inherit cmake pkgconfig

# v2.4.0. library, client and service move together (FUS_COMPONENT_VERSION);
# the sibling CLI recipe's exit-code selfcheck fails the build if the pinned
# pair does not implement the expected contract.
SRCREV ?= "ab60a8e5248b3ca08f56737882ebe08ed493a857"

FSUPLIB_SRC_URI ?= "git://github.com/FSEmbedded/fs-updater-lib.git;protocol=https"
FSUPLIB_GIT_BRANCH ?= "master"
SRC_URI = "${FSUPLIB_SRC_URI};branch=${FSUPLIB_GIT_BRANCH}"

S = "${WORKDIR}/git"
PV = "${FUS_COMPONENT_VERSION}+git${SRCPV}"

DEPENDS = " \
    libubootenv \
    botan \
    jsoncpp \
    zlib \
    boost \
    libarchive \
    systemd \
    pkgconfig-native \
"

EXTRA_OECMAKE += "-Dupdate_version_type=string"
# align the lib's compiled-in device paths with this layer's layout
# (upstream defaults to the legacy /rw_fs tree). cmake strips the trailing
# slash from the PATH-typed FSUP_APP_IMG_STORE; the lib's path join
# tolerates that.
EXTRA_OECMAKE += "-DFSUP_RAUC_SCRATCH=${FSUP_RAUC_SCRATCH}"
EXTRA_OECMAKE += "-DFSUP_APP_IMG_STORE=${FUS_UPDATE_APP_IMG_DIR}/"
# the application ships its version file inside the app mount in every app
# mode, not under the rootfs /etc.
EXTRA_OECMAKE += "-DFSUP_APP_VERSION_FILE=${FUS_UPDATE_APP_MOUNT}${sysconfdir}/app_version"
# hand the pinned revision to the library so a device reports the build it
# runs; a recipe checkout cannot describe its own source tree.
EXTRA_OECMAKE += "-DFUS_SOURCE_ID=${SRCREV}"

FILES:${PN}-dev += "${includedir}/fs_update_framework/*"

inherit fus-selfcheck
do_configure[prefuncs] += "fus_selfcheck_botan2"
do_configure[postfuncs] += "fus_selfcheck_lib_paths"
