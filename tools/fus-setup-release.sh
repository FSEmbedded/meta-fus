#!/bin/sh
#
# This is a wrapper script for NXPs fsl_setup_release.sh.
# It calls the fsl_setup_release script with the given parameters
# and adds some F&S specific configurations to the build
set -e
. ./yocto-f+s-utilities

WORKDIR="$PWD"

add_layer() {
	local layer="$1"
	if [ -d "$WORKDIR/sources/$layer" ]; then
		# Add rauc layer to bblayers.conf
		echo "BBLAYERS += \" \${BSPDIR}/sources/$layer \"" >> $BUILD_DIR/conf/bblayers.conf
	fi
}

# Get the command line parameters
while getopts "b:c:efh" setup_flag
do
    case $setup_flag in
        b) BUILD_DIR="$OPTARG";
		;;
        c) COMMAND="$OPTARG";
        ;;
        e) EULA=1;
		;;
        f) FORCE="1";
		;;
        h) SHOW_HELP="1";
		;;
		*) SHOW_HELP="1";

    esac
done

if [ -n "$SHOW_HELP" ]; then
	print_usage
	SHOW_HELP=""
	exit 1
fi

if [ -z "$DISTRO" ]; then
   	print_usage
	exit 1
fi

if [ -z "$MACHINE" ]; then
   	print_usage
	exit 1
fi

if [ -z "$BUILD_DIR" ]; then
   	BUILD_DIR=build-$MACHINE-$DISTRO
fi

BUILD_DIR_REALPATH="${PWD}/$BUILD_DIR"

if [ -z "$OEROOT_DIR" ]; then
	OEROOT_DIR=${PWD}/sources/poky
	if [ -e "${PWD}/sources/oe-core" ]; then
    	OEROOT_DIR=${PWD}/sources/oe-core
	fi
fi
# Path to fsl-setup-release.sh script
FSL_SETUP_RELEASE=setup-environment

if [ -d "$BUILD_DIR" ] && [ "$FORCE" != "1" ]; then
	. setup-environment "$BUILD_DIR"
else

	DISTRO="$DISTRO" MACHINE="$MACHINE" . ./$FSL_SETUP_RELEASE  "$BUILD_DIR"

	# Point to the current directory since the last command changed the directory to $BUILD_DIR
	BUILD_DIR=.

	if [ ! -e $BUILD_DIR/conf/local.conf ]; then
		echo -e "\n ERROR - No build directory is set yet. Run the 'setup-environment' script before running this script to create " $BUILD_DIR
		echo -e "\n"
		return 1
	fi

	# On the first script run, backup the local.conf file
	# Consecutive runs, it restores the backup and changes are appended on this one.
	if [ ! -e $BUILD_DIR/conf/local.conf.org ]; then
		cp $BUILD_DIR/conf/local.conf $BUILD_DIR/conf/local.conf.org
	else
		cp $BUILD_DIR/conf/local.conf.org $BUILD_DIR/conf/local.conf
	fi

	echo >> conf/local.conf
	echo "# Switch to Debian packaging and include package-management in the image" >> conf/local.conf
	echo "PACKAGE_CLASSES = \"package_deb\"" >> conf/local.conf
	echo "EXTRA_IMAGE_FEATURES += \"package-management\"" >> conf/local.conf

	if [ ! -e $BUILD_DIR/conf/bblayers.conf.org ]; then
		cp $BUILD_DIR/conf/bblayers.conf $BUILD_DIR/conf/bblayers.conf.org
	else
		cp $BUILD_DIR/conf/bblayers.conf.org $BUILD_DIR/conf/bblayers.conf
	fi

	# Add FuS-Layer
	echo "" >> "$BUILD_DIR/conf/bblayers.conf"
	add_layer "meta-fus/meta-fus-bsp"
	add_layer "meta-fus/meta-fus-sdk"
	add_layer "meta-fus-nboot"

	# Add other layers
	echo "" >> "$BUILD_DIR/conf/bblayers.conf"
	add_layer "meta-arm/meta-arm"
	add_layer "meta-arm/meta-arm-toolchain"
	add_layer "meta-clang"
	add_layer "meta-openembedded/meta-gnome"
	add_layer "meta-openembedded/meta-networking"
	add_layer "meta-openembedded/meta-filesystems"
	add_layer "meta-qt6"

	##
	# Run layer dependend init
	##

	OLD_PWD=${PWD}
	cd ..
	LIST_OF_INIT_SCRIPTS=$(ls -d sources/*)
	cd "$OLD_PWD"

	for INIT_SCRIPT in $LIST_OF_INIT_SCRIPTS; do

		if [ -e "../${INIT_SCRIPT}/scripts/fus_setup.sh" ]; then
			echo "Following extra layer init run": "../${INIT_SCRIPT}/scripts/fus_setup.sh"
			export BUILD_DIR="$BUILD_DIR"
			sh "../${INIT_SCRIPT}/scripts/fus_setup.sh" "$BUILD_DIR ${INIT_SCRIPT}/scripts"
		fi
	done

	# make a source_env file
	if [ ! -e source_env ]; then
		echo "#!/bin/sh" >> source_env
		echo "cd $OEROOT_DIR" >> source_env
		echo "set -- $BUILD_DIR_REALPATH" >> source_env
		echo ". ./oe-init-build-env > /dev/null" >> source_env
		echo "echo \"Back to build project $(basename "$BUILD_DIR_REALPATH").\"" >> source_env
	fi
fi

# run command
if [ -n "$COMMAND" ]; then
	echo "Running: $COMMAND"
	$COMMAND
fi


