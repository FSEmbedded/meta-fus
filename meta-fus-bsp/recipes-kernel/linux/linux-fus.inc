# Copyright (C) 2022 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel-yocto kernel

SUMMARY = "Linux Kernel for F&S i.MX6/7/8/9-based boards and modules"

DEPENDS += "lzop-native bc-native"

COMPATIBLE_MACHINE = "(mx6|mx7|mx8|mx93|mx95)"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"


# Use this to build from local source
#SRC_URI = "git://${DL_DIR}/linux-fus;branch=${SRCBRANCH};protocol=file"
SRC_URI = "git://github.com/FSEmbedded/linux-fus;branch=${SRCBRANCH};protocol=https"

PV = "${LINUX_VERSION}"

# We need to pass it as param since kernel might support more then one
# machine, with different entry points
KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT}"


# Prevent the galcore-module from beeing build, because it is already
# included in the F&S-Linux-Kernel as a build-in
RPROVIDES:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"
RREPLACES:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"
RCONFLICTS:${KERNEL_PACKAGE_NAME}-base += "kernel-module-imx-gpu-viv"

do_extraunpack () {
	mv ${UNPACKDIR}/${BP}/* ${S}/
}
addtask do_extraunpack after do_unpack before do_patch

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


# Tell to kernel class that we would like to use our defconfig to configure the kernel.
# Otherwise, the --allnoconfig would be used per default which leads to mis-configured
# kernel.
#
# This behavior happens when a defconfig is provided, the kernel-yocto configuration
# uses the filename as a trigger to use a 'allnoconfig' baseline before merging
# the defconfig into the build.
#
# If the defconfig file was created with make_savedefconfig, not all options are
# specified, and should be restored with their defaults, not set to 'n'.
# To properly expand a defconfig like this, we need to specify: KCONFIG_MODE="--alldefconfig"
# in the kernel recipe include.
KCONFIG_MODE = "--alldefconfig"

