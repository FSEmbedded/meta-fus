inherit image_types

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
	ln -sf ${IMAGE_BASENAME}-${MACHINE}.sysimg emmc-${MACHINE}${IMAGE_NAME_SUFFIX}.sysimg
	# remove old images
	rm -f ${IMAGE_NAME}.wic
	rm -f ${IMAGE_BASENAME}-${MACHINE}.wic.gz
	cd -
}

IMAGE_POSTPROCESS_COMMAND += " \
    ${@bb.utils.contains('IMAGE_FSTYPES', 'wic', 'do_rename_wic_image;', '', d)} \
    ${@bb.utils.contains('IMAGE_FSTYPES', 'wic.gz', 'do_rename_wic_gz_image', '', d)} \
"
