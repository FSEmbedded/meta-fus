#!/bin/sh
#
# This is a wrapper script for NXPs fsl_setup_release.sh.
# It calls the fsl_setup_release script with the given parameters
# and adds some F&S specific configurations to the build

source ./yocto-f+s-utilities

# Get the command line parameters
while getopts "b:m:h" setup_flag
do
    case $setup_flag in
        b) BUILD_DIR="$OPTARG";
		;;
		m) FS_MODE="$OPTARG";
		;;
		h) SHOW_HELP="1";
    esac
done

if [ -n "$SHOW_HELP" ]; then
	print_usage
	SHOW_HELP=""
	return 1
fi

if [ -z "$DISTRO" ]; then
   	print_usage
	return 1
fi

if [ -z "$MACHINE" ]; then
   	print_usage
	return 1
fi

if [ -z "$BUILD_DIR" ]; then
   	BUILD_DIR=build-$MACHINE-$DISTRO
fi



# Path to fsl-setup-release.sh script
FSL_SETUP_RELEASE=sources/meta-fsl-bsp-release/imx/tools/fsl-setup-release.sh

# Call NXPs fsl_setup_release script
DISTRO=$DISTRO MACHINE=$MACHINE . $FSL_SETUP_RELEASE -b $BUILD_DIR

# Add FuS-Layer
echo "" >> $BUILD_DIR/conf/bblayers.conf
echo "BBLAYERS += \" \${BSPDIR}/sources/meta-mono \"" >> $BUILD_DIR/conf/bblayers.conf
echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus \"" >> $BUILD_DIR/conf/bblayers.conf

# Determine root file system mode
if [ "$FS_MODE" == "ro" ]
then
	echo "" >> $BUILD_DIR/conf/local.conf
	echo "# Remove this to make your file system read-writeable:" >> $BUILD_DIR/conf/local.conf
	echo "EXTRA_IMAGE_FEATURES += \"read-only-rootfs \"" >> $BUILD_DIR/conf/local.conf
	echo
	echo "Building read-only root file system"
else
	echo
	echo "Building read/write root file system"
fi

# We remove the optee layer from the build for now because it causes trouble with the machine
# name and we do not support optee on our boards so far.
echo "" >> $BUILD_DIR/conf/local.conf
echo "# We remove the optee layer from the build for now because it causes trouble with the machine" >> $BUILD_DIR/conf/local.conf
echo "# name and we do not support optee on our boards so far." >> $BUILD_DIR/conf/local.conf
echo "BBMASK += \"meta-fsl-bsp-release/imx/meta-bsp/recipes-security/optee-imx/ \"" >> $BUILD_DIR/conf/local.conf
echo "CORE_IMAGE_EXTRA_INSTALL += \"fs-startscript \"" >> $BUILD_DIR/conf/local.conf
