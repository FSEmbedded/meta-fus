# shellcheck shell=sh
# fus-bundle-lib.sh -- shared library for the standalone RAUC bundle tools.
#
# Sourced, never executed -- hence no shebang; the shell directive above is
# the marker tools/lint-shell.sh discovers. Each tool sources this file from
# its own directory: the tool set is copied around as one directory, nothing
# is searched for anywhere else, and no path into any build environment is
# built in.
#
# Error regime: `set -u` only, deliberately no `set -e`; every deliberate
# failure exits through fus_die with a code from the shared table below.
# POSIX sh throughout. No pipeline whose exit status carries a verdict:
# command output is captured to a file or variable, the status checked, and
# only then parsed.
#
# Shared exit codes (each tool assigns a subset; unused codes stay unused):
#    0  ok
#    1  unexpected -- never assigned deliberately; a 1 is a script defect
#    2  usage: arguments, combinations, unparsable values
#    3  required tool missing or not executable
#    4  signing material or keyring unusable
#    5  source missing, incomplete or breaking its contract
#    6  size guard
#    7  rauc bundle/resign failed
#    8  verification failed
#    9  identity proof failed
#   10  version/floor policy violation
#   11  environment precondition not met
set -u

# Functional constants. Defaults mirror the layer's build configuration;
# every line is overridable from the environment. No tool ever reads a
# .inc file.
# shellcheck disable=SC2034  # consumed by the sourcing tools, not in here
{
    FUS_COMPAT_PREFIX="${FUS_COMPAT_PREFIX:-fus-update-}"
    FUS_APP_COMPAT_SUFFIX="${FUS_APP_COMPAT_SUFFIX:--appfs}"
    FUS_BUNDLE_FORMAT="${FUS_BUNDLE_FORMAT:-verity}"
    FUS_FW_SLOT_CLASS="${FUS_FW_SLOT_CLASS:-rootfs}"
    FUS_APP_SLOT_CLASS="${FUS_APP_SLOT_CLASS:-appfs}"
    FUS_FW_IMAGE_HOOK="${FUS_FW_IMAGE_HOOK:-post-install}"
    FUS_APP_IMAGE_HOOK="${FUS_APP_IMAGE_HOOK:-install}"
    FUS_APP_BUNDLE_HOOK="${FUS_APP_BUNDLE_HOOK:-install-check}"
    FUS_FW_PAYLOAD_GLOB="${FUS_FW_PAYLOAD_GLOB:-fusys-image-*.squashfs}"
    FUS_APP_PAYLOAD_NAME="${FUS_APP_PAYLOAD_NAME:-fus-app-container.squashfs}"
    FUS_APP_IMG_DIR="${FUS_APP_IMG_DIR:-/data/app/images}"
    FUS_SIZE_ROOT_MIB="${FUS_SIZE_ROOT_MIB:-256}"
    FUS_MKSQUASHFS_ARGS="${FUS_MKSQUASHFS_ARGS:--noappend -comp zstd -Xcompression-level 19}"
    FUS_APP_MKSQUASHFS_ARGS="${FUS_APP_MKSQUASHFS_ARGS:-$FUS_MKSQUASHFS_ARGS -all-root}"
    FUS_FW_DESCRIPTION="${FUS_FW_DESCRIPTION:-RAUC firmware-only update bundle (rootfs, plus the boot slot when boot=slot) for the F&S update standard image}"
    FUS_APP_DESCRIPTION="${FUS_APP_DESCRIPTION:-RAUC application-only update bundle (appfs slot) for the F&S update standard image}"
    # The measured rauc window: 1.13 (host) and 1.15.2 (build container),
    # end to end. Older is unmeasured -- not known-broken; newer only warns.
    FUS_RAUC_MIN="${FUS_RAUC_MIN:-1.13}"
    FUS_RAUC_MAX_TESTED="${FUS_RAUC_MAX_TESTED:-1.15.2}"
}

fus_die() { # fus_die <code> <text ...>
    # The only deliberate exit. Names the failing step and cause -- never the
    # command line, which would carry key/cert arguments into CI logs.
    _fd_code=$1; shift
    printf '%s: %s\n' "${0##*/}" "$*" >&2
    exit "$_fd_code"
}

fus_workdir() { # fus_workdir <parent-dir>
    # Creates the work directory inside <parent-dir> and installs the cleanup
    # trap. Result in FUS_WORKDIR -- set instead of printed, because a command
    # substitution's subshell could not install the trap in the caller.
    [ -d "$1" ] || fus_die 2 "work directory parent does not exist: $1"
    FUS_WORKDIR=$(mktemp -d "${1%/}/fus-work.XXXXXX") || \
        fus_die 2 "cannot create a work directory under: $1"
    # Save $? first and re-raise it at the end: cleanup must never turn a
    # failure into a 0.
    # shellcheck disable=SC2154  # fus_trap_rc is assigned inside the trap string itself
    trap 'fus_trap_rc=$?; rm -rf "$FUS_WORKDIR"; exit "$fus_trap_rc"' EXIT INT TERM
}

fus_abspath() { # fus_abspath <path>  -> the path pinned to the cwd
    case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s\n' "$PWD/$1" ;;
    esac
}

