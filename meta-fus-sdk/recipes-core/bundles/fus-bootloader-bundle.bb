SUMMARY = "RAUC bundle carrying only the bootloader, for the F&S update standard image"

# shared bundle policy (version, verity format, signing, install hook).
require recipes-core/bundles/fus-bundle-common.inc

# the device's bootloader slot exists only with this flag (rauc-conf.bbappend).
REQUIRED_MACHINE_FEATURES = "fus-update-bootloader"

# type boot ships the deployed file unchanged; the install hook writes it.
RAUC_BUNDLE_SLOTS = "bootloader"
RAUC_SLOT_bootloader = "u-boot-fus"
RAUC_SLOT_bootloader[type] = "boot"
RAUC_SLOT_bootloader[file] = "Firmware/uboot-${UBOOT_CONFIG_BASENAME}.fs"
RAUC_SLOT_bootloader[depends] = "u-boot-fus:do_deploy"
RAUC_SLOT_bootloader[hooks] = "install"

# host-side contract test of the hook's bootloader branch; nothing test-related ships.
SRC_URI += "file://test-install-check-bootloader.sh"
do_test_install_hook() {
    sh ${WORKDIR}/test-install-check-bootloader.sh ${WORKDIR}/install-check
}
addtask test_install_hook after do_template_install_hook before do_configure
