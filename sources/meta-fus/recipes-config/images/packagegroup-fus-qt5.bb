# Copyright (C) 2014 O.S. Systems Software LTDA.

DESCRIPTION = "Target packages for F&S Qt5 SDK"
LICENSE = "MIT"

inherit packagegroup


PACKAGEGROUP_DISABLE_COMPLEMENTARY = "1"

# Requires Wayland to work
USE_WAYLAND = " \
    qtwayland-plugins \
    qtwayland-tools \
"

RDEPENDS_${PN} += " \
    qtbase-plugins \
    qtimageformats-plugins \
    qtlocation-plugins \
    qtsensors-plugins \
    qtmultimedia-plugins \
    qttools-tools \
    qtsvg-plugins \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', '${USE_WAYLAND}', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qt3d-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtconnectivity-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtgraphicaleffects-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtlocation-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtmultimedia-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtsensors-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtsystems-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtwebsockets-qmlplugins', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'opengl', 'qtwebchannel-qmlplugins', '', d)} \
    qtbase-examples \
"

RRECOMMENDS_${PN} += " \
    qtquickcontrols-qmlplugins \
    qttools-plugins \
"

### QT Examples ###

#RDEPENDS_${PN}_append = " \
#    qtdeclarative-examples \
#    quitindicators \
#    qt5-demo-extrafiles \
#"

# Install the following apps on SoC with GPU
#RDEPENDS_${PN}_append_imxgpu = " \
#    qtsmarthome \
#    qt5ledscreen \
#    quitbattery \
#    qt5everywheredemo \
#    qt5nmapcarousedemo \
#    qt5nmapper \
#    cinematicexperience \
#"

#RDEPENDS_${PN}_append_imxgpu3d = " \
#    qt3d-examples \
#"


