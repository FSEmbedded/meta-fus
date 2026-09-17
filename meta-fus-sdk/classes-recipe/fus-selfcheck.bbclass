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

# Assert that the GENERATED system.conf slot graph matches BOTH mode
# dimensions, so a wrong parent=/bootname or a missing/misplaced app section
# (which would silently break A/B activation or the app delivery) fails the
# build, not a non-booting board. Wire as a rauc-conf do_install[postfuncs].
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

# Assert the hardened D-Bus policy for the stock RAUC bus name is the one that
# actually ships, and that it ships in the read-only location. The upstream
# file allows the default context to send to the bus name, which reaches every
# method including Mark and InstallBundle -- verified as an
# accepted InstallBundle from an unprivileged caller. Two ways to lose that
# hardening silently, both caught here: the replacement does not land (upstream
# text survives), or a copy is also installed under ${sysconfdir}, where the
# writable /etc overlay can freeze a stale version that outlives the image.
# Wire as a rauc do_install[postfuncs].
fus_selfcheck_dbus_policy() {
    pol="${D}${datadir}/dbus-1/system.d/de.pengutronix.rauc.conf"
    [ -f "$pol" ] || bbfatal "fus-selfcheck(dbus-policy): $pol not installed"

    # The default-context block is the whole question: it must refuse, and the
    # upstream file is recognised by it allowing there instead.
    block=$(sed -n '/<policy context="default">/,/<\/policy>/p' "$pol")
    printf '%s\n' "$block" | grep -q 'deny send_destination' || \
        bbfatal "fus-selfcheck(dbus-policy): no deny in the default-context block of $pol \
(the upstream permissive policy was not replaced)"
    printf '%s\n' "$block" | grep -q 'allow send_destination' && \
        bbfatal "fus-selfcheck(dbus-policy): the default-context block of $pol still allows \
send_destination; that reaches every method from any local account"

    # Root must keep both: own alone does not grant method reachability. Scoped
    # to the root block for the same reason the default block is: the file's own
    # comments quote the upstream rules verbatim to explain them, so an
    # unscoped grep matches the explanation and passes while the real rule is
    # gone -- a check that checks nothing.
    rootblock=$(sed -n '/<policy user="root">/,/<\/policy>/p' "$pol")
    printf '%s\n' "$rootblock" | grep -q 'allow own="de.pengutronix.rauc"' || \
        bbfatal "fus-selfcheck(dbus-policy): the root block of $pol does not let root own \
the bus name"
    printf '%s\n' "$rootblock" | grep -q 'allow send_destination="de.pengutronix.rauc"' || \
        bbfatal "fus-selfcheck(dbus-policy): the root block of $pol does not let root send \
to the bus name; the boot-time mark-good and confirm chain would be locked out"

    # A second copy under /etc would be shadowable and would defeat the move.
    [ -e "${D}${sysconfdir}/dbus-1/system.d/de.pengutronix.rauc.conf" ] && \
        bbfatal "fus-selfcheck(dbus-policy): a copy is still installed under \
${sysconfdir}/dbus-1/system.d; /etc is a writable overlay and can freeze it"

    :
}

# Assert that a just-built container-mode app squashfs ships with all 3
# verity-sidecar files, IMAGE-keyed (the full squashfs filename plus a
# suffix, e.g. fus-app-container.squashfs.verity) — matching the naming the
# already-shipped fus-app-container-runtime `mount` verb looks up
# ("$img.verity"/"$img.roothash"/"$img.roothash.p7s" for $img = the renamed
# squashfs path), NOT stem-keyed (fus-app-container.verity, without
# ".squashfs" in the middle). A missing/empty sidecar would otherwise only
# surface at boot, when the `mount` verb refuses to mount an unverifiable
# image and the device silently runs without the app. Argument-taking:
#   fus_selfcheck_container_artifact <deploy-dir> <image-filename>
# (image-filename includes the .squashfs extension, e.g. "fus-app-container-1.0.squashfs")
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

