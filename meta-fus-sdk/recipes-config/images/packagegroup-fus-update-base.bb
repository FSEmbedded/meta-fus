# Copyright 2026 F&S — MIT
SUMMARY = "Minimal A/B + read-only/overlay runtime floor (no app, no eval tools)"
DESCRIPTION = "The userspace packages every RAUC A/B image needs at runtime, independent of the \
application or image variant: the A/B slot floor (packagegroup-fus-ab-base) plus the RAUC \
client and config. Kernel FS/verity/overlay support comes from the kernel config, not from \
here."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

RDEPENDS:${PN} = " \
    packagegroup-fus-ab-base \
    rauc \
    rauc-conf \
    rauc-mark-good \
"
