#!/bin/sh
# fus-fw-env.test.sh -- the U-Boot environment location shipped to userspace.
#
# Three parts, each a hardening test for one way this goes wrong on a board:
#   1. the build-time renderer: one line per copy, the right device names,
#      and a refusal of every combination the bootloader cannot produce;
#   2. the boot-time setup script against a fake /dev, /sys and /proc: eMMC
#      boot0/boot1, NAND by partition name, a stale regular file in the
#      persistent /etc overlay, and SD/user-area boot, which must be refused;
#   3. fus_selfcheck_fw_env against a fake bootloader tree: a table that
#      drifts from the defconfig or from the nboot-info must fail the build.
#
# The i.MX environment access itself is not measurable here; that stays a
# bench test (fw_printenv / fw_setenv round trip, both copies).
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${DIR}/fus-test-lib.sh"
fus_test_init
fail=0

BSP="${DIR}/../meta-fus-bsp"
FILES="${BSP}/recipes-bsp/u-boot/files"
RENDER="${FILES}/fus-fw-env-render"
SETUP="${FILES}/fus-uboot-env-setup"
CLASS="${DIR}/../meta-fus-sdk/classes-recipe/fus-selfcheck.bbclass"
for f in "${RENDER}" "${SETUP}" "${CLASS}"; do
    [ -f "${f}" ] || skip "layer file missing: ${f}"
done

TAB=$(printf '\t')

# --- 1. renderer -----------------------------------------------------------

render() {
    sh "${RENDER}" "$@" 2> /dev/null
}

out=$(render emmc-boot 0x4000 0x200 '' 0x40000 0x40000)
check "renderer: equal offsets on emmc-boot give boot0 and boot1" \
    "@@BLK@@boot0${TAB}0x40000${TAB}0x4000${TAB}0x200
@@BLK@@boot1${TAB}0x40000${TAB}0x4000${TAB}0x200" "${out}"

out=$(render emmc-boot 0x2000 0x200 '' 0x200000)
check "renderer: a single copy is one boot0 line" \
    "@@BLK@@boot0${TAB}0x200000${TAB}0x2000${TAB}0x200" "${out}"

out=$(render nand 0x4000 0x20000 2 0x0 0x40000)
check "renderer: nand gives the five-column form per copy" \
    "@@MTD@@${TAB}0x0${TAB}0x4000${TAB}0x20000${TAB}2
@@MTD@@${TAB}0x40000${TAB}0x4000${TAB}0x20000${TAB}2" "${out}"

rc_is "renderer: two different offsets on emmc-boot are refused" 1 \
    sh "${RENDER}" emmc-boot 0x4000 0x200 '' 0x40000 0x44000
rc_is "renderer: three offsets are refused" 1 \
    sh "${RENDER}" emmc-boot 0x4000 0x200 '' 0x0 0x0 0x0
rc_is "renderer: an offset that is not hex is refused" 1 \
    sh "${RENDER}" emmc-boot 0x4000 0x200 '' 262144
rc_is "renderer: a hex number with trailing junk is refused" 1 \
    sh "${RENDER}" emmc-boot 0x4000 0x200 '' 0x40g00
rc_is "renderer: an unknown medium is refused" 1 \
    sh "${RENDER}" spi 0x4000 0x200 '' 0x0
rc_is "renderer: nand without a block count is refused" 1 \
    sh "${RENDER}" nand 0x4000 0x20000 '' 0x0
rc_is "renderer: no offset at all is refused" 1 \
    sh "${RENDER}" emmc-boot 0x4000 0x200 ''

# --- 2. setup script -------------------------------------------------------

# Copy of the script whose absolute paths point into the fake root.
make_setup() { # make_setup <root> <medium>
    _r=$1
    mkdir -p "${_r}/bin" "${_r}/dev" "${_r}/sys/block" "${_r}/run" "${_r}/etc" \
        "${_r}/lib/fus-update"
    sed \
        -e "s|@@LIBDIR@@|${_r}/lib|" \
        -e "s|@@MEDIUM@@|$2|" \
        -e "s|@@MTD_NAME@@|UBootEnv|" \
        -e "s|'/run/fus-update/fw_env.config'|'${_r}/run/fw_env.config'|" \
        -e "s|'/etc/fw_env.config'|'${_r}/etc/fw_env.config'|" \
        -e "s|'/proc/mtd'|'${_r}/proc_mtd'|" \
        -e "s|'/dev'|'${_r}/dev'|" \
        -e "s|'/sys/block'|'${_r}/sys/block'|" \
        -e "s|'/sys/bdinfo/boot_dev'|'${_r}/sys/bdinfo/boot_dev'|" \
        "${SETUP}" > "${_r}/setup"
    printf '#!/bin/sh\nexit 0\n' > "${_r}/bin/fw_printenv"
    chmod +x "${_r}/bin/fw_printenv"
    stub_partconf "${_r}" 48
}