# Assert the app payload tree is complete and self-describing before the rootfs
# that carries it leaves the build. App-agnostic: the binaries, the id and the
# version come from FUS_UPDATE_APP_* / etc, so a "bring your own app" payload is
# held to the same contract as the reference app. Three guards, each catching a
# class that otherwise only surfaces in the field:
#   - every binary in FUS_UPDATE_APP_BINARIES is present and executable (the app
#     would ship without its program);
#   - etc/app_version is non-empty (the app-only update path reports the running
#     app version across a slot switch from it);
#   - etc/app-release is present and its IMAGE_ID matches FUS_UPDATE_APP_ID
#     (promotes the metadata from convention to an enforced identity contract).
# Runs over ${IMAGE_ROOTFS} of whatever rootfs carries the payload: the app
# image in slot/container, the main rootfs in rootfs mode. The install
# prefix follows FUS_UPDATE_APP_MODE (empty for slot/container, the app mount for
# rootfs), so locate files by name rather than a fixed path — a hardcoded
# /etc/... or /opt/fus-app/etc/... would false-fire in the other modes.
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

# Assert at least one app-health probe is installed under the health directory.
# Scoped to the mode where the probe is monitor-only, not boot-gating
# (container): the app's own revert is driven by fus-app-container-runtime's
# boot-attempt counter, not the probe verdict, and committing/rejecting a
# pending update is an external caller's decision (fus-update-confirm). The
# probe is that external caller's only health signal, so with NO probe there
# is nothing to base that decision on. Runs over the SYSTEM rootfs — the
# launcher package ships the probe into the main image, not the app image —
# so it is wired from the image class, not the app-image build.
fus_selfcheck_health_probe() {
    # The premise is an application whose health somebody has to judge. An image
    # that ships no application runtime has no such dimension -- nothing mounts an
    # app, nothing reverts one, and the external caller this probe informs has no
    # decision to make -- so demanding a probe there asks for a signal about
    # nothing. Same shape as the install-door check further down, which skips when
    # the image carries no updater service. An image that DOES carry the runtime
    # and no probe is still the defect this check exists for.
    if [ ! -x "${IMAGE_ROOTFS}${bindir}/fus-app-container-runtime" ]; then
        bbnote "fus-selfcheck: no application runtime in this image -- skipping the app-health probe assertion"
        return
    fi
    if [ -z "$(find "${IMAGE_ROOTFS}${FUS_UPDATE_HEALTH_DIR}" -type f 2>/dev/null | head -n1)" ]; then
        bbfatal "fus-selfcheck: no app-health probe under ${FUS_UPDATE_HEALTH_DIR} \
in ${IMAGE_ROOTFS}. In container mode the probe is the only app-health signal \
an external caller has for its commit/reject decision (fus-update-confirm); \
with no probe there is nothing to decide on. Ship at least one health.d probe \
in the launcher package."
    fi
}

# Assert the staged botan pkg-config contract is botan-2.x. The lib links
# botan-2 (CMake resolves botan-2.pc); meta-oe ships botan 3.x, so this
# recipe's legacy-images PACKAGECONFIG needs its own version-pinning
# bbappend to stage 2.x. Wire as a do_configure prefunc, only when that
# PACKAGECONFIG is enabled -- otherwise botan is not staged at all.
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

# Assert the GENERATED lib config header carries the layer's device paths --
# not the recipe text, the generated artifact. This catches a drift class:
# a recipe change accidentally baking a directory that no longer matches the
# layer's configured FUS_UPDATE_APP_IMG_DIR / FSUP_RAUC_SCRATCH, which would
# silently make the lib read/write the wrong device path at install time. The
# baked FUS_LIB_APP_IMG_STORE value carries no trailing slash: CMake strips it
# from the PATH-typed cache variable, and the consuming code path joins file
# names onto it with a slash-tolerant path join, so the value must equal
# FUS_UPDATE_APP_IMG_DIR exactly (no trailing slash). FUS_LIB_RAUC_SCRATCH must
# live on the persistent data partition or v2 streaming staging lands in tmpfs.
# Wire as a do_configure postfunc of the lib recipe.
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

