require linux-fus.inc

# CVE exclusions
include recipes-kernel/linux/cve-exclusion.inc
include recipes-kernel/linux/cve-exclusion_6.6.inc

# Build linux-fus-debug to get config depended
# cve information as spdx
do_deploy[depends] += " linux-fus-debug:do_deploy_spdx"

SRCBRANCH="master"
# v6.6.142-2.2.2-fus1.1
SRCREV = "b30960239414632d8161564f705da13ca97f4c56"

# LINUX_VERSION define should match to the kernel version referenced by SRC_URI and
# should be updated once patchlevel is merged.
LINUX_VERSION = "6.6.142"

KBUILD_DEFCONFIG:mx6-nxp-bsp = "fsimx6_defconfig"
KBUILD_DEFCONFIG:mx6sx-nxp-bsp = "fsimx6sx_defconfig"
KBUILD_DEFCONFIG:mx6ul-nxp-bsp = "fsimx6ul_defconfig"
KBUILD_DEFCONFIG:mx7ulp-nxp-bsp = "fsimx7ulp_defconfig"

KBUILD_DEFCONFIG:mx8mm-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mn-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mp-nxp-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8ulp-nxp-bsp = "fsimx8ulp_defconfig"
KBUILD_DEFCONFIG:mx93-nxp-bsp = "fsimx93_defconfig"

