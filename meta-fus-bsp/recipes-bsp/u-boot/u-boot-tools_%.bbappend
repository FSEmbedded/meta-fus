PV = "2024.04"

#SRC_URI = "git://${DL_DIR}/u-boot-fus;branch=master;protocol=file"
SRC_URI = "git://github.com/FSEmbedded/u-boot-fus;branch=master;protocol=https"

# uboot-mkimage signs and packs images for the bootloader built from the same
# source tree, so this revision must stay equal to the one in u-boot-fus_2024.04.bb.
SRCREV = "e16b783721e6f6135c34aaa9ba7ac1ecb7d1914e"
