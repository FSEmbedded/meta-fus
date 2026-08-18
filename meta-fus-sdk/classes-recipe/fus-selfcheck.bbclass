# fus-selfcheck.bbclass
#
# The single catalog of build-time hardening assertions for the RAUC A/B
# invariants. These guard the classes of config error that otherwise surface
# only after a full rebuild + a manual board flash:
#   - the kernel/bootloader missing required CONFIG_* symbols,
#   - a system.conf slot graph that does not match the boot/app mode,
#   - absent externally-generated signing material.
#
# The helpers bb.fatal on violation so a broken input fails at build time,
# not on hardware. They assert only -- no runtime behaviour change. Inherit
# this class and wire the relevant helper as a task post/prefunc (or call the
# argument-taking helpers from your own task functions).

# Assert that the built kernel .config has every required CONFIG_* enabled
# (=y or =m). Intended as a linux-fus do_configure[postfuncs]: ${B}/.config
# exists and is final once do_configure has run. Anchored grep so a
# "# CONFIG_FOO is not set" line or a substring match does NOT count as enabled.
#
# Reads the required symbols from FUS_SELFCHECK_KCONFIG (space-separated bare
# symbol names, e.g. "CONFIG_DM_VERITY CONFIG_SQUASHFS CONFIG_OVERLAY_FS").
#
# The .config location defaults to ${B}/.config (linux-fus). U-Boot builds each
# UBOOT_CONFIG entry in its own subdir (${B}/<config>_defconfig/.config) and ships
# every one of them, so if the default is absent we check every .config under
# ${B} — keeping this helper usable from a u-boot-fus do_configure[postfuncs]
# without hardcoding the defconfig subdir names.
FUS_SELFCHECK_KCONFIG_FILE ?= "${B}/.config"
fus_selfcheck_kconfig() {
    configs="${FUS_SELFCHECK_KCONFIG_FILE}"
    [ -f "$configs" ] || configs=$(fus_selfcheck_configs)
    if [ -z "$configs" ]; then
        bbfatal "fus-selfcheck: .config not found under ${B}; \
cannot verify the required CONFIG symbols (${FUS_SELFCHECK_KCONFIG})"
    fi

    for config in $configs; do
        bbnote "fus-selfcheck: checking the CONFIG symbols in $config"
        missing=""
        for sym in ${FUS_SELFCHECK_KCONFIG}; do
            if ! grep -Eq "^${sym}=(y|m)\$" "$config"; then
                missing="$missing $sym"
            fi
        done

        if [ -n "$missing" ]; then
            bbfatal "fus-selfcheck: required kernel config symbol(s) not enabled \
(=y/=m) in $config:$missing. These are RAUC A/B prerequisites \
(dm-verity, squashfs read-only rootfs, overlayfs). Add them to the kernel \
config fragment/defconfig."
        fi
    done
}

# Every .config under ${B}, one per bootloader configuration.
fus_selfcheck_configs() {
    find "${B}" -maxdepth 2 -name .config -type f 2>/dev/null | sort
}

# Assert that FUS_ENV_* (fus-uboot-env.inc) matches the bootloader; wire as u-boot-fus
# do_configure[postfuncs]. Boards in the list below take the address from the "emmc-boot"
# env-start of nboot-info.dtsi (the defconfig is only their fallback), all others from it.
FUS_SELFCHECK_ENV_NBOOT ?= "fsimx8mm fsimx8mn fsimx8mp fsimx8ulp fsimx91 fsimx93"
fus_selfcheck_fw_env() {
    configs=$(fus_selfcheck_configs)
    [ -n "$configs" ] ||
        bbfatal "fus-selfcheck: .config not found under ${B}; cannot verify FUS_ENV_*"
    for config in $configs; do
        bbnote "fus-selfcheck: checking FUS_ENV_* against $config"
        fus_selfcheck_fw_env_one "$config"
    done
}