stub_partconf() { # stub_partconf <root> <PARTITION_CONFIG in hex, no 0x>
    printf '#!/bin/sh\necho "Boot configuration bytes [PARTITION_CONFIG: 0x%s]"\n' "$2" \
        > "$1/bin/mmc"
    chmod +x "$1/bin/mmc"
}

stub_findmnt() { # stub_findmnt <root> <source>
    printf '#!/bin/sh\nprintf "%%s\\n" "%s"\n' "$2" > "$1/bin/findmnt"
    chmod +x "$1/bin/findmnt"
}

stub_bdinfo() { # stub_bdinfo <root> <boot_dev value, e.g. MMC3>
    mkdir -p "$1/sys/bdinfo"
    printf '%s\n' "$2" > "$1/sys/bdinfo/boot_dev"
}

# shellcheck disable=SC2317 # called through rc_is
run_setup() { # run_setup <root>
    PATH="$1/bin:${PATH}" sh "$1/setup" > "$1/out" 2>&1
}

emmc_template() { # emmc_template <root> <offsets...>
    _r=$1
    shift
    sh "${RENDER}" emmc-boot 0x4000 0x200 '' "$@" > "${_r}/lib/fus-update/fw_env.config.in"
}

R=${TMP}/emmc
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk2boot0"
: > "${R}/dev/mmcblk2boot1"
mkdir -p "${R}/sys/block/mmcblk2boot0" "${R}/sys/block/mmcblk2boot1"
printf '1\n' > "${R}/sys/block/mmcblk2boot0/force_ro"
printf '1\n' > "${R}/sys/block/mmcblk2boot1/force_ro"
stub_findmnt "${R}" /dev/mmcblk2p1
rc_is "setup emmc: succeeds on a board booting from eMMC" 0 run_setup "${R}"
has "setup emmc: copy A on boot0" "${R}/dev/mmcblk2boot0${TAB}0x40000" "${R}/run/fw_env.config"
has "setup emmc: copy B on boot1" "${R}/dev/mmcblk2boot1${TAB}0x40000" "${R}/run/fw_env.config"
lacks "setup emmc: no placeholder is left" "@@" "${R}/run/fw_env.config"
check "setup emmc: /etc/fw_env.config links the rendered file" \
    "${R}/run/fw_env.config" "$(readlink "${R}/etc/fw_env.config")"
check "setup emmc: boot0 is made writable" "0" "$(cat "${R}/sys/block/mmcblk2boot0/force_ro")"
check "setup emmc: boot1 is made writable" "0" "$(cat "${R}/sys/block/mmcblk2boot1/force_ro")"
rc_is "setup emmc: a second run is a no-op that still succeeds" 0 run_setup "${R}"

# A regular file from an older image sits in the persistent overlay.
rm -f "${R}/etc/fw_env.config"
printf 'stale\n' > "${R}/etc/fw_env.config"
rc_is "setup emmc: a stale regular file is replaced" 0 run_setup "${R}"
check "setup emmc: the stale file became the link" \
    "${R}/run/fw_env.config" "$(readlink "${R}/etc/fw_env.config")"

# The rootfs sits on a device mapper node: fall back to the eMMC with boot0.
stub_findmnt "${R}" /dev/mapper/rootfs
mkdir -p "${R}/sys/block/mmcblk2boot0"
rc_is "setup emmc: the eMMC is found without a mmcblk rootfs" 0 run_setup "${R}"

# The eMMC is there, but which hardware partition boots decides where the environment is.
R=${TMP}/partconf
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk1boot0"
mkdir -p "${R}/sys/block/mmcblk1boot0"
stub_findmnt "${R}" /dev/mmcblk1p1
stub_partconf "${R}" 10
rc_is "setup emmc: boot partition 2 enabled is accepted" 0 run_setup "${R}"
has "setup emmc: the eMMC is found at another index" "${R}/dev/mmcblk1boot0" \
    "${R}/run/fw_env.config"
