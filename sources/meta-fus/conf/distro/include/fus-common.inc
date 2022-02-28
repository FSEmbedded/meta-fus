# Common settings for all F&S boards

UBOOT_ENTRYPOINT = "0x80800000"
UBOOT_ENTRYPOINT_mx6 = "0x10800000"
UBOOT_ENTRYPOINT_mx6sx = "0x80800000"
UBOOT_ENTRYPOINT_mx6ul = "0x80800000"
UBOOT_ENTRYPOINT_mx7ulp = "0x60800000"

PREFERRED_PROVIDER_u-boot_mx6 = "u-boot-fus"
PREFERRED_PROVIDER_u-boot_mx6ul = "u-boot-fus"
PREFERRED_PROVIDER_u-boot_mx6sx = "u-boot-fus"
PREFERRED_PROVIDER_u-boot_mx7ulp = "u-boot-fsimx7ulp"

PREFERRED_PROVIDER_virtual/bootloader_mx6 = "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader_mx6ul = "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader_mx6sx = "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader_mx7ulp = "u-boot-fsimx7ulp"

PREFERRED_PROVIDER_virtual/kernel_mx6 = "linux-fus"
PREFERRED_PROVIDER_virtual/kernel_mx6ul = "linux-fus"
PREFERRED_PROVIDER_virtual/kernel_mx6sx = "linux-fus"
PREFERRED_PROVIDER_virtual/kernel_mx7ulp = "linux-fus"

# The FSTYPES need to be set here with "=" instead of "?=",  otherwise they will get
# overwritten in meta-fsl-bsp-release/imx/meta-sdk/conf/distro/include/fsl-imx-base.inc
# Priorities should be like this:
# 1. IMAGE_FSTYPES_mx6ul  = "sdcard" (overwrites 2,3 and 4)
# 2. IMAGE_FSTYPES_mx6ul ?= "sdcard" (overwrites 3 and 4)
# 3. IMAGE_FSTYPES        = "sdcard" (overwrites 4) <-- fsl-imx-base.inc
# 4. IMAGE_FSTYPES       ?= "sdcard"
IMAGE_FSTYPES = "ubifs sdcard"

MKUBIFS_ARGS = "-m 2048 -e 126976 -c 2048"

# Remove image_types_fsl because there is a awk command which search after a
# point(.) in the devicetrees. But we have 2 points in the devicetree 
# picocom1.2.dtb so the awk command find the first point, so the new name is
# picocom1 instead of picocom1.2. And thats why you get an error at compile 
# time. Thats why we copy the image_types_fsl and rename it as image_types_fus
# and changed the line in the original file from
# "DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F "." '{print $1}'`" to
# "DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F ".dtb" '{print $1}'`"
# The Original file will be find in sources/meta-fsl-arm/classes/
# image_types_fsl.bbclass
IMAGE_CLASSES_remove = "image_types_fsl"
IMAGE_CLASSES += "image_types_fus"

# necessary, will be set in fsl-imx-preferred-env.inc
UBOOT_SUFFIX_mx6ul = "nb0"
UBOOT_MAKE_TARGET_mx6ul = ""

DISTRO_NAME = "F&S i.MX Release Distro"
SANITY_TESTED_DISTROS += "fedora-27"
