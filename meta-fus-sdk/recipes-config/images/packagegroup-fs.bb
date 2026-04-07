# Copyright 2025 F&S
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "Packagegroups for F&S"
LICENSE = "MIT"

inherit packagegroup

PACKAGES = "packagegroup-fs-benchmark packagegroup-fs-monitor packagegroup-fs-util packagegroup-fs-dotnet"

RDEPENDS:packagegroup-fs-benchmark = " \
    dhrystone \
    iperf3 \
    lmbench \
    stress-ng \
"

RDEPENDS:packagegroup-fs-monitor = " \
    evtest \
    gdb \
    ltrace \
    procps \
    strace \
"

RDEPENDS:packagegroup-fs-dotnet = " \
    icu \
    procps \
"

RDEPENDS:packagegroup-fs-util = " \
    alsa-tools \
    alsa-utils \
    bluez5 \
    can-utils \
    dosfstools \
    e2fsprogs-mke2fs \
    ethtool \
    i2c-tools \
    iproute2 \
    iw \
    kbd \
    libgpiod-tools \
    mdio-tools \
    mmc-utils \
    mtd-utils \
    mtd-utils-ubifs \
    pciutils \
    spitools \
    v4l-utils \
    wpa-supplicant \
"
