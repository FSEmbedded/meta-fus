# partition-identity contract for the F&S A/B update standard image —
# single source of truth for the persistent mount point, the GPT partition
# names and the slot sizes. globally parsed (required from the distro
# include) so every consumer reads the same values without inheriting the
# image class.
#
# keep these values distro-global, not per machine: allarch recipes bake
# them into machine-shared packages. a value that must vary per machine
# belongs in the machine include.

# persistent data partition — runtime mount point, filesystem, mount opts.
FUS_UPDATE_DATA_MOUNT          ?= "/data"
FUS_UPDATE_DATA_FSTYPE         ?= "ext4"
# nodev,nosuid,noexec: /data holds only data, never anything executed
# directly; the container app squashfs is loop-mounted, so noexec here is
# orthogonal to the loop device's exec permission. feeds both the
# overlayfs-etc preinit mount and the data.mount unit.
FUS_UPDATE_DATA_MOUNT_OPTIONS  ?= "defaults,noatime,nodev,nosuid,noexec"

# app payload lives under /opt/<package>; the mount/symlink/bake point for
# all three update modes. the binary is at <mount>/usr/bin.
FUS_UPDATE_APP_MOUNT           ?= "/opt/fus-app"
FUS_UPDATE_HEALTH_DIR          ?= "/etc/fus-app/health.d"

# GPT partition names == /dev/disk/by-partlabel/<name>; must match the F&S
# U-Boot native A/B expectation (include/configs/<machine>.h). keep names
# plain alphanumeric: the systemd mount unit derives its name and the
# by-partlabel device from them without extra escaping.
FUS_UPDATE_PARTLABEL_BOOT_A    ?= "BOOT_A"
FUS_UPDATE_PARTLABEL_BOOT_B    ?= "BOOT_B"
FUS_UPDATE_PARTLABEL_ROOT_A    ?= "Root_A"
FUS_UPDATE_PARTLABEL_ROOT_B    ?= "Root_B"
FUS_UPDATE_PARTLABEL_APP_A     ?= "App_A"
FUS_UPDATE_PARTLABEL_APP_B     ?= "App_B"
FUS_UPDATE_PARTLABEL_DATA      ?= "data"

# slot sizes (MiB, bare numbers).
FUS_UPDATE_SIZE_BOOT_MIB       ?= "88"
FUS_UPDATE_SIZE_ROOT_MIB       ?= "256"
FUS_UPDATE_SIZE_APP_MIB        ?= "64"
FUS_UPDATE_SIZE_DATA_MIB       ?= "128"

# boot mode — where kernel + DTBs live and how U-Boot loads them. leading axis:
# it pins the app mode and, through it, the install door. the rest of the OS A/B
# machinery is mode-invariant. must be set before the app mode: an override keyed
# on the boot mode only resolves once OVERRIDES already carries the boot suffix.
#   slot   — kernel + DTBs in raw vfat BOOT_A/B slots; RAUC bootname on
#            boot.0/1, rootfs slots parent onto them.
#   rootfs — kernel + DTBs in /boot inside the rootfs squashfs (needs
#            squashfs+zstd in U-Boot, see fus-ab-bootrootfs.cfg); no BOOT
#            partitions, the rootfs slots carry the bootname, so a rootfs-only
#            bundle auto-activates. fewest partitions; OS and kernel update
#            together as one integrity unit.
FUS_UPDATE_BOOT_MODE           ?= "rootfs"

# 2-way dispatch for boot consumers: append :boot-slot / :boot-rootfs.
OVERRIDES .= ":boot-${FUS_UPDATE_BOOT_MODE}"

# application update mode — how the app payload is stored and updated. free to
# choose under boot=rootfs; boot=slot pins it, see below.
#   slot      — app in a dedicated read-only squashfs A/B partition pair,
#               mounted at the app mount following the booted rootfs.
#   rootfs    — app baked into the rootfs squashfs; updates with the OS.
#   container — app as a loop-mounted, dm-verity-checked squashfs file on
#               /data, merged via OverlayFS; installed as a RAUC bundle.
FUS_UPDATE_APP_MODE            ?= "rootfs"
# boot=slot is the fully stock configuration: the app rides its own slot group
# and no fs-updater state actor is built (asserted below).
FUS_UPDATE_APP_MODE:boot-slot  = "slot"

# 3-way dispatch: append :app-slot / :app-rootfs / :app-container overrides.
OVERRIDES .= ":app-${FUS_UPDATE_APP_MODE}"