fus_selfcheck_fw_env_one() {
    config="$1"
    have=$(sed -n 's/^CONFIG_ENV_SIZE=//p' "$config")
    size="${FUS_ENV_SIZE}"
    if [ -z "$have" ] || [ "$(printf '%d' "$have")" -ne "$(printf '%d' "$size")" ]; then
        bbfatal "fus-selfcheck: FUS_ENV_SIZE $size != CONFIG_ENV_SIZE '$have'"
    fi

    copies=$(set -- ${FUS_ENV_OFFSETS}; echo $#)
    if grep -q '^CONFIG_SYS_REDUNDAND_ENVIRONMENT=y$' "$config"; then want=2; else want=1; fi
    [ "$copies" -eq "$want" ] ||
        bbfatal "fus-selfcheck: FUS_ENV_OFFSETS has $copies copies, the bootloader $want"

    if [ "${FUS_ENV_MEDIUM}" = nand ]; then
        range=$(sed -n 's/^CONFIG_ENV_NAND_RANGE=//p' "$config")
        if [ -n "$range" ]; then
            sect="${FUS_ENV_SECT}"
            nsect="${FUS_ENV_NSECT}"
            # expr exits 1 when the result is 0 or empty, not only on a syntax error; || true
            # keeps its stdout (still printed on that exit) while not tripping `set -e` here.
            product=$(expr "$(printf '%d' "$sect")" \* "$(printf '%d' "$nsect")" || true)
            if [ -z "$product" ] || [ "$(printf '%d' "$range")" -ne "$product" ]; then
                bbfatal "fus-selfcheck: SECT * NSECT != CONFIG_ENV_NAND_RANGE $range"
            fi
        fi
        return 0
    fi

    case " ${FUS_SELFCHECK_ENV_NBOOT} " in
    *" ${MACHINE} "*)
        dtsi="${S}/board/F+S/${MACHINE}/nboot/nboot-info.dtsi"
        [ -f "$dtsi" ] ||
            bbfatal "fus-selfcheck: $dtsi not found; cannot verify FUS_ENV_OFFSETS"
        cells=$(awk '/emmc-boot[ \t]*\{/{f=1} f&&/env-start/{gsub(/.*<|>.*/,"");print;exit} f&&/\};/{exit}' \
            "$dtsi")
        [ -n "$cells" ] ||
            bbfatal "fus-selfcheck: no env-start in the emmc-boot node of $dtsi"
        # shellcheck disable=SC2086 # the cells are split on purpose
        set -- $cells
        first=$1
        if [ $# -eq 1 ]; then second=$1; else second=$2; fi
        set -- ${FUS_ENV_OFFSETS}
        [ "$(printf '%d' "$first")" -eq "$(printf '%d' "$1")" ] ||
            bbfatal "fus-selfcheck: FUS_ENV_OFFSETS '${FUS_ENV_OFFSETS}' != env-start '$cells'"
        if [ $# -eq 2 ] && [ "$(printf '%d' "$second")" -ne "$(printf '%d' "$2")" ]; then
            bbfatal "fus-selfcheck: FUS_ENV_OFFSETS '${FUS_ENV_OFFSETS}' != env-start '$cells'"
        fi
        ;;
    *)
        have=$(sed -n 's/^CONFIG_ENV_MMC_OFFSET=//p' "$config")
        [ -n "$have" ] || have=$(sed -n 's/^CONFIG_ENV_OFFSET=//p' "$config")
        set -- ${FUS_ENV_OFFSETS}
        if [ -z "$have" ] || [ "$(printf '%d' "$have")" -ne "$(printf '%d' "$1")" ]; then
            bbfatal "fus-selfcheck: FUS_ENV_OFFSETS '${FUS_ENV_OFFSETS}' != offset '$have'"
        fi
        ;;
    esac
}

# Assert the slot-mode CONFIG_PREBOOT override targets the wks file's actual
# Root_A partition index, not a value that drifted from it. Wire as a
# u-boot-fus do_configure[postfuncs], only for FUS_UPDATE_BOOT_MODE=slot.
fus_selfcheck_uboot_ab_env() {
    configs=$(fus_selfcheck_configs)
    [ -n "$configs" ] ||
        bbfatal "fus-selfcheck: .config not found under ${B}; cannot verify the slot-mode CONFIG_PREBOOT override"
    for config in $configs; do
        bbnote "fus-selfcheck: checking the slot-mode CONFIG_PREBOOT in $config"
        fus_selfcheck_uboot_ab_env_one "$config"
    done
}

fus_selfcheck_uboot_ab_env_one() {
    config="$1"
    wks="${@bb.utils.which(d.getVar('BBPATH'), 'wic/' + ('fus-update-emmc.wks.in' if d.getVar('FUS_UPDATE_APP_MODE') == 'slot' else 'fus-update-emmc-noappslot.wks.in'))}"
    [ -n "$wks" ] && [ -f "$wks" ] ||
        bbfatal "fus-selfcheck: slot-mode wks file not found via BBPATH"

    idx=$(awk '/^part /{n++} /--part-name \$\{FUS_UPDATE_PARTLABEL_ROOT_A\}/{print n; exit}' "$wks")
    [ -n "$idx" ] || bbfatal "fus-selfcheck: no Root_A partition found in $wks"

    preboot=$(sed -n 's/^CONFIG_PREBOOT="\(.*\)"$/\1/p' "$config")
    case "$preboot" in
    *".rootfs_part_A $idx"*) : ;;
    *)
        bbfatal "fus-selfcheck: FUS_UPDATE_BOOT_MODE=slot but CONFIG_PREBOOT does not \
set .rootfs_part_A to $idx (the wks file's actual Root_A index). Got: $preboot"
        ;;
    esac
}

