#!/bin/sh
#
# This is a wrapper script for NXPs fsl_setup_release.sh.
# It calls the fsl_setup_release script with the given parameters
# and adds some F&S specific configurations to the build

source ./yocto-f+s-utilities

WORKDIR="$PWD"

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
FSL_SETUP_RELEASE=sources/meta-imx/tools/imx-setup-release.sh

# Call NXPs fsl_setup_release script
DISTRO=$DISTRO MACHINE=$MACHINE . $FSL_SETUP_RELEASE -b $BUILD_DIR

# Add FuS-Layer
echo "" >> $BUILD_DIR/conf/bblayers.conf
echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus \"" >> $BUILD_DIR/conf/bblayers.conf

if [ -d "$WORKDIR/sources/meta-rauc" ]; then
	# Add rauc layer to bblayers.conf
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-rauc \"" >> $BUILD_DIR/conf/bblayers.conf
	echo "DISTRO_FEATURES:append =  \" rauc\"" >> $BUILD_DIR/conf/local.conf
fi
if [ -d "$WORKDIR/sources/meta-fus-updater" ]; then
	# Add fus-updater layer to bblayers.conf
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus-updater \"" >> $BUILD_DIR/conf/bblayers.conf
fi
if [ -d "$WORKDIR/sources/meta-fus-updater-azure" ]; then
	# Add fus-updater-azure layer to bblayers.conf
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus-updater-azure \"" >> $BUILD_DIR/conf/bblayers.conf
fi

if [ -d "$WORKDIR/sources/meta-silex-fus" ]; then
	# Add silex-fus layer to bblayers.conf
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-silex-fus \"" >> $BUILD_DIR/conf/bblayers.conf
fi


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
