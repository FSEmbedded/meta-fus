FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " file://psplash-colors.h \
                  file://psplash-config.h \
                  file://radeon-font.h	"

SPLASH_IMAGES = "file://FS-Logo-256px.png;outsuffix=default"

do_configure:prepend() {
	install -m 0644 ${WORKDIR}/psplash-colors.h ${S}/
	install -m 0644 ${WORKDIR}/psplash-config.h ${S}/
	install -m 0644 ${WORKDIR}/radeon-font.h ${S}/
}