fus_tool_resolve() { # fus_tool_resolve <name> <envvar> <debian-package> [byname]
    # Prints the resolved path, always absolute. Env override first, then
    # PATH; anything else is exit 3 naming both the binary and the Debian
    # package providing it. Pass "byname" for a tool that another tool
    # launches BY NAME over a PATH prefix built from this result (mksquashfs,
    # launched by rauc): there an override under any other basename would
    # split preflight and build -- the preflight validates one file, rauc
    # runs another -- and is refused. Tools only ever invoked by path (rauc
    # itself) carry no naming constraint.
    eval "_tr_env=\${$2:-}"
    if [ -n "$_tr_env" ]; then
        # Pin a relative override (a bare name included) to the cwd BEFORE
        # validating, so the validated file and any PATH prefix built from
        # it name the same binary.
        _tr_env=$(fus_abspath "$_tr_env")
        if [ "${4:-}" = "byname" ] && [ "${_tr_env##*/}" != "$1" ]; then
            fus_die 3 \
                "tool '$1': \$$2 basename '${_tr_env##*/}' differs from the tool name; it is invoked by name at build time -- provide it as '$1' (a symlink is fine)"
        fi
        [ -f "$_tr_env" ] && [ -x "$_tr_env" ] || fus_die 3 \
            "tool '$1': \$$2 does not point at an executable file (Debian package: $3)"
        printf '%s\n' "$_tr_env"
        return 0
    fi
    _tr_path=$(command -v "$1" 2>/dev/null) || fus_die 3 \
        "tool '$1': not found in PATH and \$$2 is not set (Debian package: $3)"
    # command -v echoes a relative path for a relative PATH entry; pin it,
    # or the PATH prefix built from it is the very no-op described above.
    fus_abspath "$_tr_path"
}

fus_tools_report() { # fus_tools_report <name> <envvar> <debian-package> <byname|-> ...
    # Resolves each quadruple and prints path and version (exit 3 through
    # fus_tool_resolve when one is missing or refused). The by-name marker
    # travels WITH the tool entry: a refused override must never leave a
    # blessed tool.*.path line behind for a log scraper to read. Tool paths
    # are not secrets -- only key/cert paths are.
    while [ $# -gt 0 ]; do
        # A stale triple-form caller (a mixed copy pairing an older tool with
        # this library) must fail loudly, not silently skip a trailing tool.
        [ $# -ge 4 ] || fus_die 2 \
            "fus_tools_report: arguments come in name/envvar/package/byname quadruples"
        _trr_path=$(fus_tool_resolve "$1" "$2" "$3" "$4") || exit $?
        # Same per-tool flag mapping fus_tool_version_line's callers use for the
        # .info file: mksquashfs alone takes a single dash, openssl a bare verb.
        case "$1" in
        mksquashfs) _trr_flag=-version ;;
        openssl)    _trr_flag=version ;;
        *)          _trr_flag=--version ;;
        esac
        _trr_ver=$("$_trr_path" "$_trr_flag" 2>/dev/null) || _trr_ver=''
        _trr_ver=$(printf '%s\n' "$_trr_ver" | sed -n 1p)
        [ -n "$_trr_ver" ] || _trr_ver=unknown
        printf 'tool.%s.path=%s\ntool.%s.version=%s\n' \
            "$1" "$_trr_path" "$1" "$_trr_ver"
        shift 4
    done
}

fus_tool_version_line() { # fus_tool_version_line <tool-path> <version-flag>  -> first line, or nothing
    # The version banner a tool prints about itself, for the build evidence.
    # The flag is a PARAMETER because the tools disagree: rauc and veritysetup
    # take --version, mksquashfs -version, openssl a bare `version`. A tool
    # that refuses to say prints nothing here and the caller records it as
    # unknown -- a version banner is evidence, never a gate.
    _tvl=$("$1" "$2" 2>/dev/null) || _tvl=''
    printf '%s\n' "$_tvl" | sed -n 1p
}

fus_rauc_version() { # fus_rauc_version <rauc-path>  -> parsed version, or nothing
    # First digit-led word of the first --version line ("rauc 1.13" -> 1.13).
    # Prints nothing when no such word exists; deciding what that means is
    # the caller's business.
    _rvv_raw=$("$1" --version 2>/dev/null) || _rvv_raw=''
    _rvv_raw=$(printf '%s\n' "$_rvv_raw" | sed -n 1p)
    for _rvv_w in $_rvv_raw; do
        case "$_rvv_w" in
        [0-9]*) printf '%s\n' "$_rvv_w"; return 0 ;;
        esac
    done
    return 0
}

fus_rauc_version_gate() { # fus_rauc_version_gate <rauc-path> <min> <max-tested>
    # Enforces the measured version window. Below <min> is exit 3: an older
    # rauc is UNMEASURED, not known-broken, and the message says so and names
    # the override. Above <max-tested> only warns. This window guards against
    # the past; drift in a future rauc is caught by the parser's field
    # assertions, not here.
    fus_semver_valid "$2" || fus_die 2 "FUS_RAUC_MIN '$2' is not semver-parsable"
    fus_semver_valid "$3" || fus_die 2 "FUS_RAUC_MAX_TESTED '$3' is not semver-parsable"
    _rvg_ver=$(fus_rauc_version "$1")
    if [ -z "$_rvg_ver" ] || ! fus_semver_valid "$_rvg_ver"; then
        printf '%s\n' "${0##*/}: WARNING: cannot determine the rauc version; the measured window ($2..$3) is unchecked" >&2
        return 0
    fi
    if [ "$(fus_semver_cmp "$_rvg_ver" "$2")" = lt ]; then
        fus_die 3 "rauc $_rvg_ver is older than $2, the oldest measured version -- older rauc is unmeasured, not known-broken; measure it, then override with FUS_RAUC_MIN"
    fi
    if [ "$(fus_semver_cmp "$_rvg_ver" "$3")" = gt ]; then
        printf '%s\n' "${0##*/}: WARNING: rauc $_rvg_ver is newer than $3, the newest measured version" >&2
    fi
    return 0
}

