# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTON = "F&S Remote Desktop activation scripts"
LICENSE = "MIT"

LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " file://fsremote.sh "

do_install() {
   	install -d ${D}/${sbindir}

	install -m 0744 ${WORKDIR}/fsremote.sh ${D}/${sbindir}/fsremote.sh
}
