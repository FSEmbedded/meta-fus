# image-scope variable defaults and validation for the F&S A/B update
# standard image (RAUC, persistent /data partition, /etc in overlayfs via
# overlayfs-etc.bbclass). activate in an image recipe: inherit fus-update
#
# distro policy lives in conf/distro/include/fus-update-features.inc,
# machine policy in conf/machine/include/fus-update-emmc.inc, and the
# partition/layout identity in conf/include/fus-update-layout.inc, so
# non-image recipes can read them without inheriting here.

# build-time hardening assertions over the system rootfs.
inherit fus-selfcheck

# ── WIC ──────────────────────────────────────────────────────────────
# hard-assign WKS_FILE: the machine config sets SOC_DEFAULT_WKS_FILE to
# the non-A/B template, which would win against a weak default. the two
# mode axes (FUS_UPDATE_BOOT_MODE x FUS_UPDATE_APP_MODE) select one of
# four kickstarts:
#   slot   + slot             → fus-update-emmc.wks.in
#   slot   + rootfs/container → fus-update-emmc-noappslot.wks.in
#   rootfs + slot             → fus-update-emmc-bootrootfs.wks.in
#   rootfs + rootfs/container → fus-update-emmc-bootrootfs-noappslot.wks.in
def fus_update_wks_file(d):
    boot_rootfs = d.getVar('FUS_UPDATE_BOOT_MODE') == 'rootfs'
    app_slot = d.getVar('FUS_UPDATE_APP_MODE') == 'slot'
    if boot_rootfs:
        return 'fus-update-emmc-bootrootfs.wks.in' if app_slot \
            else 'fus-update-emmc-bootrootfs-noappslot.wks.in'
    return 'fus-update-emmc.wks.in' if app_slot \
        else 'fus-update-emmc-noappslot.wks.in'
FUS_UPDATE_WKS_DEFAULT          ?= "${@fus_update_wks_file(d)}"
WKS_FILE                        = "${FUS_UPDATE_WKS_DEFAULT}"

# the F&S BSP trims WKS_FILE_DEPENDS to an ext4-only set; re-add the
# squashfs tool for the read-only Root slots.
WKS_FILE_DEPENDS:append         = " squashfs-tools-native"

# ── squashfs compression ────────────────────────────────────────────
SQUASHFS_COMPRESSOR             ?= "zstd"
SQUASHFS_EXTRA_IMAGECMD         ?= "-comp ${SQUASHFS_COMPRESSOR} -Xcompression-level 19"

# also deploy a standalone squashfs: the RAUC bundle uses it as the rootfs
# slot image. same compressor for parity with the on-disk slot.
IMAGE_FSTYPES:append            = " squashfs"
EXTRA_IMAGECMD:squashfs         = "${SQUASHFS_EXTRA_IMAGECMD}"

# the bundle-only build path never runs wic, so check slot fit here.
do_image_squashfs[postfuncs]   += "fus_selfcheck_rootfs_slot_fit"

# expose the compressor command and the layout identity to the wic
# kickstart parser.
WICVARS:append                  = " SQUASHFS_EXTRA_IMAGECMD \
    FUS_UPDATE_PARTLABEL_BOOT_A FUS_UPDATE_PARTLABEL_BOOT_B \
    FUS_UPDATE_PARTLABEL_ROOT_A FUS_UPDATE_PARTLABEL_ROOT_B \
    FUS_UPDATE_PARTLABEL_APP_A FUS_UPDATE_PARTLABEL_APP_B \
    FUS_UPDATE_PARTLABEL_DATA \
    FUS_UPDATE_SIZE_BOOT_MIB FUS_UPDATE_SIZE_ROOT_MIB \
    FUS_UPDATE_SIZE_APP_MIB FUS_UPDATE_SIZE_DATA_MIB"

# slot mode only: the wic App_A/B slots are populated (rawcopy) from the
# standalone app slot image, so it must be deployed before do_image_wic.
do_image_wic[depends]           += "${@bb.utils.contains('FUS_UPDATE_APP_MODE', 'slot', 'fus-app-image:do_image_complete', '', d)}"

# ── overlayfs (poky overlayfs-etc.bbclass) ──────────────────────────
# the preinit mounts the data device before udev runs and the eMMC index
# varies per board, so mount by PARTLABEL. requires util-linux mount
# (pulled via the machine include); busybox mount cannot resolve PARTLABEL=.
OVERLAYFS_ETC_MOUNT_POINT       ?= "${FUS_UPDATE_DATA_MOUNT}"
OVERLAYFS_ETC_FSTYPE            ?= "${FUS_UPDATE_DATA_FSTYPE}"
OVERLAYFS_ETC_DEVICE            ?= "PARTLABEL=${FUS_UPDATE_PARTLABEL_DATA}"
OVERLAYFS_ETC_MOUNT_OPTIONS     ?= "${FUS_UPDATE_DATA_MOUNT_OPTIONS}"

