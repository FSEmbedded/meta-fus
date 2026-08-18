SUMMARY = "RAUC combined A/B update bundle (rootfs + boot and/or app slots, per the active boot/app modes) for the F&S update standard image"

# shared bundle policy (version, verity format, signing, read-back hook,
# OS slot definitions) + the app slot definition.
require recipes-core/bundles/fus-bundle-common.inc
require recipes-core/bundles/fus-app-slot.inc

# updates the inactive slot's rootfs and its boot partition together;
# rootfs.x has parent=boot.x in system.conf, so RAUC writes both
# components of one slot atomically. the app slot token is appfs in slot
# mode, empty in rootfs mode; container is rejected below.
RAUC_BUNDLE_SLOTS = "rootfs ${FUS_BUNDLE_BOOT_SLOT} ${FUS_BUNDLE_APP_SLOT}"

# container: a combined fw+app bundle is unsupported -- fs-updater-lib
# activates both dimensions only from two separate artifact paths, so a
# combined bundle's staged app member would install but never activate.
# reject the build explicitly.
do_bundle:prepend() {
    if [ "${FUS_UPDATE_APP_MODE}" = "container" ]; then
        bbfatal "fus-update-bundle (combined fw+app) does not support app-container yet -- fs-updater-lib activates an app image only from a separate app bundle path, so a combined bundle's staged app member would install but never activate. Use fus-fw-bundle + fus-app-bundle as two separate installs."
    fi
}
