SUMMARY = "Boot image tool for the U-Boot and NBoot copies on the boot medium"

require u-boot-fus-src-2024.04.inc
SRC_URI = "git://github.com/FSEmbedded/u-boot-fus;branch=master;protocol=https"
S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

# Built from the board defconfig; the architecture checked against
# /sys/bdinfo/arch at run time is compiled in.
PACKAGE_ARCH = "${MACHINE_ARCH}"
inherit features_check
REQUIRED_MACHINE_FEATURES = "fus-update-bootloader"

DEPENDS += "python3-native dtc-native bison-native libarchive-native xxd-native"

EXTRA_OEMAKE = '-C ${S} O=${B} CROSS_COMPILE="${TARGET_PREFIX}" \
    CC="${CC} ${CFLAGS} ${LDFLAGS}" HOSTCC="${BUILD_CC} ${BUILD_CFLAGS} ${BUILD_LDFLAGS}" \
    STRIP=true V=1'

do_configure() {
    oe_runmake ${UBOOT_CONFIG_BASENAME}_defconfig
}

do_compile() {
    oe_runmake fsimage
}

do_install() {
    install -d ${D}${sbindir}
    install -m 0700 ${B}/tools/fsimage/fsimage ${D}${sbindir}/fsimage
}
