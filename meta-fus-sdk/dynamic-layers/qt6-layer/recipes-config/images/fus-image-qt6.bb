# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "F&S Image, adds Qt6 to F&S standard image"
LICENSE = "MIT"

require recipes-config/images/fus-image-std.bb

inherit populate_sdk_qt6

CONFLICT_DISTRO_FEATURES = "directfb"

IMAGE_INSTALL += " \
    packagegroup-qt6-fsimx \
"

IMAGE_NAME_SUFFIX = "-qt"