# install door — which mechanism delivers updates. follows from the app mode,
# which pins it wherever only one door is admissible.
#   stock     — RAUC's own door (rauc install / hawkBit); no state actor.
#   fsupdater — fs-updater fronts the installs and owns the
#               pending/commit/rollback state door.
FUS_UPDATE_INSTALL_DOOR             ?= "fsupdater"
FUS_UPDATE_INSTALL_DOOR:app-slot      = "stock"
FUS_UPDATE_INSTALL_DOOR:app-container = "fsupdater"

# gates fs-updater-lib's raw application image / F&S container support (and
# the botan-2 dependency they need); off by default, this layer only ships
# RAUC-verity bundles.
FUS_UPDATE_LEGACY_IMAGES       ?= "0"

# bundle boot-slot token, globally parsed so both bundle recipes see it.
# empty in boot=rootfs: the kernel rides the rootfs slot.
FUS_BUNDLE_BOOT_SLOT            = "boot"
FUS_BUNDLE_BOOT_SLOT:boot-rootfs = ""

python () {
    mode = d.getVar('FUS_UPDATE_APP_MODE')
    if mode not in ('slot', 'rootfs', 'container'):
        bb.fatal("FUS_UPDATE_APP_MODE='%s' is invalid; use slot, rootfs or container" % mode)

    boot_mode = d.getVar('FUS_UPDATE_BOOT_MODE')
    if boot_mode not in ('slot', 'rootfs'):
        bb.fatal("FUS_UPDATE_BOOT_MODE='%s' is invalid; use slot or rootfs" % boot_mode)
    # boot=slot is the all-stock configuration; the app mode is pinned to it
    # above, so this only fires where that pin was overridden on purpose.
    if boot_mode == 'slot' and mode != 'slot':
        bb.fatal("boot=slot requires FUS_UPDATE_APP_MODE='slot' (it is the "
                 "all-stock configuration); got '%s'" % mode)

    door = d.getVar('FUS_UPDATE_INSTALL_DOOR')
    if door not in ('stock', 'fsupdater'):
        bb.fatal("FUS_UPDATE_INSTALL_DOOR='%s' is invalid; use stock or fsupdater" % door)
    if mode == 'slot' and door == 'fsupdater':
        # this gate cannot see bundles built elsewhere; fs-updater-guard-rootfs's
        # image-member check closes that cross-build gap.
        bb.fatal("app=slot has no fs-updater state actor; FUS_UPDATE_INSTALL_DOOR must stay 'stock'")
    if mode == 'container' and door != 'fsupdater':
        bb.fatal("app=container requires the fs-updater door (staged-but-never-activated installs otherwise)")

    legacy = d.getVar('FUS_UPDATE_LEGACY_IMAGES')
    if legacy not in ('0', '1'):
        bb.fatal("FUS_UPDATE_LEGACY_IMAGES='%s' is invalid; use 0 or 1" % legacy)
}

# container mode: all app paths live under one base dir on the persistent
# partition.
FUS_UPDATE_APP_CONTAINER_BASE   ?= "${FUS_UPDATE_DATA_MOUNT}/app"

# the A/B images and the transient .incoming.squashfs staging file must
# share this directory: fs-updater-lib renames .incoming onto the inactive
# slot and needs both paths on one filesystem for the rename to be atomic.
FUS_UPDATE_APP_IMG_DIR          ?= "${FUS_UPDATE_APP_CONTAINER_BASE}/images"

# mount point for the verity-verified active app image — the OverlayFS
# lowerdir, not the app mount itself; the merge lands on
# FUS_UPDATE_APP_MOUNT. owned by fus-app-container-runtime's mount verb.
FUS_UPDATE_APP_CURRENT          ?= "${FUS_UPDATE_APP_CONTAINER_BASE}/current"

# OverlayFS upper/work dirs for the merge onto the app mount.
FUS_UPDATE_APP_OVERLAY_UPPER    ?= "${FUS_UPDATE_APP_CONTAINER_BASE}/overlay/upper"
FUS_UPDATE_APP_OVERLAY_WORK     ?= "${FUS_UPDATE_APP_CONTAINER_BASE}/overlay/work"

# fs-updater-lib compile-time path defaults (upstream points at the legacy
# /rw_fs layout). FSUP_RAUC_SCRATCH stages the v2 container's embedded fw
# bundle; FUS_UPDATE_APP_IMG_DIR doubles as the lib's app image store, so
# the runtime, the RAUC slot hook and the lib resolve the same directory.
FSUP_RAUC_SCRATCH              ?= "${FUS_UPDATE_DATA_MOUNT}/.cache/update.fw"