# Assert the generated lib config header was configured with the legacy
# image formats compiled out, catching a PACKAGECONFIG drift that would
# silently leave botan linked into an image that believes it shipped
# without it. Wire as a do_configure postfunc, only when legacy-images is
# NOT set.
fus_selfcheck_lib_legacy_off() {
    hdr="${FUS_SELFCHECK_LIB_CONFIG_H}"
    [ -f "$hdr" ] || bbfatal "fus-selfcheck: generated lib config header missing: $hdr"
    if ! grep -qxF "#define FUS_LEGACY_IMAGE_SUPPORT 0" "$hdr"; then
        bbfatal "fus-selfcheck: $hdr was not configured with legacy image support off \
(expected '#define FUS_LEGACY_IMAGE_SUPPORT 0'). Got: \
$(grep FUS_LEGACY_IMAGE_SUPPORT "$hdr" || echo 'no such define')"
    fi
}

# Assert the installed library binary carries no botan NEEDED entry, since
# the header check above cannot see a stale build artifact or an
# unrelated link path pulling botan in regardless of the cmake option.
# readelf, not nm: the release build is LTO'd and stripped, so symbols are
# gone but a dynamic NEEDED entry would still show. Wire as a do_install
# postfunc, only when legacy-images is NOT set.
fus_selfcheck_no_botan_needed() {
    so="${D}${libdir}/libfs_updater.so.1"
    [ -f "$so" ] || bbfatal "fus-selfcheck: installed library not found: $so; \
the NEEDED check cannot run"
    if readelf -d "$so" | grep -q 'NEEDED.*libbotan'; then
        bbfatal "fus-selfcheck: $so links libbotan although legacy image support \
is off; check the PACKAGECONFIG wiring in the lib recipe."
    fi
}

# Pin the library's persisted state ABI at the point of consumption.
# These values are not an internal enum: they are written as-is into the
# U-Boot environment, so they outlive the process, the image and the
# generation that wrote them. A device flashed with an older image can be
# read by a newer one and vice versa, and out-of-tree consumers read the
# raw numbers -- the library's own header warns about
# that dependency but nothing enforces it. Renumbering would therefore not
# break a build, it would silently reinterpret the recorded state of
# devices already in the field.
#
# All values are pinned, including the sentinel, because the guarantee that
# matters is the whole numbering, not the subset this layer happens to
# branch on today. The numbers are defined in a DIFFERENT repository: fail
# the CONSUMER's build when a re-pinned SRCREV no longer carries them.
# Wire as a do_configure prefunc of the library recipe -- it reads the
# source header, which exists from do_unpack on.
fus_selfcheck_lib_state_values() {
    hdr="${S}/src/handle_update/updateDefinitions.h"
    [ -f "$hdr" ] || bbfatal "fus-selfcheck: $hdr not found; the persisted state ABI cannot be verified"

    _pin() {
        if ! sed -n "/enum class UBootBootstateFlags /,/}/p" "$hdr" | \
                grep -Eq "$1[[:space:]]*=[[:space:]]*$2(,|[[:space:]]|$)"; then
            bbfatal "fus-selfcheck: persisted state ABI drift: UBootBootstateFlags::$1 != $2 \
in $hdr. This value is stored in the U-Boot environment, so changing it reinterprets the \
recorded state of devices already flashed; re-pin only after confirming the new numbering \
against every reader, including out-of-tree consumers."
        fi
    }

    _pin NO_UPDATE_REBOOT_PENDING        0
    _pin FW_UPDATE_REBOOT_FAILED         1
    _pin INCOMPLETE_FW_UPDATE            2
    _pin INCOMPLETE_APP_UPDATE           3
    _pin INCOMPLETE_APP_FW_UPDATE        4
    _pin FAILED_FW_UPDATE                5
    _pin FAILED_APP_UPDATE               6
    _pin ROLLBACK_FW_REBOOT_PENDING      7
    _pin ROLLBACK_APP_REBOOT_PENDING     8
    _pin ROLLBACK_APP_FW_REBOOT_PENDING  9
    _pin INCOMPLETE_FW_ROLLBACK          10
    _pin INCOMPLETE_APP_ROLLBACK         11
    _pin INCOMPLETE_APP_FW_ROLLBACK      12
    # Sentinel: never written as a state, but a reader that maps an unknown
    # value onto it must agree with the writer on where the valid range ends.
    _pin UNKNOWN_STATE                   13
}

