# Copyright (C) 2026 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

DESCRIPTION = "Minimal hardened RAUC A/B production base image. Builds on the bare core image plus \
the A/B machinery only — no evaluation tools, no debug-tweaks, no package management, no example \
application. Product images `require` this and add their own application. The \
build-wide hardening (security flags) comes with the distro."
LICENSE = "MIT"

# bare core image + the A/B machinery. fus-update.bbclass enforces
# read-only-rootfs + overlayfs-etc and pulls the A/B runtime floor. does
# not require the vendor evaluation image, so none of its payload comes
# along.
inherit core-image
inherit fus-update

IMAGE_LINGUAS = ""

# coexists with the evaluation image in one deploy: skip the fixed
# emmc-${MACHINE}.sysimg flash alias (it can belong to only one image).
# images built on this inherit the setting and re-enable it deliberately.
FUS_EMMC_SYSIMG_ALIAS = "0"