rm -f "${R}/run/fw_env.config"
stub_partconf "${R}" 00
rc_is "setup emmc: no boot partition enabled is refused" 1 run_setup "${R}"
has "setup emmc: the refusal names the user area" "user area" "${R}/out"
stub_partconf "${R}" 38
rc_is "setup emmc: user-area boot (7) is refused" 1 run_setup "${R}"
check "setup emmc: nothing is rendered for a user-area boot" "no" \
    "$([ -e "${R}/run/fw_env.config" ] && echo yes || echo no)"
rm -f "${R}/bin/mmc"
rc_is "setup emmc: an unreadable PARTITION_CONFIG is refused" 1 run_setup "${R}"
has "setup emmc: the unreadable case is named" "cannot read PARTITION_CONFIG" "${R}/out"

# The rootfs sits on a device mapper node (/dev/root or dm): only the eMMC decides.
R=${TMP}/devroot
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0"
stub_findmnt "${R}" /dev/root
rc_is "setup emmc: /dev/root as source falls back to the eMMC" 0 run_setup "${R}"
has "setup emmc: the fallback renders the eMMC found" "${R}/dev/mmcblk0boot0" \
    "${R}/run/fw_env.config"

# bdinfo refines the scan fallback: two real eMMC candidates, only bdinfo tells them apart.
R=${TMP}/bdinfo
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
: > "${R}/dev/mmcblk2boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0" "${R}/sys/block/mmcblk2boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
stub_bdinfo "${R}" MMC3
rc_is "setup emmc: bdinfo disambiguates two fitted eMMCs" 0 run_setup "${R}"
has "setup emmc: bdinfo's mmcblk2 is used" "${R}/dev/mmcblk2boot0" "${R}/run/fw_env.config"
lacks "setup emmc: not the first-found mmcblk0" "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"

# bdinfo MMC2 maps to mmcblk1: with all three candidates fitted, the scan would
# pick mmcblk0 first, so an mmcblk1 result proves bdinfo is actually taken.
R=${TMP}/bdinfo-mmc2
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
: > "${R}/dev/mmcblk1boot0"
: > "${R}/dev/mmcblk2boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0" "${R}/sys/block/mmcblk1boot0" "${R}/sys/block/mmcblk2boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
stub_bdinfo "${R}" MMC2
rc_is "setup emmc: bdinfo MMC2 maps to mmcblk1" 0 run_setup "${R}"
has "setup emmc: bdinfo's mmcblk1 is used" "${R}/dev/mmcblk1boot0" "${R}/run/fw_env.config"
lacks "setup emmc: not the scan's first mmcblk0" "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"
lacks "setup emmc: not mmcblk2" "${R}/dev/mmcblk2boot0" "${R}/run/fw_env.config"

# bdinfo MMC1 maps to mmcblk0. Alone this cannot tell a real bdinfo hit apart
# from falling through to the scan (both land on mmcblk0); the MMC2 case
# above is what proves the bdinfo path is actually taken.
R=${TMP}/bdinfo-mmc1
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
: > "${R}/dev/mmcblk1boot0"
: > "${R}/dev/mmcblk2boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0" "${R}/sys/block/mmcblk1boot0" "${R}/sys/block/mmcblk2boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
stub_bdinfo "${R}" MMC1
rc_is "setup emmc: bdinfo MMC1 maps to mmcblk0" 0 run_setup "${R}"
has "setup emmc: bdinfo's mmcblk0 is used" "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"
lacks "setup emmc: not mmcblk1" "${R}/dev/mmcblk1boot0" "${R}/run/fw_env.config"
lacks "setup emmc: not mmcblk2" "${R}/dev/mmcblk2boot0" "${R}/run/fw_env.config"

# bdinfo names a controller that is not actually there: fall back to the scan, do not abort.
R=${TMP}/bdinfo-missing
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
stub_bdinfo "${R}" MMC3
rc_is "setup emmc: bdinfo names a missing device, scan still finds one" 0 run_setup "${R}"
has "setup emmc: the scan result is used, not the missing bdinfo guess" \
    "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"

# No bdinfo at all (older bootloader, or a board where it is never set): unchanged behavior.
R=${TMP}/bdinfo-absent
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
rc_is "setup emmc: no bdinfo present falls back to the scan as before" 0 run_setup "${R}"
has "setup emmc: the scan result is used" "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"

# bdinfo names a non-eMMC boot device on an emmc-boot-medium board: not decodable, fall back.
R=${TMP}/bdinfo-undecodable
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk0boot0"
mkdir -p "${R}/sys/block/mmcblk0boot0"
stub_findmnt "${R}" /dev/mapper/rootfs
stub_bdinfo "${R}" NAND
rc_is "setup emmc: bdinfo NAND on an emmc-boot board falls back to the scan" 0 run_setup "${R}"
has "setup emmc: the scan result is used, bdinfo's NAND is ignored" \
    "${R}/dev/mmcblk0boot0" "${R}/run/fw_env.config"

