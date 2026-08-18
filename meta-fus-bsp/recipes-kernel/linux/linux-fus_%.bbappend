# assert the built .config carries the RAUC A/B prerequisites (dm-verity
# app image, squashfs rootfs, overlayfs /etc); a defconfig drift otherwise
# only shows up when the device fails to mount.
inherit fus-selfcheck
FUS_SELFCHECK_KCONFIG = "CONFIG_DM_VERITY CONFIG_SQUASHFS CONFIG_OVERLAY_FS"
do_configure[postfuncs] += "fus_selfcheck_kconfig"
