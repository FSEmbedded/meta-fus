# Copyright 2024 F&S Elektronik Systeme GmbH

# used DISABLE_PTEST:pn-qtlanguageserver = 1 disable do_install_ptest_base
python () {
    disable_ptest = d.getVar('DISABLE_PTEST:pn-qtlanguageserver', True) or '1'
    if disable_ptest == '1':
        d.setVarFlag('do_install_ptest_base', 'noexec', '1')
}
