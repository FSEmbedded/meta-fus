#!/bin/bash
#
# This is a wrapper script for NXPs fsl_setup_release.sh.
# It calls the fsl_setup_release script with the given parameters
# and adds some F&S specific configurations to the build
set -e
. ./yocto-f+s-utilities

WORKDIR="$PWD"

add_layer() {
	local layer="$1"
	local bblayers_entry="BBLAYERS += \" \${BSPDIR}/sources/$layer \""
	local file="$BUILD_DIR/conf/bblayers.conf"

	if [ -d "$WORKDIR/sources/$layer" ] && ! grep -Fxq "$bblayers_entry" $file; then
		echo "$bblayers_entry" >> $file
	fi
}
add_config () {
	local config="$1"
	local file="$BUILD_DIR/conf/local.conf"

	if ! grep -Fxq "$config" $file; then
		echo "$config" >> $file
	fi
}

add_chromium() {
	if [ "$CHROMIUM" == "1" ]; then
		add_layer "meta-browser/meta-chromium"
		add_layer "meta-lts-mixins"
		add_config "IMAGE_INSTALL:append = \" chromium-ozone-wayland\""
	fi
}

add_spdx() {
	if [ "$SPDX" == "1" ]; then
		add_config "SPDX_ORG = \"${SPDX_ORG}\""
		add_config "INHERIT += \"create-spdx \""
		add_config "SPDX_PRETTY = \"1\""
		add_config "SPDX_INCLUDE_SOURCES = \"1\""
		add_config "SPDX_ARCHIVE_SOURCES = \"0\""
		add_config "SPDX_ARCHIVE_PACKAGED = \"0\""
	fi
}


parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                print_usage
				exit 0
		;;
            -b)
                BUILD_DIR="$2"
                shift # past argument
                shift # past value
        ;;
            -c)
                COMMAND="$2"
                shift # past argument
                shift # past value
		;;
            -e)
                EULA=1
                shift # past argument
		;;
            -f)
                FORCE="1"
                shift # past argument
		;;
            --add-chromium)
                CHROMIUM="1"
                shift # past argument
            ;;
            --add-spdx)
                SPDX="1"
		SPDX_ORG="$2"
                shift # past argument
                shift # past value
            ;;
            *)    # unknown option
                echo "Unknown option: $1"
                print_usage
		exit 0
            ;;
    esac
done
}

parse_arguments "$@"

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
	# Point to the current directory since the last command changed the directory to $BUILD_DIR
	BUILD_DIR=.
else

	if [ -z "$DISTRO" ] || [ -z "$MACHINE" ]; then
	   	print_usage
		exit 0
	fi
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
	add_config "# Switch to Debian packaging and include package-management in the image"
	add_config "PACKAGE_CLASSES = \"package_deb\""
	add_config "EXTRA_IMAGE_FEATURES += \"package-management\""

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
	add_layer "meta-silex-fus"

	add_config "DISTRO_FEATURES:append =  \" rauc\""
	add_layer "meta-rauc"
	add_layer "meta-fus-updater"
	add_layer "meta-fus-updater-azure"



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

# Add configs, given by parameter
add_chromium
add_spdx

set +e
# run command
if [ -n "$COMMAND" ]; then
	echo "Running: $COMMAND"
	$COMMAND
fi
