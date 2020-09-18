# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license

LICENSE = "GPLv2"
LIC_FILES_CHKSUM = "file://COPYING;md5=bbea815ee2795b2f4230826c0c6b8814"

inherit kernel

SUMMARY = "Linux Kernel for F&S i.MX8-based boards and modules"

DEPENDS += "lzop-native bc-native"

COMPATIBLE_MACHINE = "(mx8)"

SRC_URI = "file://linux-5.4.24_2.1.0-fus.tar.bz2"
S = "${WORKDIR}/linux-5.4.24_2.1.0-fus"

# We need to pass it as param since kernel might support more then one
# machine, with different entry points
KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT}"

FSCONFIG_mx8mm = "fsimx8mm_defconfig"
FSCONFIG_mx8m = "fsimx8m_defconfig"
FSCONFIG_mx8mn = "fsimx8mn_defconfig"

# Prevent the galcore-module from beeing build, because it is already
# included in the F&S-Linux-Kernel as a build-in
RPROVIDES_kernel-image += "kernel-module-imx-gpu-viv"

do_extraunpack () {
	mv ${WORKDIR}/linux-fus/* ${S}/
}


kernel_do_configure_prepend() {
	install -m 0644 ${S}/arch/${ARCH}/configs/${FSCONFIG} ${WORKDIR}/defconfig
}
