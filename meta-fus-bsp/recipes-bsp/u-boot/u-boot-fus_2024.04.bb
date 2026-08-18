# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

require u-boot-fus.inc

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM = "file://Licenses/README;md5=2ca5f2c35c8cc335f0a19756634782f1"

UBOOT_VERSION = "2024.04"
SRCBRANCH = "master"
# a revision above v2024.04-fus1.10 that carries the native A/B boot defaults
# (use_ab, rootfs-slot kernel load); files/fus-ab*.cfg add only the selector
# state on top.
SRCREV = "e16b783721e6f6135c34aaa9ba7ac1ecb7d1914e"