# Assert that externally-generated signing material exists (task-time, before
# openssl would fail cryptically). Argument-taking: call it from a task
# function, e.g. from a do_bundle:prepend:
#   fus_selfcheck_signing_material "${PN}" "${RAUC_KEY_FILE}" "${RAUC_CERT_FILE}"
#
# A key is not necessarily a file. The BSP offers three ways to hold the signing
# key, and only one of them has a path: a file, a PKCS#11 URI naming a key that
# never leaves its token, and an external signing tool that the build calls. A
# URI put through a file test would be reported as "missing" -- the failure a
# customer with an HSM would hit first, and the one that reads as if their setup
# were broken. So the check is on the shape first: anything that is not a plain
# path is passed through untouched, and only a path is required to exist.
fus_selfcheck_signing_material() {
    ctx="$1"; shift
    for f in "$@"; do
        case "$f" in
        pkcs11:*)
            # The token answers for it, not the filesystem. Nothing to check here
            # that would not be a guess.
            continue
            ;;
        esac
        if [ ! -f "$f" ]; then
            bbfatal "$ctx: signing material missing: $f. Generate the dev \
signing material out of band first, e.g.: \
meta-fus-sdk/scripts/fus-update-gen-certs.sh. A key held in a \
token is named by a pkcs11: URI and is not looked for on disk."
        fi
    done
}

# The device keyring is the one piece of material that can never be a URI: it
# is copied into the rootfs as a file, so a token reference here cannot be
# honoured by anything downstream. Checking it with the function above would
# wave a pkcs11: URI through and leave the build to fail later at the install
# step with "No such file or directory" -- exactly the cryptic failure that
# function exists to prevent. Argument-taking:
#   fus_selfcheck_keyring_material <ctx> <keyring file>
fus_selfcheck_keyring_material() {
    ctx="$1"; shift
    for f in "$@"; do
        case "$f" in
        pkcs11:*)
            bbfatal "$ctx: the device keyring cannot be a PKCS#11 URI ($f). It is \
copied into the rootfs as a file and read there by RAUC; only the signing key may \
live in a token."
            ;;
        esac
        if [ ! -f "$f" ]; then
            bbfatal "$ctx: keyring missing: $f. Generate the dev signing material \
out of band first, e.g.: meta-fus-sdk/scripts/fus-update-gen-certs.sh"
        fi
    done
}

# The gate for a production build, and it points the way round from the obvious
# one: it is not "production must not use dev keys" as a wish, it is a build
# that CLAIMS to be production and is handed development material stopping right
# there. Dev material is recognised by where it lives -- the generator writes
# each variant into its own directory -- so this catches the realistic mistake
# (a prod build inheriting the dev defaults) rather than trying to judge a
# certificate's intent. Argument-taking:
#   fus_selfcheck_production_material <ctx> <cert-variant> <material>...
fus_selfcheck_production_material() {
    ctx="$1"; variant="$2"; shift 2
    # The variant is compared, not parsed, so a near miss disables this gate in
    # silence -- and it is baked into os-release as the image's own label, where
    # the same typo mislabels the device. Every caller passes it through here,
    # so this is the one place that has to know the alphabet.
    case "$variant" in
    dev|prod) ;;
    *)
        bbfatal "$ctx: FUS_UPDATE_CERT_VARIANT='$variant' is not a variant this \
layer knows; it is either dev or prod. A near miss such as 'Prod' would leave \
the production material gate silently disabled."
        ;;
    esac
    [ "$variant" = "prod" ] || return 0
    for f in "$@"; do
        case "$f" in
        */certs/dev/*|*/dev/ca.cert.pem|*/dev/sign.*.pem)
            bbfatal "$ctx: this image declares FUS_UPDATE_CERT_VARIANT=prod but \
is signed with development material: $f. Provide the production key, \
certificate and CA out of band and point FUS_UPDATE_CERT_DIR at them; the \
generator deliberately refuses to create production keys."
            ;;
        esac
    done
}

