require linux-fus.inc

# Based on Version fslc-6.6.69-2.2.0
SRCBRANCH="linux-fus-6.6.x"
SRCREV = "3a6ea4b31c038b885ae7e17d78622c749091e357"

# LINUX_VERSION define should match to the kernel version referenced by SRC_URI and
# should be updated once patchlevel is merged.
LINUX_VERSION = "6.6.69"

KBUILD_DEFCONFIG:mx6-nxp-bsp = "fsimx6_defconfig"
KBUILD_DEFCONFIG:mx6sx-nxp-bsp = "fsimx6sx_defconfig"
KBUILD_DEFCONFIG:mx6ul-nxp-bsp = "fsimx6ul_defconfig"
KBUILD_DEFCONFIG:mx7ulp-nxp-bsp = "fsimx7ulp_defconfig"

KBUILD_DEFCONFIG:mx8mm-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mn-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mp-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8ulp-nxp-bsp = "fsimx8ulp_defconfig"
KBUILD_DEFCONFIG:mx93-nxp-bsp = "fsimx93_defconfig"