# Hold every state value to a declared flow status, at the point of consumption.
# fus_selfcheck_lib_state_values() above pins the NUMBERS; this pins whether a
# defined flow still writes each of them. The two facts have different owners:
# the library declares a `flow:` marker per enumerator, and this function counts
# the writers in its sources. A value declared live that nothing writes, or a
# value declared reserved that something writes, fails the build -- so the
# question "does this state belong to a flow?" is answered while the build is
# green instead of at the next audit.
#
# Why the consumer asks: the values no flow writes are not spare numbers. Readers
# outside that repository branch on the raw numbers, and this layer's confirm
# chain keeps a predicate for each rollback family. A flow quietly returning or
# disappearing changes which of those predicates can ever fire, and nothing in
# the component's own build would say so.
#
# to_string() is the only path from an enumerator into the U-Boot environment,
# so counting its call sites counts the writers -- but only while that stays
# true. The guard below fails if any write of the variable bypasses it, because
# a bypass would make every count read zero and the gate would pass by seeing
# nothing. Wire as a do_configure prefunc of the library recipe.
fus_selfcheck_state_flows() {
    hdr="${S}/src/handle_update/updateDefinitions.h"
    [ -f "$hdr" ] || bbfatal "fus-selfcheck: $hdr not found; the state flow status cannot be verified"

    # Non-vacuity: every persist of the variable must go through to_string(),
    # otherwise the writer counts below are blind. The argument is regularly
    # wrapped onto the next line, so the test is a three-line window, not the
    # matching line alone -- a line-only test reports every wrapped call.
    bypass=$(grep -rl 'addVariable("update_reboot_state"' "${S}/src" | while read -r _f; do
        awk -v F="$_f" '
            { l[NR] = $0 }
            END {
                for (i = 1; i <= NR; i++) {
                    if (l[i] ~ /addVariable\("update_reboot_state"/) {
                        w = l[i] " " l[i+1] " " l[i+2]
                        if (w !~ /to_string/) printf "%s:%d\n", F, i
                    }
                }
            }' "$_f"
    done)
    if [ -n "$bypass" ]; then
        bbfatal "fus-selfcheck: a write of update_reboot_state bypasses to_string(), so \
counting to_string() call sites no longer counts the writers and this check would pass \
by seeing nothing. Offending site(s): $bypass"
    fi

    # to_string() and its argument are regularly split across lines, so the file
    # is joined before matching. A line-based count reports zero for a value that
    # IS written, and a zero then agrees with a wrong 'reserved' declaration --
    # two errors cancelling into a green check.
    #
    # to_string(flag ? X : Y) writes both arms and is split into one call each.
    # A condition that is not a plain identifier stays unsplit and counts as
    # zero writers, which fails a live value instead of passing it.
    _match_writes() {
        find "${S}/src" \( -name '*.cpp' -o -name '*.h' \) -print | while read -r _f; do
            tr '\n' ' ' < "$_f" | \
                sed -E 's/to_string\( *[A-Za-z0-9_]+ *\? *((update_definitions::)?UBootBootstateFlags::[A-Za-z0-9_]+) *: *((update_definitions::)?UBootBootstateFlags::[A-Za-z0-9_]+) *\)/to_string(\1) to_string(\3)/g' | \
                grep -oE "to_string\( *(update_definitions::)?UBootBootstateFlags::$1"
        done
    }

    _count_writers() {
        _match_writes "$1([^A-Za-z0-9_]|$)" | grep -c . || true
    }

    _sum=0

    _flow() {
        _name="$1"
        _want="$2"

        _decl=$(sed -n "/enum class UBootBootstateFlags /,/};/p" "$hdr" | \
                sed -n "s/.*\<$_name\> *= *[0-9]\+,\? *\/\* flow: \([a-z-]\+\) \*\/.*/\1/p")
        if [ -z "$_decl" ]; then
            bbfatal "fus-selfcheck: UBootBootstateFlags::$_name carries no 'flow:' marker in \
$hdr. Every value must declare whether a flow still writes it."
        fi
        if [ "$_decl" != "$_want" ]; then
            bbfatal "fus-selfcheck: state flow drift: UBootBootstateFlags::$_name is declared \
'$_decl' but this layer expects '$_want'. A status change is a statement about which \
confirm-chain predicates can still fire; re-pin here only together with that review."
        fi

        _writers=$(_count_writers "$_name")
        _sum=$(expr "$_sum" + "$_writers")

        case "$_want" in
        live)
            if [ "$_writers" -eq 0 ]; then
                bbfatal "fus-selfcheck: UBootBootstateFlags::$_name is declared live but no \
flow writes it. Either a flow was removed -- then declare it reserved or legacy-inbound and \
review the predicates keyed on its exit codes -- or the write moved and this count is wrong."
            fi
            ;;
        reserved | legacy-inbound | sentinel)
            if [ "$_writers" -ne 0 ]; then
                bbfatal "fus-selfcheck: UBootBootstateFlags::$_name is declared '$_want' but \
$_writers flow(s) write it. A state that is written again must be declared live, and the \
confirm-chain predicates keyed on its exit codes must be re-read before that lands."
            fi
            ;;
        *)
            bbfatal "fus-selfcheck: unknown flow status '$_want' for UBootBootstateFlags::$_name"
            ;;
        esac
    }

    _flow NO_UPDATE_REBOOT_PENDING        live
    # Superseded flow: an older generation wrote it, so a device can still carry
    # it and the library migrates it. Nothing writes it now.
    _flow FW_UPDATE_REBOOT_FAILED         legacy-inbound
    _flow INCOMPLETE_FW_UPDATE            live
    _flow INCOMPLETE_APP_UPDATE           live
    _flow INCOMPLETE_APP_FW_UPDATE        live
    _flow FAILED_FW_UPDATE                live
    _flow FAILED_APP_UPDATE               live
    _flow ROLLBACK_FW_REBOOT_PENDING      live
    _flow ROLLBACK_APP_REBOOT_PENDING     live
    _flow ROLLBACK_APP_FW_REBOOT_PENDING  live
    # Superseded flow: the commit path wrote these three before the reboot until
    # that write was removed, and apply deliberately does not promote into them,
    # so a device flashed by that generation can carry one but nothing writes them
    # again. No confirm-chain predicate loses its reach by that: each rollback
    # family's two codes are also produced by the live rollback state of the same
    # dimension, so all six stay reachable.
    _flow INCOMPLETE_FW_ROLLBACK          legacy-inbound
    _flow INCOMPLETE_APP_ROLLBACK         legacy-inbound
    _flow INCOMPLETE_APP_FW_ROLLBACK      legacy-inbound
    _flow UNKNOWN_STATE                   sentinel

    # Non-vacuity for the counter itself. Every per-value count above used a
    # pattern naming one enumerator; this counts every to_string() call on the
    # enumeration whatever it names. A shortfall means the counter is narrower
    # than its subject -- some call site matches the broad form and no specific
    # one -- and then every count above is too low and this whole check reads
    # clean by seeing less than there is.
    _total=$(_match_writes "[A-Za-z0-9_]+" | grep -c . || true)
    if [ "$_sum" != "$_total" ]; then
        bbfatal "fus-selfcheck: the writer counter is blind: the per-value counts add up to \
$_sum but there are $_total to_string() calls on UBootBootstateFlags. Some call site is not \
matched by any per-value pattern, so the flow statuses above were checked against numbers \
that are too low. Fix the matcher before trusting this check."
    fi
}

