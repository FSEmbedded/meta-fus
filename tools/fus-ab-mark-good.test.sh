#!/bin/sh
# fus-ab-mark-good.test.sh -- the slot confirmation used without the update
# framework, against stub fw_printenv/fw_setenv and a fake kernel command line.
#
# Hardening tests for the two ways it goes wrong on a board: a counter that is
# never reset (the board falls back to the other slot after the attempts), and
# a write to the wrong variable or on every boot.
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "${DIR}/fus-test-lib.sh"
fus_test_init
fail=0

FILES="${DIR}/../meta-fus-bsp/recipes-core/fus-ab-mark-good/files"
SCRIPT="${FILES}/fus-ab-mark-good"
UNIT="${FILES}/fus-ab-mark-good.service"
for f in "${SCRIPT}" "${UNIT}"; do
    [ -f "${f}" ] || skip "layer file missing: ${f}"
done

# fw_printenv -n <var> prints ${TMP}/env/<var> and fails when it is unset;
# fw_setenv logs its arguments and exits with STUB_SETENV_RC.
mkdir -p "${TMP}/bin"
cat > "${TMP}/bin/fw_printenv" << 'STUB'
#!/bin/sh
[ "$1" = -n ] && shift
cat "${STUB_ENV}/$1" 2> /dev/null
STUB
cat > "${TMP}/bin/fw_setenv" << 'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "${STUB_LOG}"
exit "${STUB_SETENV_RC:-0}"
STUB
chmod +x "${TMP}/bin/fw_printenv" "${TMP}/bin/fw_setenv"

# run <cmdline> <BOOT_A_LEFT> <BOOT_B_LEFT> -> "<rc>|<fw_setenv calls>"
run() {
    rm -rf "${TMP}/env"
    mkdir "${TMP}/env"
    : > "${TMP}/log"
    printf '%s\n' "$1" > "${TMP}/cmdline"
    printf '%s' "$2" > "${TMP}/env/BOOT_A_LEFT"
    printf '%s' "$3" > "${TMP}/env/BOOT_B_LEFT"
    PATH="${TMP}/bin:${PATH}" STUB_ENV="${TMP}/env" STUB_LOG="${TMP}/log" \
        FUS_PROC_CMDLINE="${TMP}/cmdline" sh "${SCRIPT}" > /dev/null 2>&1
    printf '%s|%s' "$?" "$(cat "${TMP}/log")"
}

CL="console=ttymxc1,115200 root=/dev/mmcblk2p5 ro"

check "slot A resets BOOT_A_LEFT only" "0|BOOT_A_LEFT 3" "$(run "${CL} rauc.slot=A" 1 0)"
check "slot B resets BOOT_B_LEFT only" "0|BOOT_B_LEFT 3" "$(run "${CL} rauc.slot=B" 2 0)"
check "a lower-case slot name is the same slot" "0|BOOT_B_LEFT 3" "$(run "rauc.slot=b ${CL}" 3 2)"
check "a full counter is not rewritten" "0|" "$(run "${CL} rauc.slot=A" 3 0)"
check "an unset counter is written" "0|BOOT_A_LEFT 3" "$(run "${CL} rauc.slot=A" '' 3)"
check "no slot on the command line: refused, nothing written" "1|" "$(run "${CL}" 1 1)"
check "an empty slot: refused, nothing written" "1|" "$(run "${CL} rauc.slot=" 1 1)"
check "an unknown slot: refused, nothing written" "1|" "$(run "${CL} rauc.slot=X" 1 1)"
check "a failing fw_setenv fails the run" "4|BOOT_A_LEFT 3" \
    "$(STUB_SETENV_RC=4 run "${CL} rauc.slot=A" 1 3)"

# The unit gates, as rauc-mark-good.service has them.
has "unit: runs only on an A/B boot" "ConditionKernelCommandLine=rauc.slot" "${UNIT}"
has "unit: waits for a complete boot" "Requires=boot-complete.target" "${UNIT}"
has "unit: ordered after boot-complete and the env location" \
    "After=boot-complete.target fus-uboot-env-setup.service" "${UNIT}"
has "unit: outside the default boot ordering" "DefaultDependencies=no" "${UNIT}"

echo "---"
if [ "${fail}" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "${fail}"
