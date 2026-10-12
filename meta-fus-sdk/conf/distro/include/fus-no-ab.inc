# fus-no-ab.inc
#
# Required by fus-update-features.inc when FUS_UPDATE_AB is off. Depends on that
# switch alone and names no machine.
DISTRO_FEATURES:remove = "overlayfs fus-update-ab"
