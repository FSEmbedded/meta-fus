DESCRIPTION = "F&S Image, adds Qt5 to F&S standard image"
LICENSE = "MIT"

require recipes-config/images/fus-image-std.bb

inherit distro_features_check

CONFLICT_DISTRO_FEATURES = "directfb"

# Install Freescale QT demo applications
QT5_IMAGE_INSTALL_APPS = ""
QT5_IMAGE_INSTALL_APPS_imxgpu3d = "${@bb.utils.contains("MACHINE_GSTREAMER_1_0_PLUGIN", "imx-gst1.0-plugin", "imx-qtapplications", "", d)}"

# Install fonts
QT5_FONTS = "ttf-dejavu-common ttf-dejavu-sans ttf-dejavu-sans-mono ttf-dejavu-serif "

# Install Freescale QT demo applications for X11 backend only
MACHINE_QT5_MULTIMEDIA_APPS = ""
QT5_IMAGE_INSTALL = ""
QT5_IMAGE_INSTALL_common = " \
    qtbase \
    packagegroup-fus-qt5 \
    ${QT5_FONTS} \
    ${QT5_IMAGE_INSTALL_APPS} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'x11', 'libxkbcommon', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'wayland', 'qtwayland qtwayland-plugins', '', d)}\
    "
# Only QT on X11 support for now
QT5_IMAGE_INSTALL_imxgpu2d = "${@bb.utils.contains('DISTRO_FEATURES', 'x11','${QT5_IMAGE_INSTALL_common}', \
    'qtbase qtbase-plugins', d)}"

#  Install QT for x11 AND weston for fsimx6ull
QT5_IMAGE_INSTALL_imxpxp = " \
	${QT5_IMAGE_INSTALL_common}"

QT5_IMAGE_INSTALL_imxgpu3d = " \
    ${QT5_IMAGE_INSTALL_common} \
"

# Add packagegroup-qt5-webengine to QT5_IMAGE_INSTALL_mx6 and comment out the line below to install qtwebengine to the rootfs.
QT5_IMAGE_INSTALL_remove = " packagegroup-qt5-webengine"

IMAGE_INSTALL += " \
${QT5_IMAGE_INSTALL} \
"
