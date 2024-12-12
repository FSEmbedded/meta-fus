# Copyright (C) 2024 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DEPENDS:append = " python3 dtc-native bison-native lzop-native xxd-native"

EXTRA_OEMAKE:append = " -C ${S} O=${B}"
NBOOT_MAKE_TARGET ??= "nboot"

inherit deploy
inherit use-imx-security-controller-firmware

EXTRA_OEMAKE:append  = ' CROSS_COMPILE=${TARGET_PREFIX} V=1'
EXTRA_OEMAKE:append  = ' CC="${TARGET_PREFIX}gcc ${TOOLCHAIN_OPTIONS} ${@bb.utils.contains('DISTRO_FEATURES', 'ld-is-gold', ' -fuse-ld=bfd ', '', d)} ${DEBUG_PREFIX_MAP}"'
EXTRA_OEMAKE:append = ' HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_LDFLAGS}"'
EXTRA_OEMAKE:append = ' STAGING_INCDIR=${STAGING_INCDIR_NATIVE} STAGING_LIBDIR=${STAGING_LIBDIR_NATIVE}'

NEED_M33_IMAGE = "${@bb.utils.contains('MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS', 'm33-image', 'true', 'false', d)}"
NEED_UPOWER = "${@bb.utils.contains('IMX_EXTRA_FIRMWARE', 'firmware-upower', 'true', 'false', d)}"

do_configure() {
	oe_runmake ${UBOOT_CONFIG_BASENAME}_defconfig
}

do_compile[depends] += " \
    ${@' '.join('%s:do_deploy' % r for r in '${IMX_EXTRA_FIRMWARE}'.split() )} \
    imx-atf:do_deploy \
    ${@bb.utils.contains('MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS', 'm33-image', 'm33-image:do_deploy', '', d)} \
"

do_compile:prepend() {
	for ddr_firmware in ${DDR_FIRMWARE_NAME}; do
		cp "${DEPLOY_DIR_IMAGE}/${ddr_firmware}" "${S}/board/F+S/NXP-Firmware/${ddr_firmware}"
	done

	if [ -n "${SECO_FIRMWARE_NAME}" ]; then
		cp "${DEPLOY_DIR_IMAGE}/${SECO_FIRMWARE_NAME}" "${S}/board/F+S/NXP-Firmware/${SECO_FIRMWARE_NAME}"
	fi

	if ${NEED_M33_IMAGE}; then
		cp "${DEPLOY_DIR_IMAGE}/m33_image.bin" "${S}/board/F+S/NXP-Firmware/m33_image.bin"
	fi

	if ${NEED_UPOWER}; then
		cp "${DEPLOY_DIR_IMAGE}/imx-boot-tools/upower.bin" "${S}/board/F+S/NXP-Firmware/upower.bin"
	fi
}

do_compile() {
	oe_runmake ${NBOOT_MAKE_TARGET}
}

do_install[noexec] = "1"

addtask deploy after do_compile

do_deploy[depends] += " u-boot-fus:do_deploy"
do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}/Firmware
	install -d ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware

	install -m 0644 ${B}/board/F+S/NXP-Firmware/* ${DEPLOY_DIR_IMAGE}/Firmware/NXP-Firmware
	install -m 0644 ${B}/nboot.fs ${DEPLOY_DIR_IMAGE}/Firmware/nboot-${UBOOT_CONFIG_BASENAME}-${PV}.fs
	cd ${DEPLOY_DIR_IMAGE}/Firmware/ && ln -sf nboot-${UBOOT_CONFIG_BASENAME}-${PV}.fs ./nboot.fs; cd -
	for config in ${UBOOT_CONFIG}; do
		cat ${DEPLOY_DIR_IMAGE}/Firmware/nboot.fs ${DEPLOY_DIR_IMAGE}/Firmware/uboot-${config}.fs > ${DEPLOY_DIR_IMAGE}/Firmware/flash_${config}.fs
	done
}
