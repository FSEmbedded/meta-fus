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
    alsa-utils \
    alsa-tools \
    dosfstools \
    evtest \
    e2fsprogs-mke2fs \
    fbset \
    i2c-tools \
    spitools \
    iproute2 \
    memtester \
    ethtool \
    mtd-utils \
    mtd-utils-ubifs \
    lmbench \
    libgpiod \
    libgpiod-tools \
    firmwared \
    strace \
    ltrace \
    gdb \
    kbd \
    pciutils \
    libsndfile1 \
    libusb1 \
    libxml2 \
    bluez5 \
    can-utils \
    iw \
    openssh \
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
    kernel-module-nxp89xx \
    v4l-utils \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'weston-init weston-examples', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'x11 wayland', 'weston-xwayland xterm', '', d)} \
"
