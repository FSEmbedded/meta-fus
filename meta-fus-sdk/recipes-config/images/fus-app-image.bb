SUMMARY = "Application slot image (A/B appfs payload), mounted read-only at /opt/fus-app"
DESCRIPTION = "The filesystem written to the App_A/App_B slots. It is mounted \
read-only at /opt/fus-app by fus-app-mount and never boots, so it carries only \
the application payload — no init, no package management. RAUC writes it raw \
to the inactive app slot; writable application state belongs on /data."
LICENSE = "MIT"

IMAGE_INSTALL = "${FUS_UPDATE_APP_PACKAGES}"

# lean: keep the squashfs to the payload and its hard deps, not a
# bootable mini-distro.
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# read-only squashfs, raw-copied into the App_A/B partition;
# byte-deterministic so the post-install read-back verification works.
IMAGE_FSTYPES            = "squashfs"

inherit image fus-selfcheck

# app-payload contract check; slot mode has no squashfs+verity postprocess
# class (unlike container), so wire it directly over this image's rootfs.
IMAGE_POSTPROCESS_COMMAND += "fus_selfcheck_app_payload;"

# cyclonedx-export deploys a shared bom.json that would collide with the
# system image's; the app image's SBOM is covered by the combined image.
do_deploy_cyclonedx[noexec] = "1"