R=${TMP}/sd
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
stub_findmnt "${R}" /dev/mmcblk1p2
rc_is "setup emmc: SD or user-area boot is refused" 1 run_setup "${R}"
has "setup emmc: the refusal names the reason" "SD card" "${R}/out"
check "setup emmc: no config is rendered for the wrong device" "no" \
    "$([ -e "${R}/run/fw_env.config" ] && echo yes || echo no)"

# An SD card as rootfs while an eMMC with boot partitions is fitted: the eMMC is not guessed.
R=${TMP}/sdemmc
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk2boot0"
mkdir -p "${R}/sys/block/mmcblk2boot0"
stub_findmnt "${R}" /dev/mmcblk1p2
rc_is "setup emmc: SD rootfs is refused although an eMMC is fitted" 1 run_setup "${R}"
check "setup emmc: nothing is rendered for the fitted eMMC" "no" \
    "$([ -e "${R}/run/fw_env.config" ] && echo yes || echo no)"

R=${TMP}/noread
make_setup "${R}" emmc-boot
emmc_template "${R}" 0x40000 0x40000
: > "${R}/dev/mmcblk2boot0"
mkdir -p "${R}/sys/block/mmcblk2boot0"
stub_findmnt "${R}" /dev/mmcblk2p1
printf '#!/bin/sh\nexit 1\n' > "${R}/bin/fw_printenv"
rc_is "setup emmc: an environment that does not read back only warns" 0 run_setup "${R}"
has "setup emmc: the read-back failure is named" "does not read back" "${R}/out"
has "setup emmc: the location is still rendered" "mmcblk2boot0" "${R}/run/fw_env.config"

R=${TMP}/nand
make_setup "${R}" nand
sh "${RENDER}" nand 0x4000 0x20000 2 0x0 > "${R}/lib/fus-update/fw_env.config.in"
printf '%s\n' 'dev:    size   erasesize  name' 'mtd0: 00100000 00020000 "SPL"' \
    'mtd4: 00040000 00020000 "UBootEnv"' > "${R}/proc_mtd"
rc_is "setup nand: the partition is found by name" 0 run_setup "${R}"
has "setup nand: the node of that partition is used" \
    "${R}/dev/mtd4${TAB}0x0${TAB}0x4000${TAB}0x20000${TAB}2" "${R}/run/fw_env.config"
printf 'dev:    size   erasesize  name\nmtd0: 00100000 00020000 "SPL"\n' > "${R}/proc_mtd"
rc_is "setup nand: a missing partition fails" 1 run_setup "${R}"

# --- 3. build-time check ---------------------------------------------------

# fus_selfcheck_fw_env and its helpers with the bitbake variables filled in, run under set -e
# with bbfatal as a failing stub, exactly as a task function would see it.
fn=$(awk '/^fus_selfcheck_(fw_env|fw_env_one|configs)\(\) \{/ {f=1} f {print} f && /^}/ {f=0}' "${CLASS}")
[ -n "${fn}" ] || {
    echo "FAIL fus_selfcheck_fw_env is not in the class"
    exit 1
}

# shellcheck disable=SC2317 # called through rc_is
selfcheck() { # selfcheck <machine> <medium> <offsets> <size> <sect> <nsect> <build> <src>
    _body=$(printf '%s\n' "${fn}" | sed \
        -e "s|\${B}|$7|g" -e "s|\${S}|$8|g" -e "s|\${MACHINE}|$1|g" \
        -e "s|\${FUS_ENV_MEDIUM}|$2|g" -e "s|\${FUS_ENV_OFFSETS}|$3|g" \
        -e "s|\${FUS_ENV_SIZE}|$4|g" -e "s|\${FUS_ENV_SECT}|$5|g" \
        -e "s|\${FUS_ENV_NSECT}|$6|g" \
        -e "s|\${FUS_SELFCHECK_ENV_NBOOT}|fsimx8mm fsimx8mn fsimx8mp fsimx8ulp fsimx91 fsimx93|g")
    # Into a file, not /dev/null: a raw abort and a bbfatal both exit 1 under
    # sh -ec, so telling them apart needs the actual message (see `has` below).
    sh -ec "bbfatal() { echo \"\$*\" >&2; exit 1; }; bbnote() { :; }; ${_body}; fus_selfcheck_fw_env" \
        > "$(dirname "$7")/selfcheck.out" 2>&1
}

