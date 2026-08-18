#!/bin/sh
# Host-side contract test for fs-updater-guard-rootfs. Nothing here ships to
# any image: it stages the wrapper against stub `rauc` / `fs-updater.real`
# binaries in a temp dir and asserts the reject/pass-through contract per
# case. Usage: test-fs-updater-guard-rootfs.sh <path-to-fs-updater-guard-rootfs>
set -u

GUARD=${1:?usage: $0 <path-to-fs-updater-guard-rootfs>}

tmp=$(mktemp -d) || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

mkdir "$tmp/bin"
PATH="$tmp/bin:$PATH"
export PATH

# Recording real-binary stub: logs its argv, one per line.
REAL="$tmp/fs-updater.real"
cat > "$REAL" <<EOF
#!/bin/sh
printf '%s\n' "\$@" > "$tmp/real-args"
exit 0
EOF
chmod 0755 "$REAL"
FUS_UPDATER_REAL_BIN=$REAL
export FUS_UPDATER_REAL_BIN

# Stub rauc: logs each invocation and emits the compatible flavour selected
# by the mode file (set per test case via stub_rauc).
cat > "$tmp/bin/rauc" <<EOF
#!/bin/sh
: >> "$tmp/rauc-called"
mode=\$(cat "$tmp/rauc-mode")
case "\$mode" in
fail) exit 1 ;;
appfs)     printf "RAUC_MF_COMPATIBLE='fus-update-board-appfs'\n" ;;
plain)     printf "RAUC_MF_COMPATIBLE='fus-update-board'\n" ;;
midstring) printf "RAUC_MF_COMPATIBLE='fus-update-appfs-legacy-fw'\n" ;;
unquoted)  printf 'RAUC_MF_COMPATIBLE=fus-update-board-appfs\n' ;;
empty)     printf "RAUC_MF_VERSION='1'\n" ;;
appfs-image)
    printf "RAUC_MF_COMPATIBLE='fus-update-board'\n"
    printf "RAUC_IMAGE_CLASS_0='appfs'\n"
    ;;
fw-images)
    printf "RAUC_MF_COMPATIBLE='fus-update-board'\n"
    printf "RAUC_IMAGE_CLASS_0='rootfs'\n"
    printf "RAUC_IMAGE_CLASS_1='boot'\n"
    ;;
combined-appfs)
    printf "RAUC_MF_COMPATIBLE='fus-update-board'\n"
    printf "RAUC_IMAGE_CLASS_0='rootfs'\n"
    printf "RAUC_IMAGE_CLASS_1='boot'\n"
    printf "RAUC_IMAGE_CLASS_2='appfs'\n"
    ;;
appfs-image-unquoted)
    printf "RAUC_MF_COMPATIBLE='fus-update-board'\n"
    printf 'RAUC_IMAGE_CLASS_0=appfs\n'
    ;;
appfs-nearmiss)
    printf "RAUC_MF_COMPATIBLE='fus-update-board'\n"
    printf "RAUC_IMAGE_CLASS_0='appfs-extra'\n"
    ;;
esac
exit 0
EOF
chmod 0755 "$tmp/bin/rauc"

stub_rauc() {
    printf '%s\n' "$1" > "$tmp/rauc-mode"
}

fails=0
run_case() {
    # run_case <name> <rauc-mode> <expect: reject|pass> <expect-rauc: rauc|norauc> [args...]
    name=$1 rmode=$2 expect=$3 expect_rauc=$4
    shift 4
    rm -f "$tmp/real-args" "$tmp/rauc-called"
    stub_rauc "$rmode"
    sh "$GUARD" "$@" >/dev/null 2>"$tmp/stderr"
    rc=$?
    ok=1
    case "$expect" in
    reject)
        [ "$rc" -ne 0 ] || { echo "  exit code 0, expected non-zero"; ok=0; }
        [ ! -e "$tmp/real-args" ] || { echo "  real binary was invoked, expected never"; ok=0; }
        ;;
    pass)
        [ "$rc" -eq 0 ] || { echo "  exit code $rc, expected 0"; ok=0; }
        if [ -e "$tmp/real-args" ]; then
            printf '%s\n' "$@" > "$tmp/want-args"
            cmp -s "$tmp/want-args" "$tmp/real-args" || {
                echo "  argv mangled: got [$(tr '\n' ' ' < "$tmp/real-args")] want [$*]"; ok=0; }
        else
            echo "  real binary never invoked, expected pass-through"; ok=0
        fi
        ;;
    esac
    case "$expect_rauc" in
    rauc)   [ -e "$tmp/rauc-called" ] || { echo "  rauc info not called, expected call"; ok=0; } ;;
    norauc) [ ! -e "$tmp/rauc-called" ] || { echo "  rauc info called, expected no call"; ok=0; } ;;
    esac
    if [ "$ok" -eq 1 ]; then
        echo "PASS: $name"
    else
        echo "FAIL: $name"
        fails=$((fails + 1))
    fi
}

run_case "appfs bundle rejected (space form)"        appfs     reject rauc   --install_update /path/to.raucb
run_case "appfs bundle rejected (= form)"            appfs     reject rauc   --install_update=/path/to.raucb
run_case "plain bundle passes (space form)"          plain     pass   rauc   --install_update /path/to.raucb
run_case "plain bundle passes (= form)"              plain     pass   rauc   --install_update=/path/to.raucb
run_case "mid-string appfs passes (suffix match)"    midstring pass   rauc   --install_update /path/to.raucb
run_case "rauc info failure rejects (fail closed)"   fail      reject rauc   --install_update /path/to.raucb
run_case "unquoted compatible still rejected"        unquoted  reject rauc   --install_update /path/to.raucb
run_case "missing compatible rejects (fail closed)"  empty     reject rauc   --install_update /path/to.raucb
run_case "other verb passes with no rauc call"       plain     pass   norauc --update_reboot_state
run_case "pathless --install_update passes through"  plain     pass   norauc --install_update

# Image-class check (independent of the compatible-suffix check above):
run_case "appfs image member rejected (slot-mode app-only)"    appfs-image           reject rauc --install_update /path/to.raucb
run_case "firmware bundle with image classes still passes"     fw-images             pass   rauc --install_update /path/to.raucb
run_case "combined bundle with appfs member rejected"          combined-appfs        reject rauc --install_update /path/to.raucb
run_case "unquoted appfs image class rejected"                 appfs-image-unquoted  reject rauc --install_update /path/to.raucb
run_case "near-miss image class passes (exact match only)"     appfs-nearmiss        pass   rauc --install_update /path/to.raucb

if [ "$fails" -ne 0 ]; then
    echo "fs-updater-guard-rootfs contract test: $fails case(s) FAILED"
    exit 1
fi
echo "fs-updater-guard-rootfs contract test: all cases passed"