# Warn (never fatal) when a production build signs the app payload with the SAME
# certificate as the RAUC bundle. Sharing one key across two trust purposes
# means a compromise of either dimension forges both; a production deployment
# should sign the app with a dedicated app-purpose leaf. Dev/eval builds
# intentionally share the one dev key, so this only fires for the prod cert
# variant. Argument-taking:
#   fus_selfcheck_pki_purpose_separation <ctx> <cert-variant> <app-cert> <bundle-cert>
fus_selfcheck_pki_purpose_separation() {
    ctx="$1"; variant="$2"; app_cert="$3"; bundle_cert="$4"
    [ "$variant" = "prod" ] || return 0
    [ -f "$app_cert" ] && [ -f "$bundle_cert" ] || return 0
    fa=$(openssl x509 -in "$app_cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    fb=$(openssl x509 -in "$bundle_cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    if [ -n "$fa" ] && [ "$fa" = "$fb" ]; then
        bbwarn "$ctx: the app payload is signed with the SAME certificate as the \
RAUC bundle (SHA-256 fingerprint $fa). A production build should sign the app \
with a dedicated app-purpose signing leaf so a compromise of one signing \
purpose cannot forge the other. Provision a separate app-signing key/cert and \
point FUS_APP_CONTAINER_SIGN_KEY / FUS_APP_CONTAINER_SIGN_CERT at it."
    fi
}

# assert the generated system.conf slot graph matches both mode dimensions
# (boot and app). wire as a rauc-conf do_install[postfuncs].
fus_selfcheck_systemconf() {
    conf="${D}${nonarch_libdir}/rauc/system.conf"
    [ -f "$conf" ] || bbfatal "fus-selfcheck: $conf not generated"

    # The config and its keyring must not ALSO ship under ${sysconfdir}: /etc is
    # a writable overlay whose upper outlives the image, so a copy there can be
    # frozen and would then win over every later one. Two copies also pass every
    # content check below while the device honours the wrong file.
    for stray in "${D}${sysconfdir}/rauc/system.conf" "${D}${sysconfdir}/rauc/ca.cert.pem"; do
        [ -e "$stray" ] && bbfatal "fus-selfcheck: $stray is still installed; \
the writable /etc overlay can freeze it and it would beat ${nonarch_libdir}/rauc"
    done

    # Boot dimension: where the bootname lives and what parents onto it.
    if [ "${FUS_UPDATE_BOOT_MODE}" = "rootfs" ]; then
        # No boot slot; nothing may reference one; the rootfs slot carries bootname.
        grep -q '^\[slot\.boot\.' "$conf" && \
            bbfatal "fus-selfcheck(boot-rootfs): unexpected [slot.boot.*] in system.conf"
        grep -q '^parent=boot' "$conf" && \
            bbfatal "fus-selfcheck(boot-rootfs): a slot still has parent=boot.* (must be rootfs.* in boot-rootfs)"
        grep -q '^bootname=' "$conf" || \
            bbfatal "fus-selfcheck(boot-rootfs): no bootname= in system.conf (expected on the rootfs slots)"
    else
        grep -q '^\[slot\.boot\.0\]' "$conf" || \
            bbfatal "fus-selfcheck(boot-slot): [slot.boot.0] missing in system.conf"
        grep -q '^parent=boot\.' "$conf" || \
            bbfatal "fus-selfcheck(boot-slot): rootfs slot has no parent=boot.* in system.conf"
    fi

    # App dimension: the mode decides between an appfs slot pair (slot), a
    # nominal single appfs slot (container), or no app section at all (rootfs).
    case "${FUS_UPDATE_APP_MODE}" in
        slot)
            # The bootname-carrying slot is the appfs parent in BOTH boot modes.
            if [ "${FUS_UPDATE_BOOT_MODE}" = "rootfs" ]; then
                want="rootfs"
            else
                want="boot"
            fi
            for i in 0 1; do
                grep -q "^\[slot\.appfs\.$i\]" "$conf" || \
                    bbfatal "fus-selfcheck(app-slot): [slot.appfs.$i] missing in system.conf"
                sed -n "/^\[slot\.appfs\.$i\]/,/^\[/p" "$conf" | grep -q "^parent=${want}\.$i\$" || \
                    bbfatal "fus-selfcheck(app-slot): appfs.$i must have parent=${want}.$i (the bootname slot)"
            done
            grep -q '^\[artifacts\.' "$conf" && \
                bbfatal "fus-selfcheck(app-slot): unexpected [artifacts.*] repository in system.conf"
            ;;
        rootfs)
            grep -Eq '^\[slot\.appfs\.|^\[artifacts\.' "$conf" && \
                bbfatal "fus-selfcheck(app-rootfs): unexpected app section in system.conf (the app rides the rootfs slot)"
            ;;
        container)
            # One nominal, parent-less raw slot on the data partition (see
            # rauc-conf.bbappend) — not part of the bootname parent chain,
            # and not a slot pair like app-slot.
            grep -q '^\[slot\.appfs\.0\]' "$conf" || \
                bbfatal "fus-selfcheck(app-container): [slot.appfs.0] missing in system.conf"
            sed -n '/^\[slot\.appfs\.0\]/,/^\[/p' "$conf" | grep -q '^parent=' && \
                bbfatal "fus-selfcheck(app-container): appfs.0 must NOT have a parent= (nominal data-partition slot, not part of the boot chain)"
            sed -n '/^\[slot\.appfs\.0\]/,/^\[/p' "$conf" | grep -q '^allow-mounted=true$' || \
                bbfatal "fus-selfcheck(app-container): appfs.0 must have allow-mounted=true — its device (the data partition) is always mounted while the system runs, and RAUC's pre-install check rejects a mounted slot device without this flag."
            grep -q '^\[slot\.appfs\.1\]' "$conf" && \
                bbfatal "fus-selfcheck(app-container): unexpected second [slot.appfs.1] (container has one nominal slot, not a pair)"
            grep -q '^\[artifacts\.' "$conf" && \
                bbfatal "fus-selfcheck(app-container): unexpected [artifacts.*] repository in system.conf"
            ;;
        *)
            # Unreachable today (the layout include validates the enum), but a
            # NEW app mode must wire its system.conf assertion here consciously
            # instead of silently skipping it.
            bbfatal "fus-selfcheck: no app-dimension assertion wired for FUS_UPDATE_APP_MODE='${FUS_UPDATE_APP_MODE}'"
            ;;
    esac
    :
}

