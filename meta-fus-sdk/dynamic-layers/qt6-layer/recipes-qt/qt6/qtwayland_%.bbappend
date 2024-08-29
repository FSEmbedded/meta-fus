# Copyright 2024 F&S Elektronik Systeme GmbH

# find is used to locate all .h files in all subdirectories under /usr/include/*/${PV}.
# Each found file is then checked to see if it contains a reference to ${TMPDIR},
# and if so, this reference is replaced with /tmp.
# Use to handle the warning:
# ... do_package_qa: QA Issue: File *.h in package qtwayland-dev contains reference to TMPDIR
do_install:append() {
    find ${D}/usr/include/*/${PV} -type f -name "*.h" | while read -r file; do
        if grep -q "${TMPDIR}" "$file"; then
            sed -i -e 's|${TMPDIR}|/tmp|g' "$file"
        fi
    done
}

# used DISABLE_PTEST:pn-qtwayland = 1 disable do_install_ptest_base
python () {
    disable_ptest = d.getVar('DISABLE_PTEST:pn-qtwayland', True) or '1'
    if disable_ptest == '1':
        d.setVarFlag('do_install_ptest_base', 'noexec', '1')
}

# disable debug builds to handle QA issue waring
DEBUG_BUILD = "0"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
