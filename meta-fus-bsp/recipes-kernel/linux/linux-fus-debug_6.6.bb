require recipes-kernel/linux/linux-fus_6.6.bb

PN = "linux-fus-debug"
KERNEL_PACKAGE_NAME = "kernel-debug"
SRC_URI += " file://debug-sources.cfg"

do_configure[depends] += " \
	linux-fus:do_configure \
"

PROVIDES = ""
RPROVIDES:${PN} = ""

FILES:${PN} = ""

# We do not need Device Trees in the Debug build
python () {
    d.setVar('KERNEL_DEVICETREE', '')
}

deltask do_deploy

do_deploy_spdx() {

    local spdx_file="${DEPLOY_DIR_SPDX}/${MACHINE}/recipes/recipe-${PN}.spdx.json"

    if [ -f "$spdx_file" ]; then
        install -d ${DEPLOYDIR}
        install -m 0644 "$spdx_file" "${DEPLOY_DIR_IMAGE}/recipe-${PN}.spdx.json"
    fi
}

addtask do_deploy_spdx after do_create_spdx




