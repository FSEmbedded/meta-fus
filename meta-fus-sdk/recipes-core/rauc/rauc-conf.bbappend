FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Override only the example system.conf shipped by meta-rauc with the
# F&S A/B slot layout. Placeholders are filled from the globally-parsed
# layout/feature includes so one template serves every F&S machine and
# the slot devices track the single partition-identity source
# (conf/include/fus-update-layout.inc):
#   @@COMPATIBLE@@         <- RAUC_BUNDLE_COMPATIBLE        (device identity)
#   @@PARTLABEL_*@@        <- FUS_UPDATE_PARTLABEL_*        (by-partlabel devices)
#   @@DATA_DIR@@           <- ${FUS_UPDATE_DATA_MOUNT}/rauc
#   @@MIN_BUNDLE_VERSION@@ <- FUS_UPDATE_MIN_BUNDLE_VERSION (downgrade floor)
#
# The device keyring (ca.cert.pem) is replaced with the real CA from the
# external, generated signing material (FUS_UPDATE_KEYRING_FILE) instead of
# the empty upstream placeholder — see do_install:append below. The keyring
# is generated out of band (meta-fus-sdk/scripts/fus-update-gen-certs.sh); we only read it here.

# the generated slot configuration carries this machine's compatible string,
# so the package cannot be shared between machines of one architecture.
PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI:append = " file://system.conf.in"

do_install:prepend() {
    sed \
        -e 's|@@COMPATIBLE@@|${RAUC_BUNDLE_COMPATIBLE}|g' \
        -e 's|@@DATA_DIR@@|${FUS_UPDATE_DATA_MOUNT}/rauc|g' \
        -e 's|@@MIN_BUNDLE_VERSION@@|${FUS_UPDATE_MIN_BUNDLE_VERSION}|g' \
        ${WORKDIR}/system.conf.in > ${WORKDIR}/system.conf

    # Generate the OS slot section for the active boot mode (see system.conf.in):
    #   slot   — boot.0/.1 (BOOT_A/B) carry the bootname; rootfs.0/.1 parent=boot.x
    #   rootfs — no boot slot; rootfs.0/.1 (Root_A/B) carry the bootname, no parent
    # ROOTFS_PARENT below also re-parents the appfs slot (app=slot) onto the slot
    # that holds the bootname, so the app stays in the active slot's install group.
    case "${FUS_UPDATE_BOOT_MODE}" in
        rootfs)
            printf '[slot.rootfs.0]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nbootname=A\n\n[slot.rootfs.1]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nbootname=B\n' \
                "${FUS_UPDATE_PARTLABEL_ROOT_A}" "${FUS_UPDATE_PARTLABEL_ROOT_B}" \
                >> ${WORKDIR}/system.conf
            APP_PARENT_0="rootfs.0"
            APP_PARENT_1="rootfs.1"
            ;;
        slot)
            printf '[slot.boot.0]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nbootname=A\n\n[slot.boot.1]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nbootname=B\n\n[slot.rootfs.0]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nparent=boot.0\n\n[slot.rootfs.1]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nparent=boot.1\n' \
                "${FUS_UPDATE_PARTLABEL_BOOT_A}" "${FUS_UPDATE_PARTLABEL_BOOT_B}" \
                "${FUS_UPDATE_PARTLABEL_ROOT_A}" "${FUS_UPDATE_PARTLABEL_ROOT_B}" \
                >> ${WORKDIR}/system.conf
            APP_PARENT_0="boot.0"
            APP_PARENT_1="boot.1"
            ;;
        *)
            # Unreachable today (the layout include validates the enum), but a
            # NEW boot mode must wire its slot graph here consciously instead of
            # silently inheriting the slot layout.
            bbfatal "rauc-conf: no system.conf slot graph wired for FUS_UPDATE_BOOT_MODE='${FUS_UPDATE_BOOT_MODE}'"
            ;;
    esac

    # Append the application section for the active update mode. The OS slots
    # above own the boot dimension; only the app differs:
    #   slot      — an App_A/App_B slot group (parent = the bootname slot), like the OS slots
    #   container — a nominal, parent-less raw slot on the data partition: RAUC's
    #               own device-write machinery is NOT used here, the app.raucb
    #               bundle's install hook does the actual file write
    #               (fs-updater's atomic .incoming rename into
    #               FUS_UPDATE_APP_IMG_DIR); this slot only needs to exist so
    #               RAUC accepts an app.raucb bundle targeting it.
    #   rootfs    — none: the app rides the rootfs slot
    case "${FUS_UPDATE_APP_MODE}" in
        slot)
            printf '\n[slot.appfs.0]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nparent=%s\n\n[slot.appfs.1]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nparent=%s\n' \
                "${FUS_UPDATE_PARTLABEL_APP_A}" "${APP_PARENT_0}" \
                "${FUS_UPDATE_PARTLABEL_APP_B}" "${APP_PARENT_1}" \
                >> ${WORKDIR}/system.conf
            ;;
        container)
            # allow-mounted is required: the device (the data partition) is
            # always mounted at /data while the system is running, and RAUC's
            # pre-install check otherwise refuses to touch a mounted slot
            # device. Safe here because the bundle's install hook (not RAUC's
            # own raw write) does the actual write, staged through the
            # already-mounted filesystem via the atomic .incoming rename.
            printf '\n[slot.appfs.0]\ndevice=/dev/disk/by-partlabel/%s\ntype=raw\nallow-mounted=true\n' \
                "${FUS_UPDATE_PARTLABEL_DATA}" \
                >> ${WORKDIR}/system.conf
            ;;
        rootfs)
            : # no app section: the app rides the rootfs slot
            ;;
        *)
            # Unreachable today (the layout include validates the enum), but a
            # NEW app mode must wire its app section here consciously instead of
            # silently getting none.
            bbfatal "rauc-conf: no system.conf app section wired for FUS_UPDATE_APP_MODE='${FUS_UPDATE_APP_MODE}'"
            ;;
    esac
}

