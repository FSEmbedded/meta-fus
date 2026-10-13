# App delivery for an app-bearing A/B image (evaluation or product image): the
# per-mode mechanism, the launcher and, in rootfs mode, the payload.
# fusys-image-core never inherits this class and stays app-free.

# Inherit it conditionally, like the core image inherits fus-update, so the
# image still builds where A/B is off:
#   inherit ${@bb.utils.contains('COMBINED_FEATURES', 'fus-update-ab', 'fus-app', '', d)}
inherit fus-update

# The application itself (FUS_UPDATE_APP_*) is global build configuration: an
# assignment in the image recipe would not reach the app image or the bundles.
IMAGE_INSTALL:append            = " packagegroup-fus-app ${FUS_UPDATE_APP_LAUNCHER_PACKAGES}"
IMAGE_INSTALL:append:app-rootfs = " ${FUS_UPDATE_APP_PACKAGES}"

# rootfs mode: the payload rides this rootfs (no discrete app image), so its
# contract is checked here; the other modes check it in their app-image build.
ROOTFS_POSTPROCESS_COMMAND:append:app-rootfs = " fus_selfcheck_app_payload;"

# Slot mode: fill the App_A/App_B partitions from the app slot image, which
# must be deployed before do_image_wic. A varflag takes no override suffix.
FUS_UPDATE_WKS_APP_CONTENT:app-slot = '--source rawcopy --sourceparams="file=fus-app-image-${MACHINE}.squashfs"'
do_image_wic[depends] += "${@bb.utils.contains('FUS_UPDATE_APP_MODE', 'slot', 'fus-app-image:do_image_complete', '', d)}"