# assert a container-mode app squashfs ships all 3 verity sidecars, keyed on
# the full squashfs filename ("$img.verity" etc., as the runtime mount verb
# looks them up), not on the stem.
#   fus_selfcheck_container_artifact <deploy-dir> <image-filename>
fus_selfcheck_container_artifact() {
    _out="$1"
    _img="$2"

    if [ ! -s "$_out/$_img" ]; then
        bbfatal "fus-selfcheck: container app image missing/empty: $_out/$_img."
    fi
    for s in verity roothash roothash.p7s; do
        if [ ! -s "$_out/$_img.$s" ]; then
            bbfatal "fus-selfcheck: container app sidecar missing/empty: $_out/$_img.$s. \
The container app image needs all 3 verity sidecars (.verity/.roothash/.roothash.p7s) \
alongside $_img."
        fi
    done
}

# assert the app payload is complete and self-describing: every binary in
# FUS_UPDATE_APP_BINARIES present and executable, etc/app_version non-empty,
# etc/app-release IMAGE_ID matching FUS_UPDATE_APP_ID. runs over
# ${IMAGE_ROOTFS} of whatever rootfs carries the payload; files are located
# by name because the install prefix differs per app mode.
fus_selfcheck_app_payload() {
    for _bin in ${FUS_UPDATE_APP_BINARIES}; do
        _p="$(find "${IMAGE_ROOTFS}" -type f -name "$_bin" -perm -u+x 2>/dev/null | head -n1)"
        if [ -z "$_p" ]; then
            bbfatal "fus-selfcheck: app binary '$_bin' not found (executable) \
under ${IMAGE_ROOTFS}. The app payload would ship with no program to run. \
FUS_UPDATE_APP_BINARIES lists the executables an app image must carry."
        fi
    done

    _ver="$(find "${IMAGE_ROOTFS}" -type f -name app_version 2>/dev/null | head -n1)"
    if [ -z "$_ver" ] || [ ! -s "$_ver" ]; then
        bbfatal "fus-selfcheck: etc/app_version missing or empty under \
${IMAGE_ROOTFS}. The app-only update path reports the running app version from \
it across a slot switch. The fus-demo-app recipe shows how an app ships it."
    fi

    _rel="$(find "${IMAGE_ROOTFS}" -type f -name app-release 2>/dev/null | head -n1)"
    if [ -z "$_rel" ]; then
        bbfatal "fus-selfcheck: etc/app-release missing under ${IMAGE_ROOTFS}. \
The app payload must ship its self-describing metadata; the fus-demo-app \
recipe shows how."
    fi
    _id="$(sed -n 's/^IMAGE_ID=\(.*\)$/\1/p' "$_rel" | tail -n1)"
    if [ "$_id" != "${FUS_UPDATE_APP_ID}" ]; then
        bbfatal "fus-selfcheck: etc/app-release IMAGE_ID='$_id' does not match \
the configured app id '${FUS_UPDATE_APP_ID}' (FUS_UPDATE_APP_ID). The metadata \
must identify the app it ships."
    fi
}

