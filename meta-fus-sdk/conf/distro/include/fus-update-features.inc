# distro feature policy for the F&S A/B update configuration. required by every
# distro of this family, so each one ships the update channel: that is what makes
# security updates deliverable over the support period, and the DISTRO name then
# identifies one known configuration in the build metadata.
#
# a build on a foreign distro (the qemuarm64 oeqa multiconfig, for one) does not
# get it that way and must require this file itself.

# partition-identity contract, pulled in here so it is globally parsed and
# visible to the non-image recipes that template against it.
require conf/include/fus-update-layout.inc

DISTRO_FEATURES:append = " overlayfs systemd rauc"

# switch init manager to systemd; overlayfs.bbclass requires systemd.
VIRTUAL-RUNTIME_init_manager ?= "systemd"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"

# RAUC bundle compatible string — the device identity. defined here
# (globally parsed) so it is identical between the device's system.conf
# and every bundle built, without either inheriting the image class.
RAUC_BUNDLE_COMPATIBLE ?= "fus-update-${MACHINE}"

# firmware/OS version — single source for the whole image; date-based by
# default, override per release to pin. [vardepsexclude] keeps the literal
# "${DATE}" out of task signatures so a build spanning midnight stays
# deterministic. distinct from the app version (etc/app_version).
FUS_UPDATE_FW_VERSION ?= "${DATE}"
FUS_UPDATE_FW_VERSION[vardepsexclude] = "DATE"

# downgrade floor baked into the device (RAUC min-bundle-version); defaults
# to the firmware version, override per release to pin an explicit floor.
FUS_UPDATE_MIN_BUNDLE_VERSION ?= "${FUS_UPDATE_FW_VERSION}"

# --- runtime app-health / auto-revert (opt-in; disabled by default) ---
# "1" enables the health layer
FUS_UPDATE_HEALTH         ?= "0"
# confirm-or-reboot deadline (s) after boot
FUS_UPDATE_HEALTH_TIMEOUT ?= "120"
# hardware watchdog (RuntimeWatchdogSec); "0" disables
FUS_UPDATE_WATCHDOG_SEC   ?= "60"

# --- application payload identity ("bring your own app" contract) -----------
# the image/bundle/selfcheck machinery is app-agnostic; these variables are
# the only place an app's name/binaries/packages are pinned. fus-demo-app
# is the reference consumer — override to ship a different application
# without touching any recipe or class.
#
# payload package(s): installed into the app image (slot/container) or, in
# rootfs mode, into the main rootfs under the app prefix.
FUS_UPDATE_APP_PACKAGES          ?= "fus-demo-app"
# launcher package(s): the systemd launcher unit + health probe, installed
# into the main system rootfs in every mode.
FUS_UPDATE_APP_LAUNCHER_PACKAGES ?= "fus-demo-app-launcher"
# executable(s) the payload must ship (space-separated); asserted by
# fus_selfcheck_app_payload.
FUS_UPDATE_APP_BINARIES          ?= "fus-demo-app"
# container-mode app image stem — the canonical artifact name, globally
# parsed so every consumer sees the same value. override this alone to
# rename the artifact.
FUS_APP_CONTAINER_NAME           ?= "fus-app-container"
# container-mode app image filename; follows FUS_APP_CONTAINER_NAME.
FUS_UPDATE_APP_CONTAINER_IMAGE   ?= "${FUS_APP_CONTAINER_NAME}.squashfs"
# app identity — baked into etc/app-release (APP_ID/IMAGE_ID) and asserted
# by the selfcheck. distinct from the binary name and the image stem.
FUS_UPDATE_APP_ID                ?= "fus-demo-app"
# human-readable app name — baked into etc/app-release (PRETTY_NAME).
FUS_UPDATE_APP_DESCRIPTION       ?= "F&S example application"

# RAUC signing material — external, persistent directory, never in git.
# dev material is generated out of band by fus-update-gen-certs.sh; the
# recipes only read these paths and fail with
# guidance if missing. point FUS_UPDATE_CERT_DIR at a persistent location;
# for production set FUS_UPDATE_CERT_VARIANT = "prod" and provide the
# material out of band (the generator refuses to create prod keys).
FUS_UPDATE_CERT_VARIANT   ?= "dev"
FUS_UPDATE_CERT_DIR       ?= "${TOPDIR}/certs"
FUS_UPDATE_KEYRING_FILE   ?= "${FUS_UPDATE_CERT_DIR}/${FUS_UPDATE_CERT_VARIANT}/ca.cert.pem"
FUS_UPDATE_SIGN_KEY_FILE  ?= "${FUS_UPDATE_CERT_DIR}/${FUS_UPDATE_CERT_VARIANT}/sign.key.pem"
FUS_UPDATE_SIGN_CERT_FILE ?= "${FUS_UPDATE_CERT_DIR}/${FUS_UPDATE_CERT_VARIANT}/sign.cert.pem"

# signing material of the application payload (dm-verity root hash). defaults
# to the bundle material; a production build points both at a dedicated
# app-purpose leaf. set globally (local.conf or distro), never per recipe or
# per machine: the image class signs with it and the runtime package installs
# the same certificate as the one the device verifies against.
FUS_APP_CONTAINER_SIGN_KEY  ?= "${FUS_UPDATE_SIGN_KEY_FILE}"
FUS_APP_CONTAINER_SIGN_CERT ?= "${FUS_UPDATE_SIGN_CERT_FILE}"

# hawkBit client device configuration, templated into
# /etc/rauc-hawkbit-updater/config.conf. defaults are empty/dev so no
# deployment secret is baked into the layer; with an empty server the
# updater service ships but stays disabled.
FUS_UPDATE_HAWKBIT_SERVER ?= ""
FUS_UPDATE_HAWKBIT_TENANT ?= "DEFAULT"
FUS_UPDATE_HAWKBIT_TARGET ?= "${MACHINE}-01"
FUS_UPDATE_HAWKBIT_TOKEN  ?= ""
FUS_UPDATE_HAWKBIT_SSL    ?= "false"
