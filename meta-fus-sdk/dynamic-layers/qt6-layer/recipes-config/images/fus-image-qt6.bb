# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

### WARNING:
###  FOR TESTING PURPOSES ONLY
###  This image is for evaluation and testing only.
###  DO NOT USE in production or mission-critical environments.

DESCRIPTION = "F&S Qt6 evaluation image"
LICENSE = "MIT"

require recipes-config/images/fus-image-std.bb

inherit populate_sdk_qt6

CONFLICT_DISTRO_FEATURES = "directfb"

IMAGE_INSTALL += " \
    packagegroup-qt6-fsimx \
"

IMAGE_NAME_SUFFIX = "-qt"