fus_require_file() { # fus_require_file <path> <code> <message>
    # The message is entirely the caller's: for key/cert material it must not
    # contain the path.
    [ -f "$1" ] && [ -r "$1" ] || fus_die "$2" "$3"
}

fus_require_signing() { # fus_require_signing <cert-spec> <key-spec>
    # Each spec is a file path or a pkcs11: URI. A URI is taken as given --
    # rauc talks to the token, and the PIN travels only in RAUC_PKCS11_PIN.
    # No path (and no URI) ever appears in a message here.
    [ -n "$1" ] || fus_die 4 "signing material: no certificate given (--cert, FUS_UPDATE_CERT or --certs)"
    [ -n "$2" ] || fus_die 4 "signing material: no key given (--key, FUS_UPDATE_KEY or --certs)"
    case "$1" in
    pkcs11:*) : ;;
    *) [ -f "$1" ] && [ -r "$1" ] || fus_die 4 "signing certificate: not a readable file (path withheld)" ;;
    esac
    case "$2" in
    pkcs11:*) : ;;
    *) [ -f "$2" ] && [ -r "$2" ] || fus_die 4 "signing key: not a readable file (path withheld)" ;;
    esac
}

fus_write_verify_conf() { # fus_write_verify_conf <keyring-abs-path> <dest-file>
    # The minimal configuration that makes `rauc info` verify the way the
    # device does. Measured against rauc 1.13: [system] compatible and
    # bootloader must both be present for the config to load at all, although
    # `info` uses neither -- and compatible is NOT enforced by info (an -appfs
    # bundle verifies against a conf naming any string), so a compatible check
    # is always the caller's own comparison. use-bundle-signing-time=true
    # loads and verifies cleanly and matches the device's rules.
    printf '%s\n' \
        '[system]' \
        'compatible=fus-verify' \
        'bootloader=uboot' \
        '' \
        '[keyring]' \
        "path=$1" \
        'check-purpose=codesign' \
        'use-bundle-signing-time=true' \
        > "$2" || fus_die 2 "cannot write the verify configuration"
}

fus_check_slot_fit() { # fus_check_slot_fit <payload-file> <limit-mib> [stat-fail-code]
    # The rootfs slot guard, in one place because two doors need it at two
    # different moments: the image door checks the named source as a
    # preflight (before any work), the directory door can only check what
    # mksquashfs produced, so it checks after packing. The uncompressed tree
    # size is NOT the metric -- only the packed result is comparable to the
    # slot.
    # The stat happens HERE and its status is checked here. Routing it
    # through a helper that stats internally would put its own `fus_die` call
    # inside a command substitution, where it kills only the subshell: the
    # caller would then compare an empty string and die 6 -- a fabricated
    # size-guard verdict for a file that could not be stat'ed at all.
    # Always dereferences: the deploy directory publishes bundles behind
    # symlinks, and a plain `stat -c %s` on the link answers the length of
    # the target NAME (44 was measured), not the file.
    # A stat failure here means two different things depending on the door:
    # for the image door the source was already validated readable, so this
    # is defensive (usage-class, 2 by default); for the directory door this
    # runs on a file THIS SCRIPT just packed, so a failure here is the
    # packer's fault, not the caller's -- the directory-door call site passes
    # 7 explicitly.
    # limit-mib feeds an arithmetic expansion below; unlike every other
    # overridable constant in this file it reached no guard, so a malformed
    # FUS_SIZE_ROOT_MIB (empty, or colliding with an unrelated env var name)
    # crashed the shell instead of failing through fus_die.
    case "$2" in
    ''|*[!0-9]*) fus_die 2 "slot guard: limit-mib is not a plain number: '$2'" ;;
    esac
    _csf_size=$(stat -Lc %s "$1" 2>/dev/null) || _csf_size=''
    case "$_csf_size" in
    ''|*[!0-9]*) fus_die "${3:-2}" "cannot stat the payload for the slot guard: $1" ;;
    esac
    _csf_limit=$(($2 * 1024 * 1024))
    [ "$_csf_size" -le "$_csf_limit" ] || fus_die 6 \
        "payload is $_csf_size bytes, over the $2 MiB rootfs slot"
}

fus_args_contain() { # fus_args_contain <arg-string> <flag>  (predicate: 0 yes, 1 no)
    # Word-wise, never a substring match: "-all-rootish" must not read as
    # "-all-root". Both mksquashfs argument constants are overridable from the
    # environment, and the two doors depend on the OPPOSITE answer -- the app
    # payload must be flattened to uid 0, the firmware payload must keep the
    # ownership fus_require_root vouches for. Without this predicate either
    # property is lost to an environment variable alone, silently: the uid
    # guard would still report a clean root build while -all-root had already
    # discarded the ownership it claims to protect.
    # shellcheck disable=SC2086  # the argument list is a word list on purpose
    for _ac in $1; do
        [ "$_ac" = "$2" ] && return 0
    done
    return 1
}

