#Copyright (c) 2024 F&S Elektronik Systeme GmbH
#SPDX-License-Identifier: BSD-3-Clause

SUMMARY = "F&S Realtime Daemon"
DESCRIPTION = "A M33 Image, that povides SRTM Services during runtime"
LICENSE = "CLOSED"

SRC_URI = "${FUS_MIRROR}/${BPN}/${BPN}-${MACHINE}_${PV}.bin"
SRC_URI[sha256sum] = "a8db5f50ff763b0b8ed26263b244e7c8991d67f9ed14e9f4bae71eff61d16a78"

do_configure[noexec] = "1"

do_compile[noexec] = "1"

do_install[noexec] = "1"

do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${WORKDIR}/${BPN}-${MACHINE}_${PV}.bin ${DEPLOY_DIR_IMAGE}/${BPN}-${MACHINE}_${PV}.bin
	install -m 0644 ${WORKDIR}/${BPN}-${MACHINE}_${PV}.bin ${DEPLOY_DIR_IMAGE}/${BPN}.bin
}

addtask deploy after do_install before do_build

COMPATIBLE_MACHINE = "(mx8ulp-nxp-bsp)"
PACKAGE_ARCH = "${MACHINE_ARCH}"
