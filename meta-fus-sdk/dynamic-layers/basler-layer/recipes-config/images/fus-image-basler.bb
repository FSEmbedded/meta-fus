# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "F&S Basler camera support image"
LICENSE = "MIT"

require recipes-config/images/fus-image-std.bb

IMAGE_INSTALL:append = " \
		coreutils \
		packagegroup-dart-bcon-mipi \
		packagegroup-imx-isp \
"
