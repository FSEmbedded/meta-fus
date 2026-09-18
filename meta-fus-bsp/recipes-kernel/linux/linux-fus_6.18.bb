require linux-fus.inc

# CVE exclusions
include recipes-kernel/linux/cve-exclusion.inc
include recipes-kernel/linux/cve-exclusion_6.18.inc

# Build linux-fus-debug to get config depended
# cve information as spdx
do_deploy[depends] += " linux-fus-debug:do_deploy_spdx"

SRCBRANCH = "linux-fus-6.18.x"
# v6.18.20-2.0.0-fus1.0
SRCREV = "d66b66381b2d4db2975e2facdd5e0ff6acd44869"

# LINUX_VERSION define should match to the kernel version referenced by SRC_URI and
# should be updated once patchlevel is merged.
LINUX_VERSION = "6.18.20"

KBUILD_DEFCONFIG:mx6-generic-bsp = "fsimx6_defconfig"
KBUILD_DEFCONFIG:mx6sx-generic-bsp = "fsimx6sx_defconfig"
KBUILD_DEFCONFIG:mx6ul-generic-bsp = "fsimx6ul_defconfig"
KBUILD_DEFCONFIG:mx7ulp-generic-bsp = "fsimx7ulp_defconfig"

KBUILD_DEFCONFIG:mx8mm-generic-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mn-generic-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8mp-generic-bsp = "fsimx8_defconfig"
KBUILD_DEFCONFIG:mx8ulp-generic-bsp = "fsimx8ulp_defconfig"
KBUILD_DEFCONFIG:mx93-generic-bsp = "fsimx93_defconfig"
KBUILD_DEFCONFIG:mx95-generic-bsp = "fsimx95_defconfig"