# assert at least one app-health probe exists under FUS_UPDATE_HEALTH_DIR.
# container mode only: the probe is the sole health signal for the external
# commit/reject decision. runs over the system rootfs (the launcher package
# ships the probe), so wire it from the image class.
fus_selfcheck_health_probe() {
    if [ -z "$(find "${IMAGE_ROOTFS}${FUS_UPDATE_HEALTH_DIR}" -type f 2>/dev/null | head -n1)" ]; then
        bbfatal "fus-selfcheck: no app-health probe under ${FUS_UPDATE_HEALTH_DIR} \
in ${IMAGE_ROOTFS}. In container mode the probe is the only app-health signal \
an external caller has for its commit/reject decision (fus-update-confirm); \
with no probe there is nothing to decide on. Ship at least one health.d probe \
in the launcher package."
    fi
}

# assert the staged botan pkg-config contract is botan-2.x: meta-oe ships
# botan 3.x and only a version-pinning bbappend keeps 2.x in the sysroot.
# wire as a do_configure prefunc of the consuming recipe.
fus_selfcheck_botan2() {
    pc="${STAGING_LIBDIR}/pkgconfig/botan-2.pc"
    if [ ! -f "$pc" ]; then
        bbfatal "fus-selfcheck: botan-2.pc not staged in ${STAGING_LIBDIR}/pkgconfig. \
The updater stack requires botan 2.x; a botan-3-only sysroot cannot satisfy it."
    fi
    if ! grep -Eq '^Version: 2\.' "$pc"; then
        bbfatal "fus-selfcheck: staged botan-2.pc is not version 2.x \
($(grep '^Version:' "$pc" || echo 'no Version line')). Re-check the botan version-pin bbappend."
    fi
}

# assert the generated lib config header matches the layer's device paths:
# FUS_LIB_APP_IMG_STORE == FUS_UPDATE_APP_IMG_DIR (no trailing slash; cmake
# strips it) and FUS_LIB_RAUC_SCRATCH == FSUP_RAUC_SCRATCH (must be on the
# persistent data partition or streaming staging lands in tmpfs). wire as a
# do_configure postfunc of the lib recipe.
FUS_SELFCHECK_LIB_CONFIG_H ?= "${B}/include/fus_updater_lib/config.h"
fus_selfcheck_lib_paths() {
    hdr="${FUS_SELFCHECK_LIB_CONFIG_H}"
    [ -f "$hdr" ] || bbfatal "fus-selfcheck: generated lib config header missing: $hdr"
    if ! grep -qxF "#define FUS_LIB_APP_IMG_STORE \"${FUS_UPDATE_APP_IMG_DIR}\"" "$hdr"; then
        bbfatal "fus-selfcheck: FUS_LIB_APP_IMG_STORE in $hdr does not equal \
'${FUS_UPDATE_APP_IMG_DIR}'. Got: $(grep FUS_LIB_APP_IMG_STORE "$hdr")"
    fi
    if ! grep -qxF "#define FUS_LIB_RAUC_SCRATCH \"${FSUP_RAUC_SCRATCH}\"" "$hdr"; then
        bbfatal "fus-selfcheck: FUS_LIB_RAUC_SCRATCH in $hdr does not equal \
'${FSUP_RAUC_SCRATCH}'. Got: $(grep FUS_LIB_RAUC_SCRATCH "$hdr")"
    fi
}

