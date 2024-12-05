# Copyright (C) 2024 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "AHAB implementation for F&S Boards based on i.MX9"

PROVIDES += "ahab"

LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:${DL_DIR}:"
SRC_URI += " file://fsimage.sh file://input.csf "

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(mx8|mx93)"

DEPENDS:append = " imx-cst-native nboot u-boot-fus xxd-native "
inherit deploy

do_configure() {
	if [ ! -f ${DL_DIR}/crts.tar.gz ]; then
		bbfatal "crts.tar.gz not found, exiting!"
	else
		bbnote "crts.tar.gz found, extracting..."
		cp ${DL_DIR}/crts.tar.gz ../
		tar -xf ../crts.tar.gz -C ../
	fi

	if [ ! -f ${DL_DIR}/keys.tar.gz ]; then
		bbfatal "keys.tar.gz not found, exiting!"
	else
		bbnote "keys.tar.gz found, extracting..."
		cp ${DL_DIR}/keys.tar.gz ../
		tar -xf ../keys.tar.gz -C ../
	fi

	cp ${WORKDIR}/input.csf ${B}/input_edited.csf
	sed -i "s/###crtsname###/${SRK_filename}/g" ${B}/input_edited.csf
	sed -i "s/###index###/${SRK_index}/g" ${B}/input_edited.csf
	sed -i "s/###revoke###/${SRK_revoke}/g" ${B}/input_edited.csf

	cp ${DEPLOY_DIR_IMAGE}/Firmware/nboot.fs ${B}/nboot_signed.fs
	cp ${DEPLOY_DIR_IMAGE}/Firmware/uboot-${MACHINE_ARCH}_secure_boot.fs ${B}/uboot-fsimx93_secure_boot_signed.fs
}

do_compile() {
	for file in nboot uboot-fsimx93_secure_boot
	do
		cat ${DEPLOY_DIR_IMAGE}/Firmware/${file}.fs | ${WORKDIR}/fsimage.sh | grep "i.MX Container: type: OEM" | while read line
		do
			container=$(echo $line | sed 's/.*Container offset: //' | sed 's/,.*//')
			signature=$(echo $line | sed 's/.*Signature block offset: //')
			cp ${B}/input_edited.csf ${B}/input_edited2.csf
			sed -i "s/###header###/0x${container}/g" ${B}/input_edited2.csf
			sed -i "s/###signature###/0x${signature}/g" ${B}/input_edited2.csf
			sed -i "s/###filename###/${file}_signed.fs/g" ${B}/input_edited2.csf
			cst -i ${B}/input_edited2.csf -o ${B}/${file}_signed.fs
			echo ${file}_signed.fs is signed
		done
	done
	cat ${B}/nboot_signed.fs ${B}/uboot-fsimx93_secure_boot_signed.fs > flash_signed.fs
}

do_install[noexec] = "1"

addtask deploy after do_compile

do_deploy() {
}
