# Copyright (C) 2022 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

SUMMARY = "Linux Kernel for F&S i.MX6/7/8/9-based boards and modules"

DEPENDS += "lzop-native bc-native"

COMPATIBLE_MACHINE = "(mx6|mx7|mx8|mx93)"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"


# Use this to build from local source
#SRC_URI = "git://${DL_DIR}/linux-fus;branch=${SRCBRANCH};protocol=file"
SRC_URI = "git://github.com/FSEmbedded/linux-fus;branch=${SRCBRANCH};protocol=https"


PV = "${LINUX_VERSION}"
S = "${WORKDIR}/git"

# We need to pass it as param since kernel might support more then one
# machine, with different entry points
KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT}"


# Prevent the galcore-module from beeing build, because it is already
# included in the F&S-Linux-Kernel as a build-in
RPROVIDES:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"
RREPLACES:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"
RCONFLICTS:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"

do_extraunpack () {
	mv ${WORKDIR}/linux-fus/* ${S}/
}

kernel_do_configure:prepend() {

	if [ -e ${WORKDIR}/custom_defconfig ]; then
		install -m 0644 ${WORKDIR}/custom_defconfig ${WORKDIR}/defconfig
	else
		install -m 0644 ${S}/arch/${ARCH}/configs/${KBUILD_DEFCONFIG} ${WORKDIR}/defconfig
	fi
	if [ -e ${WORKDIR}/*.cfg ]; then
		# Apply config fragments
		for file in "${WORKDIR}"/*.cfg; do
			cat "$file" >> ${WORKDIR}/defconfig
		done
	fi
}

kernel_do_configure:append() {
	rm -f ${B}/.scmversion ${S}/.scmversion
}

# Rename kernel image to be confirmed with naming convention
# for iMX8M based boards
kernel_do_deploy:append:mx8m-nxp-bsp() {
	# Set soft link to the kernel image and remove not needed links.
    # Use conform naming to documentation.
	cd ${DEPLOYDIR}
	ln -sf Image-${KERNEL_IMAGE_NAME}.bin Image-${MACHINE}
	rm -f Image-${MACHINE}.bin
	cd -
}
