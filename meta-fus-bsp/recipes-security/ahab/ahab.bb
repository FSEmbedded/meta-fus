# Copyright (C) 2024 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "AHAB implementation for F&S Boards based on i.MX9"

PROVIDES += "ahab"

LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:${DL_DIR}:"

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(mx8|mx93)"

inherit deploy

do_configure() {
}

do_compile() {
}

do_install[noexec] = "1"

addtask deploy after do_compile

do_deploy() {
}
