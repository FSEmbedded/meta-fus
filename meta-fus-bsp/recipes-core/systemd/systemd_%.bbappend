FILESEXTRAPATHS:prepend := "${THISDIR}/${BPN}:"

PACKAGECONFIG[unmanaged-network] = ""

do_install:append () {

    # Disable the assignment of the fixed network interface name.
	# We decided to keep this for backward compatibility
	# but may use Predictable Network Interface Names in the future
    install -d ${D}${sysconfdir}/systemd/network
    ln -s /dev/null ${D}${sysconfdir}/systemd/network/99-default.link

    # Configure the network as unmanaged
    if [ "${@bb.utils.filter('PACKAGECONFIG', 'unmanaged-network', d)}" ]; then
        install -Dm 0644 ${WORKDIR}/69-unmanage.network ${D}${sysconfdir}/systemd/network/
    fi
}
