# Copyright (C) 2024 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DEPENDS:append = " python3 dtc-native bison-native lzop-native xxd-native"
DEPENDS:append = " \
	${IMX_EXTRA_FIRMWARE} \
	u-boot-fus \
"

EXTRA_OEMAKE:append = " -C ${S} O=${B}"
NBOOT_MAKE_TARGET ??= "nboot"

inherit deploy
inherit use-imx-security-controller-firmware

EXTRA_OEMAKE:append  = ' CROSS_COMPILE=${TARGET_PREFIX} V=1'
EXTRA_OEMAKE:append  = ' CC="${TARGET_PREFIX}gcc ${TOOLCHAIN_OPTIONS} ${@bb.utils.contains('DISTRO_FEATURES', 'ld-is-gold', ' -fuse-ld=bfd ', '', d)} ${DEBUG_PREFIX_MAP}"'
EXTRA_OEMAKE:append = ' HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_LDFLAGS}"'
EXTRA_OEMAKE:append = ' STAGING_INCDIR=${STAGING_INCDIR_NATIVE} STAGING_LIBDIR=${STAGING_LIBDIR_NATIVE}'

do_configure() {
	oe_runmake ${UBOOT_CONFIG_BASENAME}_defconfig
}

do_compile[depends] += " \
    ${@' '.join('%s:do_deploy' % r for r in '${IMX_EXTRA_FIRMWARE}'.split() )} \
    imx-atf:do_deploy \
"

do_compile:prepend() {
	for ddr_firmware in ${DDR_FIRMWARE_NAME}; do
		cp "${DEPLOY_DIR_IMAGE}/${ddr_firmware}" "${S}/board/F+S/NXP-Firmware/${ddr_firmware}"
	done

	if [ -n "${SECO_FIRMWARE_NAME}" ]; then
		cp "${DEPLOY_DIR_IMAGE}/${SECO_FIRMWARE_NAME}" "${S}/board/F+S/NXP-Firmware/${SECO_FIRMWARE_NAME}"
	fi
}

do_compile() {
	oe_runmake ${NBOOT_MAKE_TARGET}
}

do_install[noexec] = "1"

addtask deploy after do_compile
do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}/Firmware
	install -d ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware

	install -m 0644 ${B}/board/F+S/NXP-Firmware/* ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware
	install -m 0644 ${B}/nboot.fs ${DEPLOY_DIR_IMAGE}/Firmware/nboot_${UBOOT_CONFIG_BASENAME}_${PV}.fs
	ln -sf ${DEPLOY_DIR_IMAGE}/Firmware/nboot_${UBOOT_CONFIG_BASENAME}_${PV}.fs ${DEPLOY_DIR_IMAGE}/Firmware/nboot.fs

	for config in ${UBOOT_MACHINE}; do 
		cat ${DEPLOY_DIR_IMAGE}/Firmware/nboot.fs ${DEPLOY_DIR_IMAGE}/Firmware/uboot_${config}.fs > ${DEPLOY_DIR_IMAGE}/Firmware/flash_${config}.fs
	done
}
