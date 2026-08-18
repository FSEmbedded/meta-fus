# Copyright 2026 F&S — MIT
SUMMARY = "Minimal A/B + read-only/overlay runtime floor (no app, no eval tools)"
DESCRIPTION = "The userspace packages every RAUC A/B image needs at runtime, independent of the \
application or image variant: the RAUC client + config, the persistent-data mount, U-Boot env access (via \
fus-update-fw-env, which pulls the tools), and the PARTLABEL-resolution tools the overlayfs-etc \
preinit needs. Kernel FS/verity/overlay support \
comes from the kernel config, not from here."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

RDEPENDS:${PN} = " \
    rauc \
    rauc-conf \
    rauc-mark-good \
    util-linux-mount \
    util-linux-blkid \
    data-mount-unit \
    fus-update-fw-env \
"
