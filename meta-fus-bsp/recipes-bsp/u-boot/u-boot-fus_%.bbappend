FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# merge the A/B feature fragment into the U-Boot defconfig only for
# machines with MACHINE_FEATURES "fus-update-ab"; non-A/B machines build
# unchanged. boot-mode dispatch (FUS_UPDATE_BOOT_MODE, default rootfs): the
# bootloader's compiled BOOT_FROM_MMC already boots rootfs mode; fus-ab.cfg
# (opt-in slot mode) overrides bootdir/.rootfs_part_* back to the vfat
# BOOT_A/B layout. the two fragments are mutually exclusive so
# CONFIG_PREBOOT is never doubly defined.
SRC_URI:append = " ${@bb.utils.contains('MACHINE_FEATURES', 'fus-update-ab', 'file://fus-ab.cfg', '', d)}"
SRC_URI:remove:boot-rootfs = "file://fus-ab.cfg"
SRC_URI:append:boot-rootfs = " ${@bb.utils.contains('MACHINE_FEATURES', 'fus-update-ab', 'file://fus-ab-bootrootfs.cfg', '', d)}"

# assert the merged defconfig can read the zstd squashfs, so a dropped
# fragment fails the build, not the bench.
inherit fus-selfcheck
FUS_SELFCHECK_KCONFIG:boot-rootfs = "CONFIG_FS_SQUASHFS CONFIG_ZSTD CONFIG_CMD_FS_GENERIC"
do_configure[postfuncs] += "${@bb.utils.contains('MACHINE_FEATURES', 'fus-update-ab', bb.utils.contains('FUS_UPDATE_BOOT_MODE', 'rootfs', 'fus_selfcheck_kconfig', '', d), '', d)}"

# The environment location shipped to userspace must match this bootloader.
do_configure[postfuncs] += "${@bb.utils.contains('MACHINE_FEATURES', 'fus-update-ab', 'fus_selfcheck_fw_env', '', d)}"

# Assert the slot-mode CONFIG_PREBOOT override targets the wks file's actual
# Root_A partition index, so a wks reorder fails the build, not the bench.
do_configure[postfuncs] += "${@bb.utils.contains('MACHINE_FEATURES', 'fus-update-ab', bb.utils.contains('FUS_UPDATE_BOOT_MODE', 'slot', 'fus_selfcheck_uboot_ab_env', '', d), '', d)}"