fus_require_root() { # fus_require_root <bypass:0|1> <what>
    # The packed root filesystem carries the uid/gid the packer saw: Yocto
    # packs under pseudo with the real ownership, and a non-root run would
    # write the builder's own uid into every inode of the image the device
    # boots. That is not a warning-level difference, so the default is a
    # refusal (11) and the bypass has to be asked for by name -- loudly, and
    # recorded by the caller in the build evidence.
    # `id` is a PATH lookup, so this is called AFTER tool resolution: under
    # an emptied PATH the documented tool error must win over a uid that
    # could not be read at all.
    # The result lands in FUS_BUILD_UID instead of on stdout: a command
    # substitution would run the fus_die below in a subshell and the caller
    # would sail on past a refused build.
    _rr_uid=$(id -u 2>/dev/null) || _rr_uid=''
    case "$_rr_uid" in
    ''|*[!0-9]*) fus_die 11 "cannot determine the effective uid; $2 needs a known uid" ;;
    esac
    # shellcheck disable=SC2034  # read by the sourcing tool, as FUS_WORKDIR is
    FUS_BUILD_UID=$_rr_uid
    [ "$_rr_uid" -ne 0 ] || return 0
    [ "$1" -eq 1 ] || fus_die 11 \
        "$2 needs root: the packed filesystem keeps the uid/gid of the packing process, and uid $_rr_uid would ship the builder's ownership to the device; re-run as root or accept it with --i-know-ownership-is-wrong"
    printf '%s\n' "${0##*/}: WARNING: packing as uid $_rr_uid, not root: every file in the packed filesystem carries this uid/gid instead of the intended ownership; the bundle is recorded as ownership-bypassed" >&2
}

fus_squashfs_from_dir() { # fus_squashfs_from_dir <source-dir> <dest-file> <mksquashfs> <source-date-epoch> <errlog> <mksquashfs-args>
    # Packs <source-dir> with the caller's mksquashfs settings and a pinned
    # SOURCE_DATE_EPOCH -- the same variable rauc's internal mksquashfs call
    # gets on the image door, only here this script is the caller. The
    # argument list is a PARAMETER, not the global: the app payload needs
    # -all-root (FUS_APP_MKSQUASHFS_ARGS) and must not have to redefine the
    # firmware constant to get it.
    # mksquashfs output is captured and only passed through on failure: it
    # must never be echoed as a command line.
    # shellcheck disable=SC2086  # the argument list is a word list on purpose
    SOURCE_DATE_EPOCH="$4" "$3" "$1" "$2" $6 >"$5" 2>&1
    _sfd_rc=$?
    if [ "$_sfd_rc" -ne 0 ]; then
        cat "$5" >&2
        fus_die 7 "pack: mksquashfs failed (exit $_sfd_rc)"
    fi
    # A zero exit that produced nothing is the failure mode a stubbed or
    # sandboxed mksquashfs shows; it must not reach rauc as an empty payload.
    [ -f "$2" ] && [ -s "$2" ] || fus_die 7 \
        "pack: mksquashfs exited 0 but left no non-empty output"
}

fus_semver_valid() { # fus_semver_valid <version>  (predicate: 0 valid, 1 not)
    # Accepts MAJOR[.MINOR[.PATCH]][-pre][+build]. Looser than strict semver
    # where it is safe to be (leading zeros): the device is the authority, a
    # local pre-check must not reject what the device would accept.
    _svv=$1
    case "$_svv" in
    *+*)
        _svv_build=${_svv#*+}
        _svv=${_svv%%+*}
        case "$_svv_build" in ''|*[!0-9A-Za-z.-]*) return 1 ;; esac
        case "$_svv_build" in .*|*.|*..*) return 1 ;; esac
        ;;
    esac
    case "$_svv" in
    *-*)
        _svv_pre=${_svv#*-}
        _svv=${_svv%%-*}
        case "$_svv_pre" in ''|*[!0-9A-Za-z.-]*) return 1 ;; esac
        case "$_svv_pre" in .*|*.|*..*) return 1 ;; esac
        ;;
    esac
    # numeric core: one to three dot-separated digit fields
    _svv_n=0
    while :; do
        case "$_svv" in
        *.*) _svv_f=${_svv%%.*}; _svv=${_svv#*.} ;;
        *)   _svv_f=$_svv; _svv='' ;;
        esac
        case "$_svv_f" in ''|*[!0-9]*) return 1 ;; esac
        _svv_n=$((_svv_n + 1))
        [ -n "$_svv" ] || break
        [ "$_svv_n" -lt 3 ] || return 1
    done
    return 0
}

fus_check_semver() { # fus_check_semver <version>
    fus_semver_valid "$1" || fus_die 2 "version '$1' is not semver-parsable"
}

fus_check_version_shape() { # fus_check_version_shape <version>  (warning only)
    # This project's bundle versions are date-shaped (YYYYMMDD). A semver-
    # small value like 1.0 is VALID yet sits below every date floor, and the
    # device's refusal for it names neither the version nor the cause -- so
    # an odd shape is flagged early and loudly. Not rejected: a later switch
    # to semantic versions must not be blocked by this tool. Returns 1 when
    # it warned (never exits), so a builder can record the fact in its .info.
    case "$1" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) return 0 ;;
    esac
    printf '%s\n' "${0##*/}: WARNING: version '$1' is not date-shaped (YYYYMMDD) like this project's bundle versions" >&2
    return 1
}

