# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "u-boot bootloader for F&S boards and modules"
require recipes-bsp/u-boot/u-boot.inc

PROVIDES += "u-boot"
DEPENDS:append = " python3 dtc-native bison-native libarchive-native xxd-native "

RDEPENDS:${PN}:append = " fs-installscript"


# Use this to build from local source
#SRC_URI = "git://${DL_DIR}/u-boot-fus;branch=${SRCBRANCH};protocol=file"
SRC_URI = "git://github.com/FSEmbedded/u-boot-fus;branch=${SRCBRANCH};protocol=https"

# merge the A/B feature fragment into the U-Boot defconfig only where A/B
# is in effect (fus-update-ab in COMBINED_FEATURES); other builds are
# unchanged. boot-mode dispatch (FUS_UPDATE_BOOT_MODE, default rootfs): the
# bootloader's compiled BOOT_FROM_MMC already boots rootfs mode; fus-ab.cfg
# (opt-in slot mode) overrides bootdir/.rootfs_part_* back to the vfat
# BOOT_A/B layout. the two fragments are mutually exclusive so
# CONFIG_PREBOOT is never doubly defined.
SRC_URI:append = " ${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', 'file://fus-ab.cfg', '', d)}"
SRC_URI:remove:boot-rootfs = "file://fus-ab.cfg"
SRC_URI:append:boot-rootfs = " ${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', 'file://fus-ab-bootrootfs.cfg', '', d)}"

SCMVERSION ??= "y"
LOCALVERSION ??= "-F+S"

UBOOT_LOCALVERSION = "${LOCALVERSION}"

PV = "${UBOOT_VERSION}"
CVE_PRODUCT = "u-boot"
S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

UBOOT_MAKE_TARGET ??= "all"
COMPATIBLE_MACHINE = "(mx6|vf60|mx7ulp|mx8|mx93)"

# Necessary ???
# FIXME: Allow linking of 'tools' binaries with native libraries
#        used for generating the boot logo and other tools used
#        during the build process.
#EXTRA_OEMAKE += 'HOSTCC="${BUILD_CC} ${BUILD_CPPFLAGS}" \
#                 HOSTLDFLAGS="${BUILD_LDFLAGS}" \
#                 HOSTSTRIP=true'

NEED_OPTEE = "${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'true', 'false', d)}"
NEED_ATF = "${@bb.utils.contains_any('UBOOT_MAKE_TARGET', 'uboot.fs uboot-atf.fs', 'true', 'false', d)}"
UBOOT_FILE = "${UBOOT_MAKE_TARGET}"

FIRMWARE_DIR = "board/F+S/NXP-Firmware/${MACHINE}"

inherit deploy
# fus-selfcheck lives in meta-fus-sdk: inherit it only where A/B is in effect.
inherit_defer ${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', 'fus-selfcheck', '', d)}

# assert the merged defconfig can read the zstd squashfs, so a dropped
# fragment fails the build, not the bench.
FUS_SELFCHECK_KCONFIG:boot-rootfs = "CONFIG_FS_SQUASHFS CONFIG_ZSTD CONFIG_CMD_FS_GENERIC"
do_configure[postfuncs] += "${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', bb.utils.contains('FUS_UPDATE_BOOT_MODE', 'rootfs', 'fus_selfcheck_kconfig', '', d), '', d)}"

# The environment location shipped to userspace must match this bootloader.
do_configure[postfuncs] += "${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', 'fus_selfcheck_fw_env', '', d)}"

# Assert the slot-mode CONFIG_PREBOOT override targets the wks file's actual
# Root_A partition index, so a wks reorder fails the build, not the bench.
do_configure[postfuncs] += "${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', bb.utils.contains('FUS_UPDATE_BOOT_MODE', 'slot', 'fus_selfcheck_uboot_ab_env', '', d), '', d)}"

do_compile[depends] += " \
	${@bb.utils.contains_any('UBOOT_MAKE_TARGET', 'uboot.fs uboot-atf.fs', 'imx-atf:do_deploy', '', d)} \
	${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-os:do_deploy', '', d)} \
"

do_compile:prepend() {
	if [ "${SCMVERSION}" = "y" ]; then
		# Add GIT revision to the local version
		# get annotated tag name only
		head=`cd ${S} ; git tag --points-at HEAD --format='%(objecttype) %(refname:strip=2)' | \
				grep '^tag ' | awk '{print $2}' 2> /dev/null`
		sep="-"
		if [ -z "${head}" ]; then
			head=`cd ${S} ; git rev-parse --verify --short HEAD 2> /dev/null`
			sep="+g"
			UBOOT_LOCALVERSION=""
		fi
		printf "%s%s%s" "${UBOOT_LOCALVERSION}" $sep $head > ${S}/.scmversion
		printf "%s%s%s" "${UBOOT_LOCALVERSION}" $sep $head > ${B}/.scmversion
	else
		printf "%s" "${UBOOT_LOCALVERSION}" > ${S}/.scmversion
		printf "%s" "${UBOOT_LOCALVERSION}" > ${B}/.scmversion
	fi

	#Copy Firmware files into NXP-Firmware
	if ${NEED_ATF}; then
		mkdir -p ${S}/${FIRMWARE_DIR}
		cp ${DEPLOY_DIR_IMAGE}/bl31-${ATF_PLATFORM}.bin ${S}/${FIRMWARE_DIR}/bl31.bin
		if ${NEED_OPTEE}; then
			cp ${DEPLOY_DIR_IMAGE}/bl31-${ATF_PLATFORM}.bin-optee ${S}/${FIRMWARE_DIR}/bl31-optee.bin
		fi
	fi

	if ${NEED_OPTEE}; then
		mkdir -p ${S}/${FIRMWARE_DIR}
		cp ${DEPLOY_DIR_IMAGE}/tee.bin ${S}/${FIRMWARE_DIR}/bl32.bin
	fi
}

do_deploy:append() {
	install -d ${DEPLOYDIR}/Firmware/
	install -d ${DEPLOYDIR}/Firmware/NXP-Firmware/
	install -d ${DEPLOYDIR}/Firmware/NXP-Firmware/${MACHINE}

	for config in ${UBOOT_CONFIG}; do
		install -m 0644 ${S}/${FIRMWARE_DIR}/* ${DEPLOYDIR}/Firmware/NXP-Firmware/${MACHINE}
		install -m 0644 ${B}/${config}_defconfig//${UBOOT_FILE} ${DEPLOYDIR}/Firmware/uboot-${config}-${PV}.fs
		cd ${DEPLOYDIR}/Firmware/ && ln -sf uboot-${config}-${PV}.fs ./uboot-${config}.fs; cd -
	done
}

PACKAGE_ARCH = "${MACHINE_ARCH}"