# Pin the fs-updater CLI's process-exit ABI at the point of consumption.
# Two meta-fus components branch on these exact numbers across a process
# boundary: the hawkBit bridge backend (install verdict: 0/4/8/48 success,
# 47 watchdog, everything else failure) and the shared pending-state
# predicates behind the confirm door and the container bootguard, which
# key on the reboot-state family, the rollback-reboot family, and the
# success codes of the commit, rollback and state-set verbs -- every
# number those predicates compare against is pinned here, because the
# predicates are the only thing standing between a renumbered enum and a
# device that finalizes the wrong state. The numbers
# are defined in a DIFFERENT repository; its own test suite pins the
# untyped-install->48 classifier mapping but not every numeric value. Fail
# the CONSUMER's build loudly when a re-pinned SRCREV no longer carries
# the expected numbers, instead of letting a renumbered enum invert
# install verdicts in the field. Wire as a do_configure postfunc of the
# CLI recipe.
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
    # Accepted at boot as "pending, mount state unanswerable".
    _pin UPDATER_UPDATE_REBOOT_STATE UPDATE_REBOOT_STATE_INDETERMINATE 55
    # Deliberately NOT accepted there, and compared against by name since the
    # confirm run learned to settle it: pending-state.sh carries it as
    # APP_ROLLBACK_INDETERMINATE_CODE and the confirm branches on it. What the
    # boot guard needs is that it stays DISTINCT from the accepted set --
    # renumbered onto one of those, a pending rollback would start spending
    # application boot attempts on a state that refuses them, and the deadline's
    # deliberate exclusion of it would stop applying with it.
    _pin UPDATER_UPDATE_REBOOT_STATE ROLLBACK_APP_REBOOT_INDETERMINATE 57
    # Not a state: what the client answers when it died on an exception instead
    # of reporting one. The boot guard branches on this exact number to leave
    # the application trial counter alone when it was told nothing, so it is
    # held like the codes above rather than left to be discovered in the field.
    _pin UPDATER_FATAL UNHANDLED_EXCEPTION 124
    # Success codes of the verbs the predicates drive. None of these is 0 --
    # the CLI never returns 0 for them -- so a wrong number here reads as
    # failure and silently strands the state it was meant to settle.
    _pin UPDATER_UPDATE_ROLLBACK_STATE UPDATE_ROLLBACK_SUCCESSFUL 12
    _pin UPDATER_COMMIT_STATE          UPDATE_COMMIT_SUCCESSFUL   16
    _pin UPDATER_COMMIT_STATE          UPDATE_NOT_NEEDED          17
    _pin UPDATER_SETGET_UPDATE_STATE   GETSET_STATE_SUCCESSFUL    52
    # A commit that settled an install whose target was never activated. What
    # the predicates need is that it stays OUTSIDE their success set: numbered
    # into 16/17 it would report a discarded update as a confirmed one, and the
    # device would be recorded as running firmware it never booted.
    _pin UPDATER_COMMIT_STATE          STALLED_INSTALL_SETTLED    58
    # A commit that consumed a durable state no current flow writes -- a device
    # that arrived carrying it from a superseded firmware, or from an edited
    # environment. Unlike 58 nothing was discarded, so the boot-time confirm
    # counts it as settled; what it must not become is 16 or 17, because then a
    # fleet could no longer see that one of its devices came in from an older
    # generation.
    _pin UPDATER_COMMIT_STATE          LEGACY_STATE_MIGRATED      59
}

