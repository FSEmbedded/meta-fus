# Copyright 2024 F&S Elektronik Systeme GmbH

# Enable building of examples
PACKAGECONFIG += " \
    examples \
"

# The function do_install_ptest_base needs big amount of RAM
# Conditionally disable the do_install_ptest_base task with default value 1 for qtdeclarative
# use python call because of warning (See YP bug #13808)
python () {
    disable_ptest = d.getVar('DISABLE_PTEST:pn-qtdeclarative', True) or '1'
    if disable_ptest == '1':
        d.setVarFlag('do_install_ptest_base', 'noexec', '1')
}

# disable debug builds to handle QA issue waring
DEBUG_BUILD = "0"
INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