mk_tree() { # mk_tree <dir> <redundant:y|n> <env-size> [extra .config lines]
    mkdir -p "$1/build/x" "$1/src/board/F+S/fsimx8mp/nboot"
    {
        printf 'CONFIG_ENV_SIZE=%s\n' "$3"
        if [ "$2" = y ]; then printf 'CONFIG_SYS_REDUNDAND_ENVIRONMENT=y\n'; fi
        if [ -n "${4:-}" ]; then printf '%s\n' "$4"; fi
    } > "$1/build/x/.config"
    cat > "$1/src/board/F+S/fsimx8mp/nboot/nboot-info.dtsi" << 'EOF'
    emmc-boot {
        env-start = <0x00040000>;
        env-size = <0x00004000>;
    };
    sd-user {
        env-start = <0x00440000 0x00444000>;
        env-size = <0x00004000>;
    };
EOF
}

T=${TMP}/sc1
mk_tree "${T}" y 0x4000
rc_is "selfcheck: the fsimx8mp table matches the bootloader" 0 \
    selfcheck fsimx8mp emmc-boot "0x40000 0x40000" 0x4000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: a wrong size fails" 1 \
    selfcheck fsimx8mp emmc-boot "0x40000 0x40000" 0x8000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: the sd-user offset is not taken for the eMMC boot" 1 \
    selfcheck fsimx8mp emmc-boot "0x440000 0x444000" 0x4000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: a wrong offset fails" 1 \
    selfcheck fsimx8mp emmc-boot "0x0 0x0" 0x4000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: a single copy against a redundant bootloader fails" 1 \
    selfcheck fsimx8mp emmc-boot "0x40000" 0x4000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: a missing nboot-info fails instead of passing blind" 1 \
    selfcheck fsimx8mp emmc-boot "0x40000 0x40000" 0x4000 0x200 '' "${T}/build" "${T}/none"

# An emmc-boot node without env-start must not borrow the value of the node after it.
T=${TMP}/sc1b
mk_tree "${T}" y 0x4000
cat > "${T}/src/board/F+S/fsimx8mp/nboot/nboot-info.dtsi" << 'EOF'
    emmc-boot {
        env-size = <0x00004000>;
    };
    sd-user {
        env-start = <0x00040000 0x00044000>;
    };
EOF
rc_is "selfcheck: a missing emmc-boot env-start does not read the next node" 1 \
    selfcheck fsimx8mp emmc-boot "0x40000 0x40000" 0x4000 0x200 '' "${T}/build" "${T}/src"

T=${TMP}/sc2
mk_tree "${T}" n 0x2000 'CONFIG_ENV_OFFSET=0x200000'
rc_is "selfcheck: a defconfig board matches its ENV_OFFSET" 0 \
    selfcheck fsimx8x emmc-boot "0x200000" 0x2000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: two copies against a single-copy bootloader fail" 1 \
    selfcheck fsimx8x emmc-boot "0x200000 0x200000" 0x2000 0x200 '' "${T}/build" "${T}/src"
rc_is "selfcheck: a defconfig board with a wrong offset fails" 1 \
    selfcheck fsimx8x emmc-boot "0x138000" 0x2000 0x200 '' "${T}/build" "${T}/src"

T=${TMP}/sc3
mk_tree "${T}" y 0x4000 'CONFIG_ENV_NAND_RANGE=0x40000'
rc_is "selfcheck: the nand block count matches the range" 0 \
    selfcheck fsimx8mm nand "0x0 0x40000" 0x4000 0x20000 2 "${T}/build" "${T}/src"
rc_is "selfcheck: a wrong nand block count fails" 1 \
    selfcheck fsimx8mm nand "0x0 0x40000" 0x4000 0x20000 1 "${T}/build" "${T}/src"

# Regression for the expr-exit-1-on-zero bug: a zero product must reach the intended
# bbfatal message, not a raw abort with no message (both exit 1 under sh -ec).
rc_is "selfcheck: a zero nand product fails" 1 \
    selfcheck fsimx8mm nand "0x0 0x40000" 0x4000 0x20000 0 "${T}/build" "${T}/src"
has "selfcheck: a zero nand product is reported, not a raw abort" \
    "SECT * NSECT != CONFIG_ENV_NAND_RANGE" "${T}/selfcheck.out"

echo "---"
if [ "${fail}" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "${fail}"
