# Copyright 2026 F&S — MIT
SUMMARY = "Application-delivery mechanism for the A/B image (per FUS_UPDATE_APP_MODE)"
DESCRIPTION = "The /opt/fus-app provisioning for the active app-update mode: the readiness sync target \
plus the mode-specific mount (slot) or loop+overlay runtime (container). \
Contains NO example application."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit packagegroup

RDEPENDS:${PN}                      = " fus-app-target"
RDEPENDS:${PN}:append:app-slot      = " fus-app-mount"
# container runtime only; fs-updater-cli/-service ride the door-gated
# RDEPENDS in rauc_%.bbappend so every fsupdater-door image gets them,
# not just images installing this packagegroup.
RDEPENDS:${PN}:append:app-container = " fus-app-container-runtime"
# rootfs mode bakes the app into the rootfs; no mount provider.
