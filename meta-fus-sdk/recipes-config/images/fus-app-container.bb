SUMMARY = "Verity-signed application squashfs for the container app-update mode"
DESCRIPTION = "Builds the app payload as a bare squashfs image with a dm-verity \
hash tree + PKCS7-signed root hash (verity-sidecar form, IMAGE-keyed naming). \
The 4 output files (.squashfs/.squashfs.verity/.squashfs.roothash/.squashfs.roothash.p7s) \
are deployed to ${DEPLOY_DIR_IMAGE} and referenced directly as RAUC bundle members \
(fus-app-bundle.bb) -- no tar packing, no systemd-sysext. The app tree is built \
normally by the image class; fus-app-container.bbclass adds the \
squashfs+verity+sign postprocess step. Runtime verification (veritysetup open \
against the pinned leaf cert) is fus-app-container-runtime's job, not RAUC's or \
systemd's."
LICENSE = "MIT"

# app payload -- same packages as fus-app-image.bb (slot mode).
IMAGE_INSTALL = "${FUS_UPDATE_APP_PACKAGES}"

# lean: no image features, no recommendations, no extra languages.
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# no automatic image format: the squashfs is produced by the
# fus-app-container.bbclass postprocess step.
IMAGE_FSTYPES = ""

inherit image fus-app-container

# cyclonedx-export deploys a shared bom.json that would collide with the
# system image's; the app payload's SBOM is covered by the combined image.
do_deploy_cyclonedx[noexec] = "1"
