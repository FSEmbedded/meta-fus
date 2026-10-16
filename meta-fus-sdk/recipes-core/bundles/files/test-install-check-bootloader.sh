#!/bin/sh
# Host-side contract test for the bootloader branch of the install-check
# hook's slot-install stage. Nothing here ships to any image: it runs the hook
# against stub `fsimage` / `fw_printenv` / `sysctl` binaries and asserts per case
# the exit code and which steps ran. Usage: test-install-check-bootloader.sh <install-check>
set -u

HOOK=${1:?usage: $0 <path-to-install-check>}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir "$tmp/bin" "$tmp/mnt" "$tmp/hooktmp"
PATH="$tmp/bin:$PATH"
TMPDIR="$tmp/hooktmp"
RAUC_BUNDLE_MOUNT_POINT="$tmp/mnt"
RAUC_IMAGE_NAME=uboot.fs
RAUC_SLOT_NAME=bootloader.0
export PATH TMPDIR RAUC_BUNDLE_MOUNT_POINT RAUC_IMAGE_NAME RAUC_SLOT_NAME
IMG="$tmp/mnt/uboot.fs"

# mkimg <type> <descr>: a 64-byte image header (type field with a CRC in its
# last 4 bytes, like the real one) and a small payload.
mkimg() {
    {
        printf 'FSLX'; head -c 12 /dev/zero
        printf '%s' "$1"; head -c $((12 - ${#1})) /dev/zero; printf '\275\063\131\062'
        printf '%s' "$2"; head -c $((32 - ${#2})) /dev/zero
        printf 'AAAAAAAAAAAAAAAA'
    } > "$IMG"
}

# Stub fw_printenv: the file urs holds update_reboot_state, or FAIL.
cat > "$tmp/bin/fw_printenv" <<EOF
#!/bin/sh
[ "\$(cat "$tmp/urs")" = FAIL ] && exit 1
[ "\${1:-}" = -n ] && { cat "$tmp/urs"; exit 0; }
echo bootdelay=3
EOF

# Stub fsimage: logs each subcommand; the file mode selects the failure.
# Output lines are copied from a board run, including the load indentation.
cat > "$tmp/bin/fsimage" <<EOF
#!/bin/sh
echo "\$1" >> "$tmp/calls"
mode=\$(cat "$tmp/mode")
case "\$1" in
arch)
    [ "\$mode" = arch-fail ] && exit 1
    [ "\$mode" = arch-empty ] && exit 0
    echo fsimx8mm ;;
save)
    echo "Saving copy 1 to mmcblk2:"
    case "\$mode" in
    save-rc) echo "Saving U-Boot complete"; exit 1 ;;
    save-incomplete) echo "Saving U-Boot incomplete!" ;;
    *) echo "Saving U-Boot complete" ;;
    esac ;;
load)
    # load rewrites the header; model that with a zeroed one.
    { head -c 64 /dev/zero; tail -c +65 "$IMG"; } > "\$3"
    case "\$mode" in
    load-rc) echo "  Both copies are identical"; exit 1 ;;
    load-differ) echo "  Images differ" ;;
    load-mismatch) echo "  Both copies are identical"; printf B >> "\$3" ;;
    *) echo "  Both copies are identical" ;;
    esac ;;
esac
exit 0
EOF
# Stub sysctl logs into the same call list, so the cache drop is asserted to
# sit between save and load and never reaches the build host; sync is inert.
cat > "$tmp/bin/sysctl" <<EOF
#!/bin/sh
echo sysctl >> "$tmp/calls"
[ "\$(cat "$tmp/mode")" != drop-fail ]
EOF
printf '#!/bin/sh\n' > "$tmp/bin/sync"
chmod 0755 "$tmp/bin/fw_printenv" "$tmp/bin/fsimage" "$tmp/bin/sysctl" "$tmp/bin/sync"

fails=0
run_case() {
    # run_case <name> <slot-class> <urs> <fsimage-mode> <expect-rc> <expect-calls>
    name=$1
    : > "$tmp/calls"
    printf '%s\n' "$3" > "$tmp/urs"
    printf '%s\n' "$4" > "$tmp/mode"
    RAUC_SLOT_CLASS=$2 sh "$HOOK" slot-install >/dev/null 2>"$tmp/stderr"
    rc=$?
    calls=$(tr '\n' ' ' < "$tmp/calls")
    ok=1
    [ "$rc" -eq "$5" ] || { echo "  exit code $rc, expected $5"; ok=0; }
    [ "${calls% }" = "$6" ] || { echo "  calls [${calls% }], expected [$6]"; ok=0; }
    [ -z "$(ls -A "$tmp/hooktmp")" ] || { echo "  read-back temp dir left behind"; ok=0; }
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"; sed 's/^/  | /' "$tmp/stderr"
        fails=$((fails + 1))
    fi
}

mkimg U-BOOT fsimx8mm
run_case "write and read-back succeed"    bootloader 0    ok              0 "arch save sysctl load"
run_case "empty reboot state rejected"    bootloader ''   ok              1 ""
run_case "update in progress rejected"    bootloader 2    ok              1 ""
run_case "unreadable env rejected"        bootloader FAIL ok              1 ""
run_case "save exit code non-zero fails"  bootloader 0    save-rc         1 "arch save"
run_case "save success line missing"      bootloader 0    save-incomplete 1 "arch save"
run_case "cache drop failure fails"       bootloader 0    drop-fail       1 "arch save sysctl"
run_case "load exit code non-zero fails"  bootloader 0    load-rc         1 "arch save sysctl load"
run_case "differing copies fail"          bootloader 0    load-differ     1 "arch save sysctl load"
run_case "read-back payload mismatch"     bootloader 0    load-mismatch   1 "arch save sysctl load"
run_case "other slot class skips fsimage" appfs      0    ok              1 ""
mkimg NBOOT fsimx8mm
run_case "NBoot image never written"      bootloader 0    ok              1 "arch"
mkimg "$(printf 'U-BOOT\nX')" fsimx8mm
run_case "LF cannot cut the type field"   bootloader 0    ok              1 "arch"
mkimg U-BOOT "$(printf 'fsimx8mm\nX')"
run_case "LF cannot cut the board name"   bootloader 0    ok              1 "arch"
mkimg U-BOOT fsimx8mp
run_case "image for other board rejected" bootloader 0    ok              1 "arch"
mkimg U-BOOT ''
run_case "arch failure rejected"          bootloader 0    arch-fail       1 "arch"
run_case "empty arch rejected"            bootloader 0    arch-empty      1 "arch"

if [ "$fails" -ne 0 ]; then
    echo "install-check bootloader contract test: $fails case(s) FAILED"
    exit 1
fi
echo "install-check bootloader contract test: all cases passed"
