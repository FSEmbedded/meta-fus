DESCRIPTION = "F&S standard image"
LICENSE = "MIT"

inherit core-image

### WARNING: This image is NOT suitable for production use and is intended
###          to provide a way for users to reproduce the image used during
###          the validation process of i.MX BSP releases.

## Select Image Features
IMAGE_FEATURES += " \
    debug-tweaks \
    splash \
    hwcodecs \
    package-management \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston', \
       bb.utils.contains('DISTRO_FEATURES',     'x11', 'x11-base x11-sato', \
                                                       '', d), d)} \
"

CORE_IMAGE_EXTRA_INSTALL += " \
    bcsend \
    fbset \
    firmwared \
    freerdp \
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
    packagegroup-fsl-gstreamer1.0 \
    packagegroup-fsl-gstreamer1.0-full \
    psplash \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston-init weston-examples', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'x11 wayland', 'weston-xwayland xterm', '', d)} \
    ${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-test', '', d)} \
"

CORE_IMAGE_EXTRA_INSTALL:append:imx-nxp-bsp = " \
	kernel-module-nxp-wlan \
"

# remove getty tty1 service because of using runtime generated
# 'fsserial-getty@.service' service
ROOTFS_POSTPROCESS_COMMAND = "remove_default_getty_service; "
remove_default_getty_service () {
    rm -f ${IMAGE_ROOTFS}/lib/systemd/system/getty@.service
    rm -f ${IMAGE_ROOTFS}/etc/systemd/system/getty.target.wants/getty@tty1.service
}
