# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

### WARNING:
###  FOR EVALUATION AND TESTING ONLY
###  Open root login, and the upstream dummy keyring for update signatures.
###  DO NOT USE in production or mission-critical environments — build a
###  product image on fusys-image-core and provision real credentials and a
###  real keyring instead.

DESCRIPTION = "F&S evaluation image with A/B update support: the evaluation payload (graphics, \
multimedia, connectivity, diagnostics) on top of the hardened A/B base, plus the example \
application and the auto-update client. Read-only squashfs rootfs, writable /etc via overlayfs, \
persistent /data."
LICENSE = "MIT"

# the A/B base brings core-image, the read-only rootfs, overlayfs-etc and
# the update runtime floor; this recipe adds the evaluation payload.
require recipes-config/images/fusys-image-core.bb

# hard assignment on purpose: the distro-level weak default is already
# applied at parse time, so a weak assignment could not undo the base's
# locale trim.
IMAGE_LINGUAS = "${DEFAULT_IMAGE_LINGUAS}"

# the base disables the fixed emmc-${MACHINE}.sysimg alias; this is the
# image a board is flashed with, so it takes the alias.
FUS_EMMC_SYSIMG_ALIAS = "1"

## Select Image Features
# package-management is deliberately absent: a read-only rootfs cannot run
# one, and the upstream conflict check is inactive in this layer
# (fus-update.bbclass asserts against it).
IMAGE_FEATURES += " \
    debug-tweaks \
    splash \
    hwcodecs \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston', \
       bb.utils.contains('DISTRO_FEATURES',     'x11', 'x11-base x11-sato', \
                                                       '', d), d)} \
"

CORE_IMAGE_EXTRA_INSTALL += " \
    bcsend \
    fbset \
    firmwared \
    fs-remote\
    hostapd \
    liberation-fonts \
    libsndfile1 \
    libubootenv \
    libusb1 \
    libxml2 \
    libgpiod \
    linux-firmware-atmel-mxt \
    linux-firmware-pcie8997 \
    linux-firmware-sd8787 \
    linux-firmware-sd8997 \
    linux-firmware-wl12xx \
    linux-firmware-wl18xx \
    linux-serial-test \
    openssh \
    packagegroup-fs-benchmark \
    packagegroup-fs-monitor \
    packagegroup-fs-util \
    packagegroup-fs-dotnet \
    packagegroup-fsl-gstreamer1.0 \
    packagegroup-fsl-gstreamer1.0-full \
    psplash \
    openssl-provider-se050 \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston-init weston-examples', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'x11 wayland', 'weston-xwayland xterm', '', d)} \
    ${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-os optee-test', '', d)} \
"

CORE_IMAGE_EXTRA_INSTALL:append:imx-nxp-bsp = " \
	kernel-module-nxp-wlan \
"

# evaluation-only audit tooling; drop together with debug-tweaks for
# production.
IMAGE_INSTALL:append = " systemd-analyze"

# the app-delivery mechanism, the example application and the auto-update
# client.
IMAGE_INSTALL:append            = " packagegroup-fus-app ${FUS_UPDATE_APP_LAUNCHER_PACKAGES} rauc-hawkbit-updater"
IMAGE_INSTALL:append:app-rootfs = " ${FUS_UPDATE_APP_PACKAGES}"

set_fus_release_version() {

    if [ -n "${FUS_RELEASE_VERSION}" ]; then
        echo -e "${FUS_RELEASE_VERSION}" >> ${IMAGE_ROOTFS}${sysconfdir}/issue
        echo -e "${FUS_RELEASE_VERSION}" >> ${IMAGE_ROOTFS}${sysconfdir}/issue.net
    fi

}

ROOTFS_POSTPROCESS_COMMAND += "set_fus_release_version; "

update_issue() {

    local WARNING_TEXT="
----------------------------------------------------------
                 FOR TESTING PURPOSES ONLY
     This image is for evaluation and testing only!
DO NOT USE in production or mission-critical environments!
----------------------------------------------------------
"
    echo -e "${WARNING_TEXT}" >> ${IMAGE_ROOTFS}${sysconfdir}/issue
    echo -e "${WARNING_TEXT}" >> ${IMAGE_ROOTFS}${sysconfdir}/issue.net

    bbwarn "$WARNING_TEXT"
    if ${@bb.utils.contains_any('CORE_IMAGE_EXTRA_INSTALL', 'openssh', 'true', 'false', d)}; then
        echo -e "Banner /etc/issue.net" >> ${IMAGE_ROOTFS}${sysconfdir}/ssh/sshd_config
    fi
}

ROOTFS_POSTPROCESS_COMMAND += "update_issue; "

# remove getty tty1 service because of using runtime generated
# 'fsserial-getty@.service' service
ROOTFS_POSTPROCESS_COMMAND += "remove_default_getty_service; "
remove_default_getty_service () {
    rm -f ${IMAGE_ROOTFS}/lib/systemd/system/getty@.service
    rm -f ${IMAGE_ROOTFS}/etc/systemd/system/getty.target.wants/getty@tty1.service
}

# /data is created empty; overlayfs-etc creates its dirs on first boot.
