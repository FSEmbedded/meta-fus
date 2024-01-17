# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the GPLv2 license
SUMMARY = "Linux Kernel for F&S GAL1 and SOLDERCORE8ULP boards"
DESCRIPTION = "Recipe created by bitbake-layers"
LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

inherit kernel

DEPENDS += "lzop-native bc-native"
COMPATIBLE_MACHINE = "(qemux86|qemux86-64|qemuarm|qemuarmv5|qemuarm64|qemuppc|qemumips|fsimx8ulp|rev0_fsimx8ulp)"

# SRC_URI and SRCREV are set in the bbappend file

S = "${WORKDIR}/git"

# This is necessary because there will be some debian packages created and
# these packages must be lower case. Basically we set CONFIG_LOCALVERSION to
# "-F+S". This appends the string "-F+S". Due to the string is upper case we
# need to set variable to convert it to lower case.
KERNEL_MODULE_PACKAGE_SUFFIX = "${@legitimize_package_name(d.getVar('KERNEL_VERSION'))}"

KBUILD_DEFCONFIG ?= "fsimx8ulp_defconfig"

do_configure() {
     oe_runmake -C ${S} O=${B} ARCH=${ARCH} ${KBUILD_DEFCONFIG}
}

