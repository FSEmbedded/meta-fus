FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI:append = " file://60-rtc1-fallback.rules "

do_install:append () {
    install -D -m 0644 \
            ${UNPACKDIR}/60-rtc1-fallback.rules  \
            ${D}${sysconfdir}/udev/rules.d/60-rtc1-fallback.rules
}

