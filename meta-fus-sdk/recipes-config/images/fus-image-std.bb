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
    packagegroup-fsl-gstreamer1.0 \
    packagegroup-fsl-gstreamer1.0-full \
    v4l-utils \
    alsa-utils \
    alsa-tools \
    dosfstools \
    e2fsprogs-mke2fs \
    mtd-utils \
    mtd-utils-ubifs \
    mmc-utils \
    evtest \
    fbset \
    i2c-tools \
    spitools \
    pciutils \
    can-utils \
    linux-serial-test \
    iproute2 \
    ethtool \
    iperf3 \
    lmbench \
    glmark2 \
    stress-ng \
    libgpiod \
    libgpiod-tools \
    fbida \
    firmwared \
    strace \
    ltrace \
    gdb \
    kbd \
    libsndfile1 \
    libusb1 \
    libxml2 \
    bluez5 \
    iw \
    openssh \
    libubootenv \
    wpa-supplicant \
    hostapd \
    psplash \
    liberation-fonts \
    linux-firmware-wl12xx \
    linux-firmware-wl18xx \
    linux-firmware-sd8787 \
    linux-firmware-sd8997 \
    linux-firmware-pcie8997 \
    linux-firmware-atmel-mxt \
    nxp-wlan-sdk \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston-init weston-examples', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'x11 wayland', 'weston-xwayland xterm', '', d)} \
    ${@bb.utils.contains('MACHINE_FEATURES', 'optee', 'optee-test', '', d)} \
"

# remove getty tty1 service because of using runtime generated
# 'fsserial-getty@.service' service
ROOTFS_POSTPROCESS_COMMAND = "remove_default_getty_service; "
remove_default_getty_service () {
    rm -f ${IMAGE_ROOTFS}/lib/systemd/system/getty@.service
    rm -f ${IMAGE_ROOTFS}/etc/systemd/system/getty.target.wants/getty@tty1.service
}