# named mount point for later overlayfs.bbclass consumers.
OVERLAYFS_MOUNT_POINT[data]     ?= "${FUS_UPDATE_DATA_MOUNT}"

# F&S U-Boot's native A/B selector boots with init=/sbin/preinit.sh. keep
# /sbin/init = the real init (systemd), generate the overlay preinit as
# /sbin/preinit and expose it under the expected name via a
# /sbin/preinit.sh link.
OVERLAYFS_ETC_USE_ORIG_INIT_NAME = "0"

# the rootfs is a read-only squashfs, so bake the persistent mount point
# into the image and tell overlayfs-etc not to create dirs at runtime.
OVERLAYFS_ETC_CREATE_MOUNT_DIRS = "0"
ROOTFS_POSTPROCESS_COMMAND      += "fus_update_link_preinit_sh; fus_update_create_data_mountpoint; fus_update_create_app_mountpoint;"
fus_update_link_preinit_sh() {
    ln -sf preinit ${IMAGE_ROOTFS}${base_sbindir}/preinit.sh
}
fus_update_create_data_mountpoint() {
    install -d ${IMAGE_ROOTFS}${FUS_UPDATE_DATA_MOUNT}
}
# provide the app prefix in the read-only rootfs per app mode:
#   slot      — empty mount point for the active App_A/B partition.
#   container — empty merge base; the runtime's mount unit overlays the
#               loop-mounted app image from /data over it at boot.
#   rootfs    — nothing: the payload package is baked under the prefix.
fus_update_create_app_mountpoint() {
    case "${FUS_UPDATE_APP_MODE}" in
        slot|container)
            install -d ${IMAGE_ROOTFS}${FUS_UPDATE_APP_MOUNT}
            ;;
        rootfs)
            : # payload baked under the prefix by the app package
            ;;
        *)
            # a new app mode must decide its rootfs shape here explicitly.
            bbfatal "fus-update: no app mount shape wired for FUS_UPDATE_APP_MODE='${FUS_UPDATE_APP_MODE}'"
            ;;
    esac
}

# ── app-payload / health-probe assertions (over the system rootfs) ──
# container: the probe ships in the launcher package into this rootfs.
ROOTFS_POSTPROCESS_COMMAND:append:app-container = " fus_selfcheck_health_probe;"
ROOTFS_POSTPROCESS_COMMAND:append:app-container = " fus_selfcheck_install_door;"
# door-gated, not mode-gated: rootfs mode takes the same confirm door.
ROOTFS_POSTPROCESS_COMMAND:append = "${@bb.utils.contains('FUS_UPDATE_INSTALL_DOOR', 'fsupdater', ' fus_selfcheck_confirm_ordering;', '', d)}"
# rootfs mode: the payload rides the main rootfs, so its contract is
# checked here; the other modes assert it from their app-image build.
ROOTFS_POSTPROCESS_COMMAND:append:app-rootfs    = " fus_selfcheck_app_payload;"

