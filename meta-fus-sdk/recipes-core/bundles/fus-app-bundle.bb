SUMMARY = "RAUC application-only update bundle (appfs slot) for the F&S update standard image"

# shared bundle policy + the app slot definition; the OS slot definitions
# from the common include stay inert here (not listed in RAUC_BUNDLE_SLOTS).
require recipes-core/bundles/fus-bundle-common.inc
require recipes-core/bundles/fus-app-slot.inc

# updates only the application; the inactive slot's base OS is untouched.
# RAUC does not enforce OS<->app compatibility for a partial bundle -- keep
# the app compatible with the deployed OS range, or use the combined
# fus-update-bundle when OS and app change together.
RAUC_BUNDLE_SLOTS = "${FUS_BUNDLE_APP_SLOT}"

# container: the app bundle's manifest carries an -appfs compatible suffix
# so fs-updater-lib can classify it as an application bundle. :append, not
# a self-referential override (which would recurse). on-device the
# install-check hook below replaces RAUC's exact-equality default check,
# which would otherwise reject the suffixed string. slot mode stays
# unsuffixed: the default exact-match check is the working install path there.
RAUC_BUNDLE_COMPATIBLE:append:app-container = "-appfs"

# container: replace RAUC's default compatible check with the
# manifest-level install-check hook (RAUC_BUNDLE_HOOKS[hooks], not a
# per-slot hook). varflags cannot take overrides, hence anonymous python.
python () {
    if d.getVar('FUS_UPDATE_APP_MODE') == 'container':
        d.setVarFlag('RAUC_BUNDLE_HOOKS', 'hooks', 'install-check')
}

# container: the 3 verity sidecars ride as extra bundle files, found by
# the install hook at the bundle mount point. deployed flat by
# fus-app-container.bbclass, so no destdir mismatch with the primary image.
RAUC_BUNDLE_EXTRA_FILES:app-container = " \
    ${FUS_UPDATE_APP_CONTAINER_IMAGE}.verity \
    ${FUS_UPDATE_APP_CONTAINER_IMAGE}.roothash \
    ${FUS_UPDATE_APP_CONTAINER_IMAGE}.roothash.p7s \
"
RAUC_BUNDLE_EXTRA_DEPENDS:app-container = "fus-app-container:do_image_complete"

do_bundle:prepend() {
    # guard in a task, not anonymous python, so it fires only when this
    # bundle is built -- not during the global parse of a rootfs-mode image.
    if [ "${FUS_UPDATE_APP_MODE}" = "rootfs" ]; then
        bbfatal "fus-app-bundle (app-only) is meaningless in rootfs mode; the app ships baked into the rootfs, so use fus-fw-bundle to update it"
    fi
}
