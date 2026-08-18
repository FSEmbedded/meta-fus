# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

inherit image_types

# The fixed `emmc-${MACHINE}.sysimg` flash-convenience alias (made in
# do_rename_wic_gz_image) can belong to only ONE image per deploy. Default ON
# (unchanged for existing images); an image that coexists with another in the
# same deploy sets this to "0" and is flashed via its ${IMAGE_BASENAME}-… name.
FUS_EMMC_SYSIMG_ALIAS ?= "1"

# rename wic image to be confirmed with naming convention
do_rename_wic_image() {
    cd ${IMGDEPLOYDIR}
    cp ${IMAGE_NAME}.wic ${IMAGE_NAME}.sysimg
    ln -sf ${IMAGE_NAME}.sysimg ${IMAGE_BASENAME}-${MACHINE}.sysimg
    # remove old images
    rm -f ${IMAGE_NAME}.wic
    rm -f ${IMAGE_BASENAME}-${MACHINE}.wic
    cd -
}

do_rename_wic_gz_image() {
    cd ${IMGDEPLOYDIR}
    gzip -d ${IMAGE_NAME}.wic.gz
    cp ${IMAGE_NAME}.wic ${IMAGE_NAME}.sysimg
    ln -sf ${IMAGE_NAME}.sysimg ${IMAGE_BASENAME}-${MACHINE}.sysimg
    if [ "${FUS_EMMC_SYSIMG_ALIAS}" = "1" ]; then
        ln -sf ${IMAGE_BASENAME}-${MACHINE}.sysimg emmc-${MACHINE}${IMAGE_NAME_SUFFIX}.sysimg
    fi
    # remove old images
    rm -f ${IMAGE_NAME}.wic
    rm -f ${IMAGE_BASENAME}-${MACHINE}.wic.gz
    cd -
}

IMAGE_POSTPROCESS_COMMAND += " \
    ${@bb.utils.contains('IMAGE_FSTYPES', 'wic', 'do_rename_wic_image;', '', d)} \
    ${@bb.utils.contains('IMAGE_FSTYPES', 'wic.gz', 'do_rename_wic_gz_image', '', d)} \
"