# pin the fs-updater cli's process-exit ABI at the point of consumption: the
# hawkBit bridge backend and the shared pending-state predicates branch on
# these exact numbers across a process boundary, and the numbers are defined
# in a different repository. fail the consumer's build when a re-pinned
# SRCREV no longer carries them. wire as a do_configure postfunc of the CLI
# recipe.
fus_selfcheck_cli_exit_codes() {
    hdr="${S}/src/cli/fs_updater_error.h"
    [ -f "$hdr" ] || bbfatal "fus-selfcheck: $hdr not found; the process-exit contract cannot be verified"

    _pin() {
        if ! sed -n "/enum class $1 /,/}/p" "$hdr" | \
                grep -Eq "$2[[:space:]]*=[[:space:]]*$3(,|[[:space:]]|$)"; then
            bbfatal "fus-selfcheck: exit-code contract drift: $1::$2 != $3 in $hdr. \
rauc-installer-fsupdater.c and fus-app-container-runtime branch on this exact \
number; re-verify BOTH against the new header before re-pinning the SRCREV."
        fi
    }

    _pin UPDATER_FIRMWARE_STATE                 UPDATE_SUCCESSFUL 0
    _pin UPDATER_APPLICATION_STATE              UPDATE_SUCCESSFUL 4
    _pin UPDATER_FIRMWARE_AND_APPLICATION_STATE UPDATE_SUCCESSFUL 8
    _pin UPDATER_INSTALL_UPDATE_STATE UPDATE_INSTALLATION_IN_PROGRESS 47
    _pin UPDATER_INSTALL_UPDATE_STATE UPDATE_INSTALLATION_FINISHED    48
    _pin UPDATER_INSTALL_UPDATE_STATE UPDATE_INSTALLATION_FAILED      49
    _pin UPDATER_UPDATE_REBOOT_STATE FAILED_APP_UPDATE        20
    _pin UPDATER_UPDATE_REBOOT_STATE FAILED_FW_UPDATE         21
    _pin UPDATER_UPDATE_REBOOT_STATE FW_UPDATE_REBOOT_FAILED  22
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_FW_UPDATE     23
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_APP_UPDATE    24
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_APP_FW_UPDATE 25
    _pin UPDATER_UPDATE_REBOOT_STATE UPDATE_REBOOT_PENDING    26
    _pin UPDATER_UPDATE_REBOOT_STATE NO_UPDATE_REBOOT_PENDING 27
    _pin UPDATER_UPDATE_REBOOT_STATE ROLLBACK_FW_REBOOT_PENDING     28
    _pin UPDATER_UPDATE_REBOOT_STATE ROLLBACK_APP_REBOOT_PENDING    29
    _pin UPDATER_UPDATE_REBOOT_STATE ROLLBACK_APP_FW_REBOOT_PENDING 30
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_FW_ROLLBACK         31
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_APP_ROLLBACK        32
    _pin UPDATER_UPDATE_REBOOT_STATE INCOMPLETE_APP_FW_ROLLBACK     33
    # accepted at boot as "pending, mount state unanswerable".
    _pin UPDATER_UPDATE_REBOOT_STATE UPDATE_REBOOT_STATE_INDETERMINATE 55
    # not accepted at boot; pinned only so it stays distinct from the
    # accepted set.
    _pin UPDATER_UPDATE_REBOOT_STATE ROLLBACK_APP_REBOOT_INDETERMINATE 57
    # verb success codes; none is 0, the CLI never returns 0 for them.
    _pin UPDATER_UPDATE_ROLLBACK_STATE UPDATE_ROLLBACK_SUCCESSFUL 12
    _pin UPDATER_COMMIT_STATE          UPDATE_COMMIT_SUCCESSFUL   16
    _pin UPDATER_COMMIT_STATE          UPDATE_NOT_NEEDED          17
    _pin UPDATER_SETGET_UPDATE_STATE   GETSET_STATE_SUCCESSFUL    52
    # settles an install whose target was never activated; pinned so it
    # stays outside the predicates' success set (16/17).
    _pin UPDATER_COMMIT_STATE          STALLED_INSTALL_SETTLED    58
}

# assert neither unit in the hawkBit -> fs-updater handoff sets PrivateTmp:
# the bundle is handed over as a /tmp path string, so both units must see
# the same /tmp. also asserts the updater's data-mount ordering drop-in
# survived image assembly. wire as a ROOTFS_POSTPROCESS_COMMAND.
fus_selfcheck_install_door() {
    _unitdir="${IMAGE_ROOTFS}${systemd_system_unitdir}"
    for u in fs-updater.service rauc-hawkbit-updater.service; do
        for f in "$_unitdir/$u" "$_unitdir/$u.d/"*.conf; do
            [ -f "$f" ] || continue
            if grep -Eq '^[[:space:]]*PrivateTmp[[:space:]]*=[[:space:]]*(true|yes|on|1)[[:space:]]*$' "$f"; then
                bbfatal "fus-selfcheck: $f sets PrivateTmp -- the hawkBit bundle handoff passes a /tmp path from rauc-hawkbit-updater to fs-updater.service and requires a shared /tmp namespace"
            fi
        done
    done
    # the drop-in is fs-updater-specific; skip images without the service.
    if [ -f "$_unitdir/fs-updater.service" ]; then
        _dropin="$_unitdir/fs-updater.service.d/10-fus-data-mount.conf"
        [ -f "$_dropin" ] || bbfatal "fus-selfcheck: $_dropin missing -- fs-updater.service must order after the persistent data mount"
        grep -q '^RequiresMountsFor=' "$_dropin" || bbfatal "fus-selfcheck: $_dropin carries no RequiresMountsFor="
    fi
}

