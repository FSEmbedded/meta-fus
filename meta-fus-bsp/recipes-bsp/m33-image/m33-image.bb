#Copyright (c) 2024 F&S Elektronik Systeme GmbH
#SPDX-License-Identifier: BSD-3-Clause
SUMMARY = "M33 Image Provider for NBOOT"
DESCRIPTION = "This Recipe uses ${M33_IMAGE}.bb to build its output binary for NBOOT "

LICENSE = "CLOSED"
DEPENDS = "${M33_IMAGE}"

do_configure[noexec] = "1"

do_compile[noexec] = "1"

do_install[noexec] = "1"

do_deploy() {
	if [ ! -f ${DEPLOY_DIR_IMAGE}/${M33_IMAGE}.bin ]; then
		bberror "Failed to find ${M33_IMAGE}.bin"
		exit 1
	fi

	install -d ${DEPLOY_DIR_IMAGE}
	install -m 0644 ${DEPLOY_DIR_IMAGE}/${M33_IMAGE}.bin ${DEPLOY_DIR_IMAGE}/m33_image.bin
}

addtask deploy after do_install before do_build
PACKAGE_ARCH = "${MACHINE_ARCH}"