fus_semver_cmp() { # fus_semver_cmp <a> <b>  -> lt|eq|gt on stdout
    # Semver precedence: numeric core first; a release outranks any
    # pre-release of the same core; pre-release identifiers compare left to
    # right (numeric numerically and below alphanumeric, alphanumeric
    # bytewise); fewer identifiers rank lower; build metadata is ignored.
    # Inputs are pre-validated with fus_semver_valid by the caller.
    _smc_a=${1%%+*}; _smc_b=${2%%+*}
    _smc_ap=''; _smc_bp=''
    case "$_smc_a" in *-*) _smc_ap=${_smc_a#*-}; _smc_a=${_smc_a%%-*} ;; esac
    case "$_smc_b" in *-*) _smc_bp=${_smc_b#*-}; _smc_b=${_smc_b%%-*} ;; esac
    _smc_ac="$_smc_a.0.0"; _smc_bc="$_smc_b.0.0"
    _smc_i=0
    while [ "$_smc_i" -lt 3 ]; do
        _smc_fa=${_smc_ac%%.*}; _smc_ac=${_smc_ac#*.}
        _smc_fb=${_smc_bc%%.*}; _smc_bc=${_smc_bc#*.}
        if [ "$_smc_fa" -lt "$_smc_fb" ]; then echo lt; return 0; fi
        if [ "$_smc_fa" -gt "$_smc_fb" ]; then echo gt; return 0; fi
        _smc_i=$((_smc_i + 1))
    done
    if [ -z "$_smc_ap" ] && [ -z "$_smc_bp" ]; then echo eq; return 0; fi
    if [ -z "$_smc_ap" ]; then echo gt; return 0; fi
    if [ -z "$_smc_bp" ]; then echo lt; return 0; fi
    while :; do
        if [ -z "$_smc_ap" ] && [ -z "$_smc_bp" ]; then echo eq; return 0; fi
        if [ -z "$_smc_ap" ]; then echo lt; return 0; fi
        if [ -z "$_smc_bp" ]; then echo gt; return 0; fi
        case "$_smc_ap" in
        *.*) _smc_fa=${_smc_ap%%.*}; _smc_ap=${_smc_ap#*.} ;;
        *)   _smc_fa=$_smc_ap; _smc_ap='' ;;
        esac
        case "$_smc_bp" in
        *.*) _smc_fb=${_smc_bp%%.*}; _smc_bp=${_smc_bp#*.} ;;
        *)   _smc_fb=$_smc_bp; _smc_bp='' ;;
        esac
        _smc_na=1; _smc_nb=1
        case "$_smc_fa" in *[!0-9]*) _smc_na=0 ;; esac
        case "$_smc_fb" in *[!0-9]*) _smc_nb=0 ;; esac
        if [ "$_smc_na" -eq 1 ] && [ "$_smc_nb" -eq 1 ]; then
            if [ "$_smc_fa" -lt "$_smc_fb" ]; then echo lt; return 0; fi
            if [ "$_smc_fa" -gt "$_smc_fb" ]; then echo gt; return 0; fi
        elif [ "$_smc_na" -eq 1 ]; then
            echo lt; return 0
        elif [ "$_smc_nb" -eq 1 ]; then
            echo gt; return 0
        elif [ "$_smc_fa" != "$_smc_fb" ]; then
            # LC_ALL=C: bytewise order, not locale collation
            if LC_ALL=C expr "x$_smc_fa" \< "x$_smc_fb" >/dev/null; then
                echo lt
            else
                echo gt
            fi
            return 0
        fi
    done
}

fus_check_floor() { # fus_check_floor <bundle-version> <floor>
    # The device rejects below-floor AND version-less bundles when a floor is
    # set; both are policy verdicts (10), not broken inputs. The floor itself
    # is a caller argument and pre-validated there (exit 2). Equality passes,
    # as it does on the device.
    [ -n "$1" ] || fus_die 10 \
        "floor check: bundle carries no version while a floor is set"
    fus_semver_valid "$1" || fus_die 10 \
        "floor check: bundle version '$1' is not semver-parsable"
    _cfl=$(fus_semver_cmp "$1" "$2")
    [ "$_cfl" != lt ] || fus_die 10 \
        "floor violation: bundle version '$1' is below floor '$2'"
}

fus_shell_value() { # fus_shell_value <file> <KEY>  -> value ('' when absent)
    # Accepts KEY='value' and KEY=value lines. A value whose embedded quoting
    # defeats this parses wrong and every comparison built on it fails
    # closed -- deliberately no eval of bundle-controlled text here.
    _sfv=$(sed -n "s/^$2=//p" "$1" | sed -n 1p)
    case "$_sfv" in
    \'*\') _sfv=${_sfv#\'}; _sfv=${_sfv%\'} ;;
    esac
    printf '%s\n' "$_sfv"
}