# Cross-unit /tmp visibility gate for the hawkBit -> fs-updater handoff:
# the bridge downloads the bundle to a /tmp path and hands the PATH
# STRING to the updater service over D-Bus -- only works while BOTH units
# see the same /tmp. A later hardening pass adding PrivateTmp= to either
# unit would break the handoff silently: the download "succeeds", the
# install never finds the file. Also asserts the updater's data-mount
# ordering drop-in survived image assembly. Wire as a
# ROOTFS_POSTPROCESS_COMMAND of the image shipping both units.
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
    # The data-mount ordering drop-in is fs-updater-specific; only images that
    # ship fs-updater.service need it. A container-mode image without the updater
    # service has nothing to order, so skip rather than fail spuriously.
    if [ -f "$_unitdir/fs-updater.service" ]; then
        _dropin="$_unitdir/fs-updater.service.d/10-fus-data-mount.conf"
        [ -f "$_dropin" ] || bbfatal "fus-selfcheck: $_dropin missing -- fs-updater.service must order after the persistent data mount"
        grep -q '^RequiresMountsFor=' "$_dropin" || bbfatal "fus-selfcheck: $_dropin carries no RequiresMountsFor="
    fi
}

# Assert the deployed rootfs squashfs still fits the A/B slot it is written to.
# wic already refuses an oversized partition, but the bundle-only build path
# strips every wic fstype, so a bundle can be produced with no size check at all
# -- and that one only fails on the device, mid-install. Check the artifact the
# bundle actually carries instead. Wire as a do_image_squashfs postfunc.
# Arithmetic via expr, not $(( )): bitbake's shell parser does not implement
# arithmetic expansion and fails the whole recipe at parse time on it.
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

