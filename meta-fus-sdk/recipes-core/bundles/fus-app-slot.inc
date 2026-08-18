# application slot definition shared by the combined and app-only RAUC
# bundles. the including recipe adds ${FUS_BUNDLE_APP_SLOT} to its
# RAUC_BUNDLE_SLOTS:
#   slot      -> "appfs": A/B app slot image, raw-written, post-install
#                read-back hook like the OS slots.
#   container -> "appfs": same token -- RAUC matches [image.appfs] against
#                the device's [slot.appfs.*] family by name; only the
#                per-token varflags differ.
#   rootfs    -> "": no app dimension in the bundle; the definition stays
#                inert (same idiom as the OS slots in fus-bundle-common.inc).

FUS_BUNDLE_APP_SLOT            = "appfs"
FUS_BUNDLE_APP_SLOT:app-rootfs = ""

# slot mode: RAUC performs the raw device write, so post-install can
# read it back.
RAUC_SLOT_appfs = "fus-app-image"
RAUC_SLOT_appfs[fstype] = "squashfs"
RAUC_SLOT_appfs[hooks] = "post-install"

# container mode: same slot-class name, different source and hooks.
# [hooks]/[file] are varflags and cannot take an override suffix, so the
# container-specific values are set in anonymous python; the plain
# variable does take a normal override.
RAUC_SLOT_appfs:app-container = "fus-app-container"
python () {
    if d.getVar('FUS_UPDATE_APP_MODE') == 'container':
        # install (not post-install): the container slot is nominal and
        # always mounted -- RAUC does not write it, the bundle's own
        # install hook stages the image for fs-updater to activate.
        d.setVarFlag('RAUC_SLOT_appfs', 'hooks', 'install')
        d.setVarFlag('RAUC_SLOT_appfs', 'file', d.getVar('FUS_UPDATE_APP_CONTAINER_IMAGE'))
        # [fstype] from the slot-mode block stays set but is unused here:
        # [file] names the deploy artifact explicitly.
}
