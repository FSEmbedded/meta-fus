require linux-fus.inc

# CVE exclusions
include recipes-kernel/linux/cve-exclusion.inc
include recipes-kernel/linux/cve-exclusion_6.18.inc

# Build linux-fus-debug to get config depended
# cve information as spdx
do_deploy[depends] += " linux-fus-debug:do_deploy_spdx"

SRCBRANCH = "linux-fus-6.18.x"
# v6.18.20-2.0.0-fus1.0
SRCREV = "26f17e7987a26e32d7c976273ba6c77828840f51"

# LINUX_VERSION define should match to the kernel version referenced by SRC_URI and
# should be updated once patchlevel is merged.
LINUX_VERSION = "6.18.20"

KBUILD_DEFCONFIG:mx6-nxp-bsp = "fsimx6_defconfig"
KBUILD_DEFCONFIG:mx6sx-nxp-bsp = "fsimx6sx_defconfig"
KBUILD_DEFCONFIG:mx6ul-nxp-bsp = "fsimx6ul_defconfig"
KBUILD_DEFCONFIG:mx7ulp-nxp-bsp = "fsimx7ulp_defconfig"

KBUILD_DEFCONFIG:mx8mm-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mn-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mp-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8ulp-nxp-bsp = "fsimx8ulp_defconfig"
KBUILD_DEFCONFIG:mx93-nxp-bsp = "fsimx93_defconfig"
KBUILD_DEFCONFIG:mx95-nxp-bsp = "fsimx95_defconfig"

