SUMMARY = "Reproducibly-sized vfat boot image (kernel + DTBs + TEE) for the RAUC boot slot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# standalone vfat image holding the same files the WIC bootimg-partition
# writes into the factory BOOT_x partition (${IMAGE_BOOT_FILES}). the RAUC
# boot slot is written raw, so the image is the byte-for-byte slot content
# and the install can be verified by read-back. partition size comes from
# the shared layout contract.

inherit deploy nopackages

require conf/include/fus-update-layout.inc

# mkfs.vfat (dosfstools) + mcopy/mmd (mtools); the boot files must be deployed.
DEPENDS = "dosfstools-native mtools-native virtual/kernel"

do_deploy[depends] += "virtual/kernel:do_deploy"
do_deploy[depends] += "${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-os:do_deploy', '', d)}"

# output is machine specific (IMAGE_BOOT_FILES + kernel are per machine).
PACKAGE_ARCH = "${MACHINE_ARCH}"

S = "${WORKDIR}"

# fixed FAT volume serial removes the one random field mkfs.vfat would
# generate per build; the image is still not bit-identical across builds,
# mcopy stamps directory entries with wall-clock time.
FUS_BOOT_VOLID ?= "FACEB007"

# slot size in 1 KiB blocks for mkfs.vfat -C (bitbake's shell parser
# rejects $(( )) arithmetic, so derive it in python).
FUS_BOOT_BLOCKS_1K = "${@int(d.getVar('FUS_UPDATE_SIZE_BOOT_MIB')) * 1024}"

do_deploy() {
    local img="${DEPLOYDIR}/fus-boot-${MACHINE}.vfat"

    rm -f "${img}"
    mkfs.vfat -i "${FUS_BOOT_VOLID}" -n "BOOT" -C "${img}" ${FUS_BOOT_BLOCKS_1K}

    for entry in ${IMAGE_BOOT_FILES}; do
        # support the optional "src;dst" form (dst is the path inside the FAT).
        src="${entry%%;*}"
        dst="${entry##*;}"
        [ "${dst}" = "${entry}" ] && dst="${src}"

        if [ ! -e "${DEPLOY_DIR_IMAGE}/${src}" ]; then
            bbwarn "fus-update-boot-image: ${src} not found in DEPLOY_DIR_IMAGE, skipping"
            continue
        fi

        # create the parent directory inside the FAT for subdir destinations.
        case "${dst}" in
            */*) mmd -i "${img}" "::${dst%/*}" 2>/dev/null || true ;;
        esac

        mcopy -i "${img}" "${DEPLOY_DIR_IMAGE}/${src}" "::${dst}"
    done

    bbnote "fus-update-boot-image: built ${img} (${FUS_UPDATE_SIZE_BOOT_MIB} MiB)"
}
addtask deploy after do_compile before do_build
