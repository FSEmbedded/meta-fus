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

### default values
SRK_index ?= "0"
SRK_filename ?= "SRK1_sha384_secp384r1_v3_usr_crt.pem"
SRK_revoke ?= "0x0"

### NBoot Binary
nboot_file ?= "nboot.fs"

### script files
Update_Files ?= ""
Update_Scripts ?= ""

### sign linux if fitimage is there
SIGN_LINUX = "${@bb.utils.contains('KERNEL_CLASSES', 'kernel-fitimage', 'true', 'false', d)}"

DEPENDS:append = " imx-cst-native u-boot-fus xxd-native u-boot-tools-native linux-fus optee-os imx-atf"
inherit deploy

### recipe should alway run, do not stamp the tasks
python __anonymous () {
    tasks = d.keys()
    for t in tasks:
        d.setVarFlag(t, "nostamp", "1")
}

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

	if [ -f ${DL_DIR}/${nboot_file} ]; then
		cp ${DL_DIR}/${nboot_file} ${B}/nboot_signed.fs
	elif [ -f ${DEPLOY_DIR_IMAGE}/Firmware/${nboot_file} ]; then
		cp ${DEPLOY_DIR_IMAGE}/Firmware/${nboot_file} ${B}/nboot_signed.fs
	fi
	cp ${DEPLOY_DIR_IMAGE}/Firmware/uboot-${MACHINE_ARCH}.fs ${B}/uboot-${MACHINE_ARCH}_signed.fs

	if ${SIGN_LINUX}; then
		cp ${WORKDIR}/os_cntr.cfg ${B}/os_cntr_edited.cfg
		cp ${DEPLOY_DIR_IMAGE}/fitImage-${MACHINE_ARCH}.bin ${B}/
	fi

	### skript kopieren
	for i in ${Update_Files}; do
		cp ${DL_DIR}/${i} ${WORKDIR}
	done
	for i in ${Update_Scripts}; do
		cp ${DL_DIR}/${i} ${WORKDIR}
	done
}

do_compile() {
	if [ -f ${B}/nboot_signed.fs ]; then
		image_list="nboot uboot-${MACHINE_ARCH}"
	else
		image_list="uboot-${MACHINE_ARCH}"
	fi

	for file in ${image_list}
	do
		### we need container and signature offsets, we parse the first from the fsimage.sh output and get the second from the container header
		cat ${B}/${file}_signed.fs | ${WORKDIR}/fsimage.sh | grep "IMX Container Header" | grep -v "NXP signed" | while read line
		do
			container_hex=0x$(echo $line | sed 's/.*: 0*//' | sed 's/ .*//')
			container_dec=$(printf %d $container_hex)
			signature_rel_hex=0x$(xxd -e -l 2 -s $(expr $container_dec + 12) ${B}/${file}_signed.fs  | awk '{print $2}'); 
			signature_rel_dec=$(printf %d $signature_rel_hex);
			signature_dec=$(expr $container_dec + $signature_rel_dec);
			signature_hex=0x$(printf %x $signature_dec);

			cp ${B}/input_edited.csf ${B}/input_edited2.csf
			sed -i "s/###header###/${container_hex}/g" ${B}/input_edited2.csf
			sed -i "s/###signature###/${signature_hex}/g" ${B}/input_edited2.csf
			sed -i "s/###filename###/${file}_signed.fs/g" ${B}/input_edited2.csf

			bbnote $(cat  ${B}/input_edited2.csf)

			cst -i ${B}/input_edited2.csf -o ${B}/${file}_signed.fs
			echo ${file}_signed.fs is signed
		done
	done
	if [ -f ${B}/nboot_signed.fs ]; then
		cat ${B}/nboot_signed.fs ${B}/uboot-${MACHINE_ARCH}_signed.fs > flash_signed.fs
	fi

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

	for i in ${Update_Files}; do
		cp ${WORKDIR}/os_cntr.cfg ${B}/script.cfg #alles von W zu B
		sed -i "s/###fitimage###/${i}.scr/g" ${B}/script.cfg
		mkimage -T script -n "Bootscript" -C none -d ${WORKDIR}/${i} ${B}/${i}.scr
		mkimage -n script.cfg -T imx8image -d ${B}/${i}.scr ${B}/${i}.cntr >> ${WORKDIR}/scripts.log
		
		cp ${B}/input_edited.csf ${B}/input_edited3.csf
		sed -i "s/###signature###/0x90/g" ${B}/input_edited3.csf
		sed -i "s/###header###/0x0/g" ${B}/input_edited3.csf
		sed -i "s/###filename###/${i}.scr.cntr/g" ${B}/input_edited3.csf

		cst -i ${B}/input_edited3.csf -o ${B}/${i}.scr.cntr.signed
	done
	for i in ${Update_Scripts}; do
		mkimage -n script.cfg -T imx8image -d ${WORKDIR}/${i}.scr ${B}/${i}.cntr >> ${WORKDIR}/scripts.log

		cp ${B}/input_edited.csf ${B}/input_edited3.csf
		sed -i "s/###signature###/0x90/g" ${B}/input_edited3.csf
		sed -i "s/###header###/0x0/g" ${B}/input_edited3.csf
		sed -i "s/###filename###/${i}.scr.cntr/g" ${B}/input_edited3.csf

		cst -i ${B}/input_edited3.csf -o ${B}/${i}.cntr.signed
	done
}

do_install[noexec] = "1"

addtask deploy after do_compile

do_deploy() {
	install -d ${DEPLOY_DIR_IMAGE}/Secure
	install -m 0644 ${B}/uboot-${MACHINE_ARCH}_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
	if [ -f ${B}/nboot_signed.fs ]; then
		install -m 0644 ${B}/nboot_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
		install -m 0644 ${B}/flash_signed.fs ${DEPLOY_DIR_IMAGE}/Secure
	fi
	if ${SIGN_LINUX}; then
		install -m 0644 ${B}/os_cntr_signed.cntr ${DEPLOY_DIR_IMAGE}/Secure
	fi

	for i in ${Update_Files}; do
		name=$(echo ${i} | sed "s/\..*//g")_signed.scr
		cp ${B}/${i}.scr.cntr.signed ${DEPLOY_DIR_IMAGE}/Secure/${name}
	done
	for i in ${Update_Scripts}; do
		name=$(echo ${i} | sed "s/\..*//g")_signed.scr
		cp ${B}/${i}.cntr.signed ${DEPLOY_DIR_IMAGE}/Secure/${name}
	done
}
