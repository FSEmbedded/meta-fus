# Common settings for all F&S boards

DISTRO_NAME = "FUS i.MX Release Distro"

MKUBIFS_ARGS ??= "-m 2048 -e 126976 -c 2048"

# Remove image_types_fsl because there is a awk command which search after a
# point(.) in the devicetrees. But we have 2 points in the devicetree
# picocom1.2.dtb so the awk command find the first point, so the new name is
# picocom1 instead of picocom1.2. And thats why you get an error at compile
# time. Thats why we copy the image_types_fsl and rename it as image_types_fus
# and changed the line in the original file from
# "DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F "." '{print $1}'`" to
# "DTS_BASE_NAME=`basename ${DTS_FILE} | awk -F ".dtb" '{print $1}'`"
# The Original file will be find in sources/meta-fsl-arm/classes/
# image_types_fsl.bbclass
IMAGE_CLASSES:remove = "image_types_fsl"
IMAGE_CLASSES += "image_types_fus"
IMAGE_NAME_SUFFIX ?= ""

CORE_IMAGE_EXTRA_INSTALL:append = " fs-startscript "

# Remove Kernel Image from rootfs
RRECOMMENDS:${KERNEL_PACKAGE_NAME}-base = ""

# This is necessary because there will be some debian packages created and
# these packages must be lower case. Basically we set CONFIG_LOCALVERSION to
# "-F+S". This appends the string "-F+S". Due to the string is upper case we
# need to set variable to convert it to lower case.
KERNEL_MODULE_PACKAGE_SUFFIX = "${@legitimize_package_name(d.getVar('KERNEL_VERSION'))}"

INHERIT:append ?= " image-buildinfo create-spdx cyclonedx-export"

# do not use ptest for qtbase and qtdeclarative.
# set to 0 in local.conf to use
DISABLE_PTEST:pn-qtbase ??= "1"
DISABLE_PTEST:pn-qtdeclarative ??= "1"
DISABLE_PTEST:pn-qtlanguageserver ??= "1"
DISABLE_PTEST:pn-qtwayland ??= "1"

DISTRO_FEATURES:remove:pn-qtbase = "${@bb.utils.contains('DISABLE_PTEST:pn-qtbase', '1', 'ptest', '', d)}"
DISTRO_FEATURES:remove:pn-qtdeclarative = "${@bb.utils.contains('DISABLE_PTEST:pn-qtdeclarative', '1', 'ptest', '', d)}"
DISTRO_FEATURES:remove:pn-qtlanguageserver = "${@bb.utils.contains('DISABLE_PTEST:pn-qtlanguageserver', '1', 'ptest', '', d)}"
DISTRO_FEATURES:remove:pn-qtwayland = "${@bb.utils.contains('DISABLE_PTEST:pn-qtwayland', '1', 'ptest', '', d)}"


# SPDX_ORG = "F&S Elektronik Systeme GmbH (info@fs-net.de)"
SPDX_PRETTY ?= "1"
SPDX_INCLUDE_SOURCES ?= "0"
SPDX_ARCHIVE_SOURCES ?= "0"
SPDX_ARCHIVE_PACKAGED ?= "0"
SPDX_INCLUDE_COMPILED_SOURCES:pn-linux-fus-debug  ?= "1"

CYCLONEDX_SPEC_VERSION ?= "1.6"
CYCLONEDX_RUNTIME_PACKAGES_ONLY ?= "0"
