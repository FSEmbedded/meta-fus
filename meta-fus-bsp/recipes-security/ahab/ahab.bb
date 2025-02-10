# Copyright (C) 2024 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "AHAB implementation for F&S Boards based on i.MX9"

PROVIDES += "ahab"

LICENSE = "CLOSED"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:${DL_DIR}:"
SRC_URI += " file://fsimage.sh file://input.csf file://os_cntr.cfg  "

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

PACKAGE_ARCH = "${MACHINE_ARCH}"
COMPATIBLE_MACHINE = "(mx8|mx93)"

SRK_index ?= "0"
SRK_filename ?= "SRK1_sha384_secp384r1_v3_usr_crt.pem"
SRK_revoke ?= "0x0"

SIGN_LINUX = "${@bb.utils.contains('KERNEL_CLASSES', 'kernel-fitimage', 'true', 'false', d)}"

DEPENDS:append = " imx-cst-native nboot u-boot-fus xxd-native u-boot-tools-native linux-fus optee-os imx-atf"
inherit deploy

do_configure[depends] += " linux-fus:do_deploy "
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
	cp ${DEPLOY_DIR_IMAGE}/Firmware/uboot-${MACHINE_ARCH}_secure_boot.fs ${B}/uboot-${MACHINE_ARCH}_secure_boot_signed.fs

	if ${SIGN_LINUX}; then
		cp ${WORKDIR}/os_cntr.cfg ${B}/os_cntr_edited.cfg
		cp ${DEPLOY_DIR_IMAGE}/fitImage-${MACHINE_ARCH}.bin ${B}/
	fi
}

do_compile() {
	for file in nboot uboot-${MACHINE_ARCH}_secure_boot
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
	cat ${B}/nboot_signed.fs ${B}/uboot-${MACHINE_ARCH}_secure_boot_signed.fs > flash_signed.fs

	if ${SIGN_LINUX}; then
		sed -i "s/###fitimage###/fitImage-${MACHINE_ARCH}.bin/g" ${B}/os_cntr_edited.cfg
		mkimage -n ${B}/os_cntr_edited.cfg -T imx8image -d ${DEPLOY_DIR_IMAGE}/fitImage-${MACHINE_ARCH}.bin ${B}/os_cntr.cntr > os_cntr.log
		cp ${B}/input_edited.csf ${B}/input_edited2.csf
		grep "CST" os_cntr.log | while read line
		do
			if [[ $line == *"Signature"* ]]
			then
				signature=0x$(echo $line | sed "s/.*0x//")
				sed -i "s/###signature###/${signature}/g" ${B}/input_edited2.csf
			else
				container=0x$(echo $line | sed "s/.*0x//")
				sed -i "s/###header###/${container}/g" ${B}/input_edited2.csf
			fi
		done
		sed -i "s/###filename###/os_cntr.cntr/g" ${B}/input_edited2.csf
		cst -i ${B}/input_edited2.csf -o ${B}/os_cntr_signed.cntr
	fi

	### jetzt noch das update script
}

do_install[noexec] = "1"

addtask deploy after do_compile

do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}/Secure
	install -m 0644 ${B}/uboot-${MACHINE_ARCH}_secure_boot_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
	install -m 0644 ${B}/nboot_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
	install -m 0644 ${B}/flash_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
	if ${SIGN_LINUX}; then
		install -m 0644 ${B}/os_cntr_signed.cntr ${DEPLOY_DIR_IMAGE}/Secure
	fi
}
