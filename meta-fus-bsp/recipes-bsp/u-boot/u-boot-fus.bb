# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "u-boot bootloader for F&S boards and modules"
require recipes-bsp/u-boot/u-boot.inc

PROVIDES += "u-boot"
DEPENDS:append = " python3 dtc-native bison-native libarchive-native xxd-native "
DEPENDS:append = " \
	${@bb.utils.contains('UBOOT_MAKE_TARGET', 'uboot-info.fs', 'imx-atf', '', d)} \
	${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-os', '', d)} \
"

RDEPENDS:${PN}:append = " fs-installscript"

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://Licenses/README;md5=2ca5f2c35c8cc335f0a19756634782f1"

# Use this to build from local source
#SRC_URI = "git://${DL_DIR}/u-boot-fus;branch=fsimx93;protocol=file"
SRC_URI = "git://github.com/FSEmbedded/u-boot-fus;branch=fsimx93;protocol=https"
SRCREV = "4f846f5a7b29e2d934f86918875b3296ee185cb0"

SCMVERSION ??= "y"
LOCALVERSION ??= "-F+S"

UBOOT_LOCALVERSION = "${LOCALVERSION}"

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"
PV = "+git${SRCPV}"

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
NEED_ATF = "${@bb.utils.contains('UBOOT_MAKE_TARGET', 'uboot-info.fs', 'true', 'false', d)}"
UBOOT_FILE = "${@bb.utils.contains('UBOOT_MAKE_TARGET', 'uboot-info.fs', 'uboot-info.fs', 'uboot.fs', d)}"

inherit deploy

do_compile:prepend() {
	if [ "${SCMVERSION}" = "y" ]; then
		# Add GIT revision to the local version
		# get annotated tag name only
		head=`cd ${S} ; git tag --contains HEAD --format='%(objecttype) %(refname:strip=2)' | \
				grep '^tag ' | awk '{print $2}' 2> /dev/null`
		sep="-"
		if [ -z "${head}" ]; then
			head=`cd ${S} ; git rev-parse --verify --short HEAD 2> /dev/null`
			sep="+g"
		fi
		printf "%s%s%s" "${UBOOT_LOCALVERSION}" $sep $head > ${S}/.scmversion
		printf "%s%s%s" "${UBOOT_LOCALVERSION}" $sep $head > ${B}/.scmversion
	else
		printf "%s" "${UBOOT_LOCALVERSION}" > ${S}/.scmversion
		printf "%s" "${UBOOT_LOCALVERSION}" > ${B}/.scmversion
	fi

	#Copy Firmware files into NXP-Firmware
	if ${NEED_ATF}; then
		cp ${DEPLOY_DIR_IMAGE}/bl31-${ATF_PLATFORM}.bin ${S}/board/F+S/NXP-Firmware/bl31.bin
		if ${NEED_OPTEE}; then
			cp ${DEPLOY_DIR_IMAGE}/bl31-${ATF_PLATFORM}.bin-optee ${S}/board/F+S/NXP-Firmware/bl31-optee.bin
		fi
	fi

	if ${NEED_OPTEE}; then
		cp ${DEPLOY_DIR_IMAGE}/tee.bin ${S}/board/F+S/NXP-Firmware/bl32.bin
	fi
}

do_deploy:append() {
	install -d ${DEPLOY_DIR_IMAGE}/Firmware/
	install -d ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware

	for config in ${UBOOT_CONFIG}; do
		install -m 0644 ${B}/${config}_defconfig/board/F+S/NXP-Firmware/* ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware
		install -m 0644 ${B}/${config}_defconfig//${UBOOT_FILE} ${DEPLOY_DIR_IMAGE}/Firmware/uboot-${config}-${PV}.fs
		cd ${DEPLOY_DIR_IMAGE}/ && ln -sf Firmware/uboot-${config}-${PV}.fs ./uboot-${config}.fs; cd -
		cd ${DEPLOY_DIR_IMAGE}/Firmware/ && ln -sf uboot-${config}-${PV}.fs ./uboot-${config}.fs; cd -
	done
}

PACKAGE_ARCH = "${MACHINE_ARCH}"
