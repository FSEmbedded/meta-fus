# fus-no-update.inc
#
# Required by fus-update-features.inc when FUS_UPDATE is off. Depends on that
# switch alone and names no machine. :remove also beats the
# DISTRO_FEATURES:append = " rauc" that older setup scripts wrote into local.conf.
DISTRO_FEATURES:remove = "rauc fus-update"

# meta-rauc warns when its layer is present without the rauc feature.
SKIP_META_RAUC_FEATURE_CHECK = "1"

# Release fields that describe the signed update firmware (os-release.bbappend).
OS_RELEASE_FIELDS:remove = "BUILD_ID FUS_SIGNING_VARIANT"

# Without fs-updater only RAUC's own door is left. A plain assignment, so it
# beats local.conf, which is read before this file. The app-container override
# never applies here: app=container without the framework is fatal
# (fus-update-layout.inc).
FUS_UPDATE_INSTALL_DOOR = "stock"