# Assert the two boot orderings the confirm door rests on survived image
# assembly. Both are a single line in a unit file, and losing either one fails
# as a race rather than as an error: the units still start, the answer just
# stops being a function of the device's state.
#
#   1. The mark-good gate must run after the confirm run. Confirm settles the
#      very state the ExecCondition asks about, and both units are pulled into
#      the same boot transaction, so unordered the gate's verdict depends on
#      which unit wins. Nothing transitive substitutes: the health-check chain
#      that would otherwise separate them is monitor-only in container mode.
#   2. Where the container mount unit is shipped, confirm must run after it.
#      Finalizing an application rollback needs the mounted image as evidence
#      that the revert boot happened; asked earlier the query only answers
#      "indeterminate", which no predicate claims, so the rollback would be
#      left unfinalized and the deadline would reboot instead.
#
# Wire as a ROOTFS_POSTPROCESS_COMMAND of any image built for the fsupdater
# door -- this is a door property, not an app-mode one.
fus_selfcheck_confirm_ordering() {
    _unitdir="${IMAGE_ROOTFS}${systemd_system_unitdir}"

    # An After= line may list several units, so match the token, not the line.
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

        # The other half of the same sandwich. The boot guard settles a
        # firmware fallback under a combined update before the mount, so that
        # the proven firmware is never paired with the application the failed
        # update brought. Ordered the other way round, the mount wins that race
        # and the pairing runs for a whole boot.
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


# Assert that the removable-medium door's unit stays in the host mount
# namespace and keeps its start rate limit off. Wire as a do_install[postfuncs]
# in fus-usb-update.
#
# The wrapper stages the bundle under /tmp and hands the installer a PATH, not
# a descriptor; the installer is a different process. A unit with its own
# mount namespace therefore hands over a path that resolves to nothing there,
# and the medium's own mount from ExecStartPre is invisible to the wrapper as
# well -- the defect the predecessor layer's unit carries.
#
# The rate limit is measured, not assumed: consecutive FAILED starts count, and
# a refusal exits non-zero, so two refused media inside the window make the
# third insertion -- a correct medium -- produce no run and no record at all.
fus_selfcheck_usb_door_unit() {
    _unit="${D}${systemd_system_unitdir}/fus-usb-update.service"
    [ -f "$_unit" ] || bbfatal "fus-selfcheck(usb-door): $_unit not installed"

    if grep -Eq '^(PrivateTmp|PrivateMounts|ProtectHome|MountAPIVFS)=(yes|true|1|on|read-only|tmpfs)' "$_unit"; then
        bbfatal "fus-selfcheck(usb-door): $_unit asks for a private mount namespace. \
The staged bundle path is handed to the installer, a different process, and would not resolve \
there; the medium's mount would be invisible too."
    fi
    if grep -Eq '^Root(Directory|Image)=' "$_unit"; then
        bbfatal "fus-selfcheck(usb-door): $_unit reroots the unit; same defect as a private \
mount namespace -- the path handed to the installer does not resolve in the installer's view."
    fi
    grep -q '^StartLimitIntervalSec=0' "$_unit" || \
        bbfatal "fus-selfcheck(usb-door): $_unit does not set StartLimitIntervalSec=0. \
A refusal exits non-zero, so a rate limit lets two refused media suppress the run for a third, \
correct one -- with no journal line under the tag and no record entry."
}