fus_identity_from_shell() { # fus_identity_from_shell <rauc-shell-output-file>
    # THE single parse point for `rauc info --output-format=shell`. Field
    # names measured IDENTICAL on rauc 1.13 (host) and 1.15.2 (build
    # container): scalars RAUC_MF_*, images 0-indexed RAUC_IMAGE_*_<n>. If a
    # future rauc differs, correct it here and in the canned block of
    # fus-rauc-stub.sh together, nowhere else.
    _ifs_file=$1
    # Every expected scalar must be present as a line (it may be empty). A
    # version floor on rauc guards against the past only; a field renamed in
    # a future rauc is caught by this assertion.
    for _ifs_k in RAUC_MF_COMPATIBLE RAUC_MF_VERSION RAUC_MF_BUILD \
                  RAUC_MF_FORMAT RAUC_MF_HOOKS RAUC_MF_IMAGES; do
        grep -q "^${_ifs_k}=" "$_ifs_file" || fus_die 8 \
            "parse: expected scalar $_ifs_k missing from rauc info output (renamed in this rauc?)"
    done
    _ifs_compat=$(fus_shell_value "$_ifs_file" RAUC_MF_COMPATIBLE)
    _ifs_version=$(fus_shell_value "$_ifs_file" RAUC_MF_VERSION)
    _ifs_build=$(fus_shell_value "$_ifs_file" RAUC_MF_BUILD)
    _ifs_format=$(fus_shell_value "$_ifs_file" RAUC_MF_FORMAT)
    _ifs_hooks=$(fus_shell_value "$_ifs_file" RAUC_MF_HOOKS)
    [ -n "$_ifs_compat" ] || fus_die 8 \
        "parse: no compatible in rauc info output (drifted field names? see fus_identity_from_shell)"
    printf 'compatible=%s\nversion=%s\nbuild=%s\nformat=%s\nhooks=%s\n' \
        "$_ifs_compat" "$_ifs_version" "$_ifs_build" "$_ifs_format" "$_ifs_hooks"
    # Images keyed by slot class, not by ordinal: the reference diff must
    # pair images even when two generators order manifest sections
    # differently. rauc's own count drives the loop, so a renamed per-image
    # field cannot silently shrink the identity.
    _ifs_cnt=$(fus_shell_value "$_ifs_file" RAUC_MF_IMAGES)
    case "$_ifs_cnt" in
    ''|*[!0-9]*) fus_die 8 "parse: RAUC_MF_IMAGES is not a count: '$_ifs_cnt'" ;;
    esac
    [ "$_ifs_cnt" -gt 0 ] || fus_die 8 \
        "parse: no images in rauc info output (drifted field names? see fus_identity_from_shell)"
    _ifs_seen=' '; _ifs_i=0
    while [ "$_ifs_i" -lt "$_ifs_cnt" ]; do
        # The same presence rule as for the scalars, per index: an absent
        # line is drift (a renamed DIGEST would otherwise make the reference
        # diff compare empty against empty and pass); present-but-empty is
        # legitimate -- ARTIFACT, VARIANT and a hookless image's HOOKS are
        # all measured empty-but-present on rauc 1.13.
        for _ifs_k in NAME CLASS DIGEST SIZE HOOKS; do
            grep -q "^RAUC_IMAGE_${_ifs_k}_${_ifs_i}=" "$_ifs_file" || fus_die 8 \
                "parse: expected field RAUC_IMAGE_${_ifs_k}_${_ifs_i} missing from rauc info output (renamed in this rauc?)"
        done
        _ifs_cls=$(fus_shell_value "$_ifs_file" "RAUC_IMAGE_CLASS_$_ifs_i")
        _ifs_name=$(fus_shell_value "$_ifs_file" "RAUC_IMAGE_NAME_$_ifs_i")
        _ifs_dig=$(fus_shell_value "$_ifs_file" "RAUC_IMAGE_DIGEST_$_ifs_i")
        _ifs_size=$(fus_shell_value "$_ifs_file" "RAUC_IMAGE_SIZE_$_ifs_i")
        _ifs_ihooks=$(fus_shell_value "$_ifs_file" "RAUC_IMAGE_HOOKS_$_ifs_i")
        [ -n "$_ifs_cls" ] || fus_die 8 "parse: image $_ifs_i carries no slot class"
        case "$_ifs_seen" in
        *" $_ifs_cls "*) fus_die 8 "parse: duplicate image class '$_ifs_cls'" ;;
        esac
        _ifs_seen="$_ifs_seen$_ifs_cls "
        # hooks is part of the identity: an image that lost its post-install
        # hook (no read-back on the device) must not diff clean.
        printf 'image.%s.filename=%s\nimage.%s.sha256=%s\nimage.%s.size=%s\nimage.%s.hooks=%s\n' \
            "$_ifs_cls" "$_ifs_name" "$_ifs_cls" "$_ifs_dig" \
            "$_ifs_cls" "$_ifs_size" "$_ifs_cls" "$_ifs_ihooks"
        _ifs_i=$((_ifs_i + 1))
    done
    # The count drives the loop, so it only bounds one direction; entries
    # beyond the count -- gapped ones included -- would otherwise vanish
    # from both sides of a reference diff and pass uncompared.
    _ifs_lines=$(grep -c '^RAUC_IMAGE_NAME_[0-9][0-9]*=' "$_ifs_file")
    if [ "$_ifs_lines" -ne "$_ifs_cnt" ]; then
        fus_die 8 "parse: $_ifs_lines image name lines but RAUC_MF_IMAGES reports $_ifs_cnt"
    fi
    printf 'image.count=%s\n' "$_ifs_cnt"
}

