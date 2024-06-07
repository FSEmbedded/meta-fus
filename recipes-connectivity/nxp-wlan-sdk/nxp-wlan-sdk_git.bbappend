FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://0001-Fix-sizeof-sa_data-on-Kernel-5-15-160.patch;striplevel=3"
# fsimx6ul does not support PCIE
EXTRA_OEMAKE:append:fsimx6ul=" CONFIG_PCIE8997=n CONFIG_PCIE9098=n"