# Ship the real CA as the device keyring and move both it and the generated
# system.conf out of ${sysconfdir}.
#
# /etc is a writable overlay whose upper lives on the persistent data partition
# and is independent of the slot, so a file copied up there once beats every
# later image, across A/B updates. That is not theoretical: a device was found
# honouring the slot graph and the downgrade floor of a superseded image
# because its system.conf had been copied up. Under ${nonarch_libdir} both
# files sit in the read-only rootfs, travel with the slot, and cannot be
# shadowed; RAUC finds them because /usr/lib/rauc is the last entry of its own
# search order, and ${sysconfdir}/rauc stays free for a deliberate
# administrator override that then legitimately wins.
#
# The base recipe installs both unconditionally into ${sysconfdir}/rauc, so
# they are moved rather than merely also-installed: leaving the originals would
# ship two copies, and the /etc one would keep winning.
do_install:append() {
    fus_selfcheck_keyring_material "rauc-conf (device keyring)" "${FUS_UPDATE_KEYRING_FILE}"
    fus_selfcheck_production_material "rauc-conf (device keyring)" \
        "${FUS_UPDATE_CERT_VARIANT}" "${FUS_UPDATE_KEYRING_FILE}"

    # The move depends on the base recipe having put system.conf there. Say so
    # if that stops being true: a bare copy-and-remove would otherwise fail
    # somewhere inside do_install with a message about a missing file, and the
    # reader would have to work out that the upstream layout changed.
    if [ ! -f ${D}${sysconfdir}/rauc/system.conf ]; then
        bbfatal "fus-selfcheck(rauc-conf): the base recipe did not install \
${sysconfdir}/rauc/system.conf. Its layout changed, so this move -- and the \
selfcheck that asserts nothing stays behind -- must be re-checked before it can \
be trusted."
    fi

    install -d ${D}${nonarch_libdir}/rauc
    install -m 0644 ${D}${sysconfdir}/rauc/system.conf ${D}${nonarch_libdir}/rauc/system.conf
    install -m 0644 "${FUS_UPDATE_KEYRING_FILE}" ${D}${nonarch_libdir}/rauc/ca.cert.pem
    rm -r ${D}${sysconfdir}/rauc

    # Firmware version marker (single source: FUS_UPDATE_FW_VERSION). Distinct
    # from the application version at ${FUS_UPDATE_APP_MOUNT}/etc/app_version;
    # also mirrored into /etc/os-release (VERSION_ID/BUILD_ID).
    install -d ${D}${sysconfdir}
    echo "${FUS_UPDATE_FW_VERSION}" > ${D}${sysconfdir}/fw_version
}

FILES:${PN} += "${sysconfdir}/fw_version ${nonarch_libdir}/rauc"

# Rebuild when the external keyring changes (it is not a SRC_URI input).
do_install[file-checksums] += "${FUS_UPDATE_KEYRING_FILE}:False"

# Build-time guard: assert the GENERATED slot graph matches BOTH mode
# dimensions (boot: parent=/bootname graph; app: appfs slots vs artifact repo
# vs none), so a wrong graph — which would silently break A/B activation or
# the app delivery — fails the build, not a non-booting board. The check
# itself lives in the fus-selfcheck.bbclass catalog.
inherit fus-selfcheck
do_install[postfuncs] += "fus_selfcheck_systemconf"
