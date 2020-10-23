# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license

LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=bbea815ee2795b2f4230826c0c6b8814"

inherit kernel

SUMMARY = "Linux Kernel for F&S i.MX6/7/8-based boards and modules"

DEPENDS += "lzop-native bc-native"

COMPATIBLE_MACHINE = "(mx6|mx7|mx8)"

SRC_URI = "file://linux-5.4.24-fus.tar.bz2"
S = "${WORKDIR}/linux-5.4.24-fus"

# We need to pass it as param since kernel might support more then one
# machine, with different entry points
KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT}"

FSCONFIG_mx6 = "fsimx6_defconfig"
FSCONFIG_mx6sx = "fsimx6sx_defconfig"
FSCONFIG_mx6ul = "fsimx6ul_defconfig"
FSCONFIG_mx7ulp = "fsimx7ulp_defconfig"
FSCONFIG_mx8mm = "fsimx8mm_defconfig"
FSCONFIG_mx8m = "fsimx8m_defconfig"
FSCONFIG_mx8mn = "fsimx8mn_defconfig"

do_extraunpack () {
	mv ${WORKDIR}/linux-fus/* ${S}/
}


kernel_do_configure_prepend() {
	install -m 0644 ${S}/arch/${ARCH}/configs/${FSCONFIG} ${WORKDIR}/defconfig
}
