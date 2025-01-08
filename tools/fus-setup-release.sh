#!/bin/sh
#
# This is a wrapper script for NXPs fsl_setup_release.sh.
# It calls the fsl_setup_release script with the given parameters
# and adds some F&S specific configurations to the build
set -e
. ./yocto-f+s-utilities

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
FSL_SETUP_RELEASE=sources/meta-imx/tools/imx-setup-release.sh

if [ -d "$BUILD_DIR" ] && [ "$FORCE" != "1" ]; then
	. setup-environment "$BUILD_DIR"
else
	# Call NXPs fsl_setup_release script
	DISTRO="$DISTRO" MACHINE="$MACHINE" . $FSL_SETUP_RELEASE -b "$BUILD_DIR"

	# Add FuS-Layer
	echo "" >> "$BUILD_DIR/conf/bblayers.conf"
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus/meta-fus-bsp \"" >> "$BUILD_DIR/conf/bblayers.conf"
	echo "BBLAYERS += \" \${BSPDIR}/sources/meta-fus/meta-fus-sdk \"" >> "$BUILD_DIR/conf/bblayers.conf"

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