# assert the deployed rootfs squashfs fits the A/B slot: the bundle-only
# build path strips the wic fstypes, so wic's own size check never runs.
# wire as a do_image_squashfs postfunc. arithmetic via expr, not $(( )):
# bitbake's shell parser fails at parse time on arithmetic expansion.
fus_selfcheck_rootfs_slot_fit() {
    _max=$(expr ${FUS_UPDATE_SIZE_ROOT_MIB} \* 1048576)
    for _img in "${IMGDEPLOYDIR}"/*.squashfs; do
        [ -f "$_img" ] || continue
        _sz=$(stat -c %s "$_img")
        if [ "$_sz" -gt "$_max" ]; then
            bbfatal "fus-selfcheck: $_img is $_sz bytes and does not fit the \
${FUS_UPDATE_SIZE_ROOT_MIB} MiB rootfs slot ($_max bytes). Shrink the image or raise \
FUS_UPDATE_SIZE_ROOT_MIB -- note that raising it changes the partition layout and \
makes bundles incompatible with already-deployed devices."
        fi
    done
}

# assert two unit orderings the confirm door depends on; losing either fails
# as a race, not an error:
#   1. rauc-mark-good after fus-update-confirm: the gate's ExecCondition
#      asks about the very state the confirm run settles.
#   2. fus-update-confirm after the container mount unit: finalizing an app
#      rollback needs the mounted image; asked earlier the query answers
#      only "indeterminate" and the rollback stays unfinalized.
# wire as a ROOTFS_POSTPROCESS_COMMAND of any image built for the fsupdater
# door.
fus_selfcheck_confirm_ordering() {
    _unitdir="${IMAGE_ROOTFS}${systemd_system_unitdir}"

    # an After= line may list several units, so match the token, not the line.
    _ordered_after() {
        grep -E '^[[:space:]]*After[[:space:]]*=' "$1" 2>/dev/null | \
            grep -qE "(=|[[:space:]])$2([[:space:]]|\$)"
    }

    if [ -f "$_unitdir/rauc-mark-good.service" ]; then
        _gate="$_unitdir/rauc-mark-good.service.d/10-fw-confirm-gate.conf"
        [ -f "$_gate" ] || bbfatal "fus-selfcheck: $_gate missing -- an fsupdater-door image ships rauc-mark-good only with the firmware confirm gate"
        _ordered_after "$_gate" "fus-update-confirm\.service" || \
            bbfatal "fus-selfcheck: $_gate does not order rauc-mark-good after fus-update-confirm.service. \
Without it the gate can evaluate a state the confirm run is settling in the same boot, and its \
verdict becomes timing-dependent."
    fi

    _confirm="$_unitdir/fus-update-confirm.service"
    _mount="$_unitdir/fus-app-container-mount.service"
    if [ -f "$_mount" ]; then
        [ -f "$_confirm" ] || bbfatal "fus-selfcheck: $_confirm missing on an image shipping the container mount unit"
        _ordered_after "$_confirm" "fus-app-container-mount\.service" || \
            bbfatal "fus-selfcheck: $_confirm does not order the confirm run after fus-app-container-mount.service. \
Asked before the mount, the reboot-state query answers indeterminate, no predicate claims that \
answer, and a pending application rollback is left for the deadline to reboot on."

        # the other half of the same sandwich: the boot guard settles a
        # firmware fallback under a combined update before the mount, so the
        # proven firmware is never paired with the application the failed
        # update brought. ordered the other way round, the mount wins that
        # race and the pairing runs for a whole boot.
        _guard="$_unitdir/fus-app-container-bootguard.service"
        [ -f "$_guard" ] || bbfatal "fus-selfcheck: $_guard missing on an image shipping the container mount unit. \
An After= naming a unit that is not installed is a silent no-op, so the ordering below would \
pass while the mount ran unguarded on every boot."
        _ordered_after "$_mount" "fus-app-container-bootguard\.service" || \
            bbfatal "fus-selfcheck: $_mount does not order the mount after fus-app-container-bootguard.service. \
The guard decides which application slot this boot mounts -- both on trial exhaustion and on a \
firmware fallback under a combined update -- and after the mount that decision comes too late."
    fi
}