fus_bundle_identity() { # fus_bundle_identity <bundle> <rauc> <conf> <workdir> <step>
    # Verifies <bundle> under the system configuration <conf> and prints the
    # normalized machine-readable identity (manifest fields + image digests).
    # Always under a configuration: without one, rauc applies its default
    # certificate purpose, which is stricter than codesign and rejects a
    # signing leaf carrying only extendedKeyUsage=codeSigning (measured:
    # "unsuitable certificate purpose"). A bare `info --keyring` therefore
    # cannot verify these bundles at all.
    # Signer SPKI data is not part of this identity: it would need openssl,
    # and the verify tool needs rauc only.
    # Call with stdout redirected, never in a command substitution, so a
    # fus_die below terminates the caller directly. Output is captured to a
    # file first: a rauc failure must set the exit code even though its
    # output would parse -- a pipeline would swallow exactly that.
    _bi_out="$4/rauc-info-$5.out"; _bi_err="$4/rauc-info-$5.err"
    "$2" --conf "$3" info --output-format=shell "$1" >"$_bi_out" 2>"$_bi_err"
    _bi_rc=$?
    if [ "$_bi_rc" -ne 0 ]; then
        cat "$_bi_err" >&2
        fus_die 8 "$5: rauc info rejected the bundle (exit $_bi_rc)"
    fi
    fus_identity_from_shell "$_bi_out"
}

fus_manifest_begin() { # fus_manifest_begin <compat> <version> <description> <build> <format> <hook-filename> [bundle-hook-verb]
    # The input manifest, word for word what the recipe writes -- and no
    # sha256/size lines: rauc bundle computes those into the manifest INSIDE
    # the bundle, which is why acceptance compares `rauc info`, never this
    # input file.
    # The seventh argument is the BUNDLE-level hook verb, a separate thing
    # from the hook FILE named by the sixth: the app bundle needs
    # `hooks=install-check` so its own install-check hook REPLACES rauc's
    # default compatible check (which would reject the -appfs suffix outright,
    # because rauc compares the manifest compatible to the device's for exact
    # equality). Absent or empty reproduces the firmware door's output
    # unchanged -- which is why the fw call sites stay at six arguments and
    # `${7:-}` is read, never a bare $7 under `set -u`.
    printf '[update]\ncompatible=%s\nversion=%s\ndescription=%s\nbuild=%s\n' \
        "$1" "$2" "$3" "$4"
    printf '\n[bundle]\nformat=%s\n' "$5"
    printf '\n[hooks]\nfilename=%s\n' "$6"
    [ -z "${7:-}" ] || printf 'hooks=%s\n' "$7"
}

fus_verity_sidecars() { # fus_verity_sidecars <squashfs> <cert> <key> <veritysetup> <openssl> <sha256sum> <errlog>
    # The app payload's three dm-verity sidecars, reproducing
    # fus-app-container.bbclass's steps 2 and 3 and nothing else.
    #
    # Salt and uuid are DERIVED from the already-packed image's own sha256,
    # never random: that is the whole reproducibility property -- the same
    # bytes in yield the same three files out, on any host. The uuid is that
    # digest sliced 8-4-4-4-12, the same expression the reference uses.
    #
    # The names are IMAGE-KEYED (<image>.verity, <image>.roothash,
    # <image>.roothash.p7s) and that is a device contract, not a local
    # convention: fus-app-container-runtime's mount verb looks up "$img.verity"
    # for the renamed image path, so a stem-keyed name would be found by
    # nothing. Writing them beside the image is therefore not a copy step --
    # the caller packs straight into the content directory and the sidecars
    # land there by construction.
    #
    # Every step's output is captured and only passed through on failure: a
    # command line carrying --inkey/-signer must never reach a log. A step
    # that exits 0 without writing its file is treated exactly like a failure
    # (7): a bundle missing a sidecar installs and then fails to mount on the
    # device, which is the worst place to find out.
    # Results land in FUS_VERITY_* instead of on stdout: a command
    # substitution would run the fus_die calls below in a subshell and the
    # caller would sail past a refused build.
    _vs_img=$1; _vs_cert=$2; _vs_key=$3
    _vs_veritysetup=$4; _vs_openssl=$5; _vs_sha=$6; _vs_err=$7

    "$_vs_sha" "$_vs_img" > "$_vs_err.sha" 2>"$_vs_err"
    _vs_rc=$?
    if [ "$_vs_rc" -ne 0 ]; then
        cat "$_vs_err" >&2
        fus_die 7 "sidecars: cannot hash the packed payload (exit $_vs_rc)"
    fi
    _vs_salt=$(sed -n 1p "$_vs_err.sha")
    _vs_salt=${_vs_salt%% *}
    # A 64-hex digest or nothing: a truncated or reformatted digest would
    # otherwise become a salt that no rebuild can reproduce, and the failure
    # would only surface as a mismatching root hash on the device.
    case "$_vs_salt" in
    ????????????????????????????????????????????????????????????????) : ;;
    *) fus_die 7 "sidecars: the payload digest is not a 64-character hash: '$_vs_salt'" ;;
    esac
    case "$_vs_salt" in
    *[!0-9a-f]*) fus_die 7 "sidecars: the payload digest is not lower-case hex: '$_vs_salt'" ;;
    esac
    _vs_uuid=$(printf '%s' "$_vs_salt" | \
        sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12}).*/\1-\2-\3-\4-\5/')
    case "$_vs_uuid" in
    ????????-????-????-????-????????????) : ;;
    *) fus_die 7 "sidecars: cannot derive the verity uuid from the payload digest" ;;
    esac

    "$_vs_veritysetup" format "$_vs_img" "$_vs_img.verity" \
        --salt="$_vs_salt" --uuid="$_vs_uuid" \
        --root-hash-file="$_vs_img.roothash" >"$_vs_err" 2>&1
    _vs_rc=$?
    if [ "$_vs_rc" -ne 0 ]; then
        cat "$_vs_err" >&2
        fus_die 7 "sidecars: veritysetup format failed (exit $_vs_rc)"
    fi
    [ -f "$_vs_img.verity" ] && [ -s "$_vs_img.verity" ] || fus_die 7 \
        "sidecars: veritysetup exited 0 but wrote no verity hash tree"
    [ -f "$_vs_img.roothash" ] && [ -s "$_vs_img.roothash" ] || fus_die 7 \
        "sidecars: veritysetup exited 0 but wrote no roothash file"

    "$_vs_openssl" smime -sign -noattr -binary \
        -in "$_vs_img.roothash" -inkey "$_vs_key" -signer "$_vs_cert" \
        -outform der -out "$_vs_img.roothash.p7s" >"$_vs_err" 2>&1
    _vs_rc=$?
    if [ "$_vs_rc" -ne 0 ]; then
        cat "$_vs_err" >&2
        fus_die 7 "sidecars: openssl could not sign the root hash (exit $_vs_rc)"
    fi
    [ -f "$_vs_img.roothash.p7s" ] && [ -s "$_vs_img.roothash.p7s" ] || fus_die 7 \
        "sidecars: openssl exited 0 but wrote no roothash.p7s signature"

    # The root hash gets the same shape gate as the salt: it is the value the
    # device checks the mounted image against, and an empty or reformatted one
    # would travel into the build evidence as a convincing-looking blank.
    _vs_root=$(sed -n 1p "$_vs_img.roothash")
    case "$_vs_root" in
    ????????????????????????????????????????????????????????????????) : ;;
    *) fus_die 7 "sidecars: the verity root hash is not a 64-character hash: '$_vs_root'" ;;
    esac
    case "$_vs_root" in
    *[!0-9a-f]*) fus_die 7 "sidecars: the verity root hash is not lower-case hex: '$_vs_root'" ;;
    esac
    # shellcheck disable=SC2034  # read by the sourcing tool, as FUS_WORKDIR is
    FUS_VERITY_SALT=$_vs_salt
    # shellcheck disable=SC2034
    FUS_VERITY_UUID=$_vs_uuid
    # shellcheck disable=SC2034
    FUS_VERITY_ROOTHASH=$_vs_root
}

