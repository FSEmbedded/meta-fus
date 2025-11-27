# Copyright (C) 2022 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel  kernel-yocto

SUMMARY = "Experimental Mainline Linux Kernel with F&S patches "

DEPENDS += "lzop-native bc-native"

COMPATIBLE_MACHINE = "mx6|mx8"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI = "git://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/;branch=${SRCBRANCH};protocol=https"

PV = "${LINUX_VERSION}"

S = "${WORKDIR}/git"

# We need to pass it as param since kernel might support more then one
# machine, with different entry points
KERNEL_EXTRA_ARGS += "LOADADDR=${UBOOT_ENTRYPOINT}"

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
KCONFIG_MODE="--alldefconfig"







