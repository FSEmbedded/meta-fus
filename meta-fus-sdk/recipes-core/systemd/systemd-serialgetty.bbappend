do_install:prepend() {
	if [ "${SERIAL_CONSOLES}" == "FUS_LOGIN_CONSOLE" ] ; then
		install -d ${D}${systemd_system_unitdir}/
		ln -sf {systemd_system_unitdir}/serial-getty@.service ${D}${systemd_system_unitdir}/fsserial-getty@.service
		return 0
	fi
}

FILES:${PN} += "${systemd_system_unitdir}/fsserial-getty@.service "
