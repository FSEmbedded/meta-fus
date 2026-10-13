# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

# Server access
SIGNING_SERVER_USER ?= "client"
SIGNING_SERVER_ADRESS ?= "172.17.0.1"
SIGNING_SERVER ?= "${SIGNING_SERVER_USER}@${SIGNING_SERVER_ADRESS}"

# Server environment
SIGNING_SERVER_STAGING_DIR ?= "/staging/"
SIGNING_SERVER_OUTPUT_DIR ?= "/output/"

# Change to UL if board is not using i.MX6ULL
IMX6UL_TYPE ?= "ULL"

# Processor specific parameters
SIGNING_CPU ?= ""
SIGNING_CPU:mx6-nxp-bsp = "1"
SIGNING_CPU:mx6sx-nxp-bsp = "2"
SIGNING_CPU:mx6ul-nxp-bsp = "${@bb.utils.contains(IMX6UL_TYPE, "ULL", 3, 4, d)}"
SIGNING_CPU:mx8mm-nxp-bsp = "6"
SIGNING_CPU:mx8mn-nxp-bsp = "7"
SIGNING_CPU:mx8mp-nxp-bsp = "8"
# not implemented in fs-secure-boot-tool
SIGNING_CPU:mx93-nxp-bsp = "9"

# Default values, should be changed by the calling recipe
SIGNING_TARGET_IMAGE ?= "unsigned.bin"
SIGNING_TARGET_IMAGE_LOCATION ?= "${B}/"

# Optional installation of signed images
FUS_SIGNED_IMAGES_INSTALL ?= "0"

# Separate package for signed images
PACKAGES:append = " ${PN}-signed-images"
FILES:${PN}-signed-images = "/boot/signed/*"

do_sign() {
    # Check if CPU override is set
    if [ -z "${SIGNING_CPU}" ]; then
        bbfatal "SIGNING_CPU not set for ${MACHINE}"
    fi

    # Remove old signed binaries if there are any
    ssh ${SIGNING_SERVER} "clean"

    # Copy all the Images on the Server and let it sign
    for IMAGE in ${SIGNING_TARGET_IMAGE}; do
        # strip subpath away, necessary for devicetrees
        IMAGE=$(basename "${IMAGE}")
        scp "${SIGNING_TARGET_IMAGE_LOCATION}${IMAGE}" "${SIGNING_SERVER}:${SIGNING_SERVER_STAGING_DIR}"
        ssh ${SIGNING_SERVER} "sign ${SIGNING_CPU} ${IMAGE}"
    done
    
    # Make sure deploy directory exists
    mkdir -p ${DEPLOY_DIR_IMAGE}/Signed_Images/${PN}-${PV}/
    
    # Copy all files that have been signed in this step
    files=$(ssh ${SIGNING_SERVER} "list")
    for file in $files; do
        scp -O ${SIGNING_SERVER}:/output/${file} ${DEPLOY_DIR_IMAGE}/Signed_Images/${PN}-${PV}/
    done

    # Clean up server side after operation
    ssh ${SIGNING_SERVER} "clean"
}

fakeroot do_install_signed_images() {
    # Check if Images should be in /boot directory
    if [ "${FUS_SIGNED_IMAGES_INSTALL}" != "1" ]; then
        bbnote "Skipping signed image installation for ${PN}"
        exit 0
    fi

    # get path were signed Images reside
    SIGNED_DIR="${DEPLOY_DIR_IMAGE}/Signed_Images/${PN}-${PV}"

    if [ ! -d "${SIGNED_DIR}" ]; then
        bbfatal "Signed images directory not found: ${SIGNED_DIR}"
    fi

    # Copy Images over
    install -d ${D}/boot/signed

    for file in "${SIGNED_DIR}"/*; do
        [ -f "$file" ] || continue
		cp --no-preserve=ownership "$file" ${D}/boot/signed/
    done
}

# Task definiion and switches
addtask sign after do_install before do_build
addtask install_signed_images after do_sign before do_package

python () {
    if bb.utils.contains('DISTRO_FEATURES', 'fus-image-signing', True, False, d):
        d.delVarFlag("do_sign", "noexec")
        d.delVarFlag("do_install_signed_images", "noexec")
    else:
        d.setVarFlag("do_sign", "noexec", "1")
        d.setVarFlag("do_install_signed_images", "noexec", "1")
}