fus_manifest_image() { # fus_manifest_image <slot-class> <filename> <hook>
    printf '\n[image.%s]\nfilename=%s\nhooks=%s\n' "$1" "$2" "$3"
}

fus_install_hook() { # fus_install_hook <source> <dest> <app-img-dir>
    # Stages the hook: token substitution as the recipe does it, then the
    # executable mode the measured bundles carry (0744).
    [ -f "$1" ] && [ -r "$1" ] || fus_die 5 "hook: not a readable file: $1"
    # '|' is the delimiter; '&' and '\' are sed replacement-string metacharacters
    # (whole-match insert, escape introducer) -- any of the three would corrupt
    # the substitution rather than just fail to apply.
    case "$3" in
    *\|*|*\&*|*\\*) fus_die 2 "app image dir must not contain '|', '&' or '\\'" ;;
    esac
    sed "s|@@FUS_APP_IMG_DIR@@|$3|g" "$1" > "$2" || fus_die 5 "hook: cannot stage the hook"
    chmod 0744 "$2" || fus_die 5 "hook: cannot set the hook mode"
}

fus_rauc_bundle() { # fus_rauc_bundle <content-dir> <dest> <rauc> <mksquashfs> <cert> <key> <errlog>
    # The resolved mksquashfs's directory is put FIRST on PATH so rauc's own
    # internal mksquashfs call hits the same binary the preflight resolved.
    # Deliberately NO --signing-keyring: rauc bundle's built-in verification
    # runs under the default certificate purpose and rejects the codeSigning-
    # only leaf (measured: "unsuitable certificate purpose"); whether a --conf
    # reaches the bundle verb differs across the measured window. The caller's
    # mandatory self-verification checks the same property one step later,
    # under the device rules.
    # rauc's output is captured and passed through on failure -- never echoed
    # as a command line, which would carry the cert/key arguments into logs.
    PATH="${4%/*}:$PATH" "$3" bundle --cert="$5" --key="$6" "$1" "$2" >"$7" 2>&1
    _rb_rc=$?
    if [ "$_rb_rc" -ne 0 ]; then
        cat "$7" >&2
        fus_die 7 "bundle: rauc bundle failed (exit $_rb_rc)"
    fi
}

fus_publish() { # fus_publish <tmp-file> <final-path>
    # Never overwrites: a silently replaced release artifact is the worst
    # possible outcome, so an existing target is exit 2. The caller prechecks
    # the same path before doing any work; this is the last line of defense.
    [ ! -e "$2" ] || fus_die 2 "artifact already exists, not overwriting: $2"
    mv "$1" "$2" || fus_die 2 "cannot publish: $2"
}

fus_symlink_flip() { # fus_symlink_flip <target-basename> <link-path>
    # The unstamped "latest" pointer. Built aside and moved into place, so a
    # parallel reader sees the old or the new target, never none.
    _sf_tmp="$2.tmp.$$"
    ln -s "$1" "$_sf_tmp" || fus_die 2 "cannot prepare the symlink: $2"
    mv "$_sf_tmp" "$2" || { rm -f "$_sf_tmp"; fus_die 2 "cannot place the symlink: $2"; }
}
