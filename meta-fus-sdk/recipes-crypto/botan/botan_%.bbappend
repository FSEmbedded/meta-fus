# fs-updater-lib requires botan-2 (CMake finds botan-2.pc).
# meta-oe scarthgap ships botan 3.x, so pin the recipe back to 2.19.5.
# Remove this bbappend once fs-updater-lib migrates to botan-3.
PV = "2.19.5"
SRC_URI = "https://botan.randombit.net/releases/Botan-${PV}.tar.xz"
SRC_URI[sha256sum] = "dfeea0e0a6f26d6724c4af01da9a7b88487adb2d81ba7c72fcaf52db522c9ad4"
LIC_FILES_CHKSUM = "file://license.txt;md5=f4ce98476c07c34e1793daa036960fad"

DISABLE_STATIC = ""
DEPENDS += " sed-native \
"
do_configure() {
    python3 ${S}/configure.py \
    --prefix="${D}${prefix}" \
    --cpu="${CPU}" \
    --cc-bin="${CXX}" \
    --cxxflags="${CXXFLAGS}" \
    --ldflags="${LDFLAGS}" \
    --with-endian=${@oe.utils.conditional('SITEINFO_ENDIANNESS', 'le', 'little', 'big', d)} \
    ${@bb.utils.contains("TUNE_FEATURES","neon","","--disable-neon",d)} \
    --with-sysroot-dir=${STAGING_DIR_TARGET} \
    --with-build-dir="${B}" \
    --optimize-for-size \
    --build-targets=static,shared,cli \
    --with-stack-protector \
    --with-python-versions=3 \
    ${EXTRA_OECONF}
}

do_install() {
    oe_runmake install
    sed -i -e "s|${D}||g" ${D}${libdir}/pkgconfig/botan-2.pc
}
