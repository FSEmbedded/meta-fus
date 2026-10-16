PV = "2024.04"

#SRC_URI = "git://${DL_DIR}/u-boot-fus;branch=master;protocol=file"
SRC_URI = "git://github.com/FSEmbedded/u-boot-fus;branch=master;protocol=https"

# uboot-mkimage signs and packs images for the bootloader of the same tree.
require u-boot-fus-src-2024.04.inc