# ── kernel + DTBs into rootfs /boot (boot mode rootfs only) ─────────
# no BOOT_A/B partitions in this mode; U-Boot loads kernel and DTB from
# /boot inside the rootfs squashfs. bake /boot from the same
# IMAGE_BOOT_FILES list (and src;dst semantics) the vfat boot slot uses,
# so the dst names match U-Boot's ${bootfile}/${bootfdt}.
ROOTFS_POSTPROCESS_COMMAND:append:boot-rootfs = " fus_update_bake_boot_into_rootfs; fus_update_assert_boot_in_rootfs;"
do_rootfs[depends] += "${@bb.utils.contains('FUS_UPDATE_BOOT_MODE', 'rootfs', 'virtual/kernel:do_deploy', '', d)}"
do_rootfs[depends] += "${@'optee-os:do_deploy' if d.getVar('FUS_UPDATE_BOOT_MODE') == 'rootfs' and bb.utils.contains('MACHINE_FEATURES', 'optee', True, False, d) else ''}"
fus_update_bake_boot_into_rootfs() {
    install -d ${IMAGE_ROOTFS}/boot
    for entry in ${IMAGE_BOOT_FILES}; do
        # support the optional "src;dst" form (dst is the path under /boot).
        src="${entry%%;*}"
        dst="${entry##*;}"
        [ "${dst}" = "${entry}" ] && dst="${src}"

        if [ ! -e "${DEPLOY_DIR_IMAGE}/${src}" ]; then
            bbwarn "fus-update: boot file ${src} not in DEPLOY_DIR_IMAGE, skipping"
            continue
        fi

        case "${dst}" in
            */*) install -d "${IMAGE_ROOTFS}/boot/${dst%/*}" ;;
        esac
        install -m 0644 "${DEPLOY_DIR_IMAGE}/${src}" "${IMAGE_ROOTFS}/boot/${dst}"
    done
}

# fail the build (not the bench) if the bake above did not produce a
# loadable kernel + DTB.
fus_update_assert_boot_in_rootfs() {
    if [ ! -f "${IMAGE_ROOTFS}/boot/${KERNEL_IMAGETYPE}" ]; then
        bbfatal "fus-update(boot-rootfs): ${IMAGE_ROOTFS}/boot/${KERNEL_IMAGETYPE} is \
missing — the bootloader cannot load the kernel from the rootfs. Check IMAGE_BOOT_FILES."
    fi
    if [ -n "${KERNEL_DEVICETREE}" ] && ! ls ${IMAGE_ROOTFS}/boot/*.dtb >/dev/null 2>&1; then
        bbfatal "fus-update(boot-rootfs): no device tree (*.dtb) under \
${IMAGE_ROOTFS}/boot although this machine configures one — the bootloader cannot \
load a DTB. Check IMAGE_BOOT_FILES."
    fi
}

# ── image features (image-scope, not distro policy) ─────────────────
IMAGE_FEATURES:append           = " read-only-rootfs overlayfs-etc"

# every fus-update image gets the A/B runtime floor; the example app and
# the per-mode mechanism are image-level choices and not pulled here.
IMAGE_INSTALL:append            = " packagegroup-fus-update-base"

# opt-in health layer, mode-invariant.
IMAGE_INSTALL:append            = " ${@bb.utils.contains('FUS_UPDATE_HEALTH', '1', 'fus-health', '', d)}"

# ── validation ──────────────────────────────────────────────────────
python __anonymous() {
    # machine capability — owned by fus-update-emmc.inc, not this class. skip
    # rather than fail: an anonymous fatal would stop every parse for the
    # machine, including builds this image has nothing to do with.
    if not bb.utils.contains("MACHINE_FEATURES", "fus-update-ab", True, False, d):
        raise bb.parse.SkipRecipe(
            "machine %s does not declare update support -- the A/B update is available on the\n"
            "eMMC boards whose machine conf requires conf/machine/include/fus-update-emmc.inc;\n"
            "NAND boards are not supported" % d.getVar("MACHINE"))

    # image-level variables that must resolve to something non-empty, each with
    # the place that provides it. an empty value is nearly always a missing
    # include in the build configuration rather than a defect in the image, so
    # the failure names the line that fixes it instead of only the variable.
    from_config = ("the update policy is not active in this build -- it comes "
                   "with the fus distro family; on a foreign DISTRO require it "
                   "explicitly:\n  require conf/distro/include/fus-update-features.inc\n"
                   "(it pulls in the layout include this variable comes from)")
    required_vars = [
        ("WKS_FILE", from_config),
        ("OVERLAYFS_ETC_MOUNT_POINT", from_config),
        ("OVERLAYFS_ETC_FSTYPE", from_config),
        ("OVERLAYFS_ETC_DEVICE", from_config),
        ("RAUC_BUNDLE_COMPATIBLE", from_config),
        ("FUS_UPDATE_DATA_MOUNT", from_config),
        ("FUS_UPDATE_PARTLABEL_ROOT_A", from_config),
        ("FUS_UPDATE_PARTLABEL_DATA", from_config),
    ]
    # no BOOT_A partition in boot mode rootfs.
    if d.getVar("FUS_UPDATE_BOOT_MODE") != "rootfs":
        required_vars.append(("FUS_UPDATE_PARTLABEL_BOOT_A", from_config))
    for name, hint in required_vars:
        if not d.getVar(name):
            bb.fatal("fus-update.bbclass: required variable %s is empty -- %s" % (name, hint))

    # distro policy — owned by fus-update-features.inc, not this class.
    distro_features = (d.getVar("DISTRO_FEATURES") or "").split()
    missing_distro = [f for f in ("overlayfs", "systemd", "rauc")
                      if f not in distro_features]
    if missing_distro:
        bb.fatal(
            "fus-update.bbclass: DISTRO_FEATURES missing %s. they come with "
            "the fus distro family; on a foreign DISTRO add:\n"
            "  require conf/distro/include/fus-update-features.inc"
            % " ".join(missing_distro)
        )
}

# a package manager cannot write on this read-only rootfs, and the upstream
# conflict check is inactive once USE_ORIG_INIT_NAME is off. refused at rootfs
# time: local.conf often adds it, and a parse-time fatal stops every build.
python fus_update_refuse_package_management() {
    if bb.utils.contains("IMAGE_FEATURES", "package-management", True, False, d):
        bb.fatal(
            "fus-update.bbclass: IMAGE_FEATURES contains 'package-management', "
            "which cannot work on this line's read-only rootfs. Nothing else "
            "catches this: the upstream conflict check is inactive here. Drop "
            "it from the image and from EXTRA_IMAGE_FEATURES in local.conf, or "
            "build a writable-rootfs image outside this class."
        )
}
do_rootfs[prefuncs] += "fus_update_refuse_package_management"
