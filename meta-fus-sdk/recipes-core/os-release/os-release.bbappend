# Report the firmware version through the standard os-release file. BUILD_ID is
# the freedesktop field for "the identifier of the system image originally used
# as the installation base" — i.e. our firmware build version. The stock recipe
# defines BUILD_ID but omits it from OS_RELEASE_FIELDS, so add it and pin it to
# the single-source firmware version (date-based by default; see
# conf/distro/include/fus-update-features.inc). VERSION_ID is left as the base
# distro version. Matches /etc/fw_version and the bundles' RAUC_BUNDLE_VERSION.
OS_RELEASE_FIELDS:append = " BUILD_ID FUS_SIGNING_VARIANT"
BUILD_ID = "${FUS_UPDATE_FW_VERSION}"

# Say on the device which signing material this image was built with. A vendor
# field, not a freedesktop one, and deliberately in os-release rather than only
# in a release document: an image that trusts a laboratory CA must be
# recognisable on the device that runs it, by anyone holding it, without the
# paperwork that came with it. "dev" is not a defect -- it is the honest label
# for every image built here today.
FUS_SIGNING_VARIANT = "${FUS_UPDATE_CERT_VARIANT}"
