SUMMARY = "RAUC firmware-only update bundle (rootfs, plus the boot slot when boot=slot) for the F&S update standard image"

# shared bundle policy (version, verity format, signing, read-back hook,
# OS slot definitions).
require recipes-core/bundles/fus-bundle-common.inc

# updates the OS of a slot (boot + rootfs) only; the application is left
# untouched. RAUC does not enforce OS<->app compatibility for a partial
# bundle, so keep the deployed app compatible or use the combined bundle.
# in boot=rootfs there is no separate boot slot (the token is empty).
RAUC_BUNDLE_SLOTS = "rootfs ${FUS_BUNDLE_BOOT_SLOT}"
