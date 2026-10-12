# Copyright 2026 F&S — MIT
SUMMARY = "A/B slot runtime floor without the update framework"
DESCRIPTION = "The userspace packages every A/B image needs at runtime, with or without \
the update framework: the persistent-data mount, U-Boot env access (via \
fus-update-fw-env, which pulls the tools), and the PARTLABEL-resolution tools the \
overlayfs-etc preinit needs. Kernel FS/overlay support comes from the kernel config, \
not from here."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

RDEPENDS:${PN} = " \
    data-mount-unit \
    fus-update-fw-env \
    util-linux-blkid \
    util-linux-mount \
"
