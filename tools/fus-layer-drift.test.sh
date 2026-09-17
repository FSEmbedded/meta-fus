#!/bin/sh
# fus-layer-drift.test.sh -- the drift gate between this tool set and the layer.
#
# fus-bundle-lib.sh carries the layer's functional constants a SECOND time, as
# defaults, so the tools work without a build system. Two producers of one
# truth drift silently; this suite is the recurring measurement that says so.
# It is not a one-off: it runs in the hermetic suite and, from CI track A, on
# every push.
#
# It reads the layer, it never parses it the way bitbake would. Each pair
# names ONE syntactic form -- plain assignment, :override, [varflag] or
# python setVarFlag -- and two hits of that form for one name is a FAILURE,
# not "the first one wins": RAUC_SLOT_appfs[hooks] genuinely appears twice in
# one file (post-install for slot mode, install for container), and picking
# the wrong one builds a permanent false alarm.
#
# Two blind spots, named rather than hidden:
#   - the extractor reads the setVarFlag LITERAL, not the `if
#     d.getVar('FUS_UPDATE_APP_MODE') == 'container'` condition above it. Move
#     that condition and this gate stays green.
#   - `-noappend` comes from poky's oe_mksquashfs, not from the layer, so the
#     gate compares the layer's share of the argument list and takes that one
#     flag on trust.
#
# SKIP only when the layer is not there at all (the tool set was copied away).
# A layer that IS there and misses a file or a key is drift, and drift is FAIL.
set -u

DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck disable=SC1091
. "$DIR/fus-test-lib.sh"
fus_test_init
fail=0

SDK="$DIR/../meta-fus-sdk"
[ -d "$SDK" ] || skip "layer not present (no meta-fus-sdk beside the tool set) -- nothing to compare against"

BUNDLES="$SDK/recipes-core/bundles"
FEATURES="$SDK/conf/distro/include/fus-update-features.inc"
LAYOUT="$SDK/conf/include/fus-update-layout.inc"
COMMON="$BUNDLES/fus-bundle-common.inc"
APPSLOT="$BUNDLES/fus-app-slot.inc"
APPBUNDLE="$BUNDLES/fus-app-bundle.bb"
FWBUNDLE="$BUNDLES/fus-fw-bundle.bb"
HOOK="$BUNDLES/files/install-check"
UPDCLASS="$SDK/classes-recipe/fus-update.bbclass"
APPCLASS="$SDK/classes-recipe/fus-app-container.bbclass"
SELFCHECK="$SDK/classes-recipe/fus-selfcheck.bbclass"
SYSCONF="$SDK/recipes-core/rauc/files/system.conf.in"

# --- reading the two sides -------------------------------------------------

lib_default() { # lib_default <NAME> -> the DEFAULT, never an inherited override
    # env -i, because every constant is ${X:-default}: sourcing the library in
    # this suite's own environment would compare a runner's FUS_* export
    # against the layer and call that agreement.
    env -i PATH="$PATH" sh -c '
        . "$1" || exit 1
        eval "printf %s\\\\n \"\${$2}\""
    ' sh "$DIR/fus-bundle-lib.sh" "$1"
}

# Every extractor prints either the value or !!<reason>; `pair` turns the
# marker into a named FAIL. An absent key is a reason, never an empty string
# that would compare clean against another empty string.
bb_plain() { # bb_plain <file> <VAR>   -- VAR = / ?= / ??= "value"
    _f=$1; _v=$2
    [ -f "$_f" ] || { printf '!!no such layer file: %s\n' "${_f##*/}"; return; }
    _n=$(LC_ALL=C grep -cE "^${_v}[[:space:]]*(\?\?=|\?=|=)[[:space:]]*\"" "$_f")
    [ "$_n" -eq 1 ] || {
        printf '!!%s: %s plain assignments of %s (want exactly 1)\n' "${_f##*/}" "$_n" "$_v"; return; }
    LC_ALL=C sed -n -E "s/^${_v}[[:space:]]*(\?\?=|\?=|=)[[:space:]]*\"(.*)\"[[:space:]]*\$/\\2/p" "$_f"
}

bb_flag() { # bb_flag <file> <VAR> <flag>   -- VAR[flag] = "value"
    _f=$1; _v=$2; _g=$3
    [ -f "$_f" ] || { printf '!!no such layer file: %s\n' "${_f##*/}"; return; }
    _n=$(LC_ALL=C grep -cE "^${_v}\[${_g}\][[:space:]]*=[[:space:]]*\"" "$_f")
    [ "$_n" -eq 1 ] || {
        printf '!!%s: %s [%s] assignments of %s (want exactly 1)\n' "${_f##*/}" "$_n" "$_g" "$_v"; return; }
    LC_ALL=C sed -n -E "s/^${_v}\[${_g}\][[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*\$/\\1/p" "$_f"
}

bb_setflag() { # bb_setflag <file> <VAR> <flag>  -- d.setVarFlag('VAR','flag','value')
    _f=$1; _v=$2; _g=$3
    [ -f "$_f" ] || { printf '!!no such layer file: %s\n' "${_f##*/}"; return; }
    _n=$(LC_ALL=C grep -cE "setVarFlag\('${_v}', *'${_g}', *'" "$_f")
    [ "$_n" -eq 1 ] || {
        printf '!!%s: %s setVarFlag(%s,%s) calls with a literal (want exactly 1)\n' \
            "${_f##*/}" "$_n" "$_v" "$_g"; return; }
    LC_ALL=C sed -n -E "s/.*setVarFlag\('${_v}', *'${_g}', *'([^']*)'\).*/\\1/p" "$_f"
}

bb_resolve() { # bb_resolve <file> <value>  -- expand ${VAR} against the SAME file
    _rf=$1; _rv=$2; _ri=0
    case "$_rv" in '!!'*) printf '%s\n' "$_rv"; return ;; esac
    while : ; do
        case "$_rv" in *'${'*) ;; *) printf '%s\n' "$_rv"; return ;; esac
        _ri=$((_ri + 1))
        [ "$_ri" -le 8 ] || { printf '!!still unresolved after 8 rounds: %s\n' "$_rv"; return; }
        _rn=${_rv#*\$\{}; _rn=${_rn%%\}*}
        _rs=$(bb_plain "$_rf" "$_rn")
        case "$_rs" in '!!'*) printf '!!%s (while expanding ${%s})\n' "${_rs#\!\!}" "$_rn"; return ;; esac
        [ -n "$_rs" ] || { printf '!!${%s} expands to nothing in %s\n' "$_rn" "${_rf##*/}"; return; }
        # First occurrence only; the loop handles the rest. No sed here: the
        # values are paths and argument lists, and building a regex out of
        # them is how an extractor starts guessing.
        _rv="${_rv%%\$\{*}$_rs${_rv#*\}}"
    done
}

absent() { # absent <desc> <file> <extended-regex>  -- the key must NOT exist
    _n=$(LC_ALL=C grep -cE "$3" "$2" 2>/dev/null)
    check "$1" 0 "${_n:-0}"
}

pair() { # pair <desc> <layer-side> <library-side>
    case "$2" in '!!'*) echo "FAIL $1: ${2#\!\!}"; fail=1; return ;; esac
    case "$3" in '!!'*) echo "FAIL $1: ${3#\!\!}"; fail=1; return ;; esac
    [ -n "$2" ] || { echo "FAIL $1: the layer side is empty"; fail=1; return; }
    [ -n "$3" ] || { echo "FAIL $1: the library side is empty"; fail=1; return; }
    check "$1" "$2" "$3"
}

sorted_words() { # sorted_words <string> -> its words, sorted, space-separated
    # shellcheck disable=SC2086  # word splitting is the point
    printf '%s\n' $1 | LC_ALL=C sort | tr '\n' ' '
}

drop_word() { # drop_word <string> <word>
    _dw=''
    # shellcheck disable=SC2086
    for _d in $1; do [ "$_d" = "$2" ] || _dw="$_dw $_d"; done
    printf '%s\n' "${_dw# }"
}

echo "# --- group A: recipe and class values (the bundle as it is built) ---"

# ${MACHINE} is assigned nowhere in the layer, so the general "an unresolved
# ${ is drift" rule cannot apply to this one line. Named exception, checked
# in the only way that carries meaning: prefix plus exactly that placeholder.
COMPAT_RAW=$(bb_plain "$FEATURES" RAUC_BUNDLE_COMPATIBLE)
pair "compatible prefix (features.inc)" "$(lib_default FUS_COMPAT_PREFIX)\${MACHINE}" "$COMPAT_RAW"

pair "bundle format (fus-bundle-common.inc)" \
    "$(bb_plain "$COMMON" RAUC_BUNDLE_FORMAT)" "$(lib_default FUS_BUNDLE_FORMAT)"

# The listed slot, not the inert RAUC_SLOT_rootfs definition: a definition
# that no recipe lists produces no image section at all.
FW_SLOTS=$(bb_plain "$FWBUNDLE" RAUC_BUNDLE_SLOTS)
case "$FW_SLOTS" in
'!!'*) echo "FAIL fw slot class: ${FW_SLOTS#\!\!}"; fail=1 ;;
*)     pair "fw slot class (fus-fw-bundle.bb RAUC_BUNDLE_SLOTS)" \
           "${FW_SLOTS%% *}" "$(lib_default FUS_FW_SLOT_CLASS)" ;;
esac

pair "app slot class (fus-app-slot.inc)" \
    "$(bb_plain "$APPSLOT" FUS_BUNDLE_APP_SLOT)" "$(lib_default FUS_APP_SLOT_CLASS)"

# A [name] varflag would rename the manifest section and this whole group
# would keep comparing the variable name instead of what rauc writes.
absent "no RAUC_SLOT_rootfs[name] renames the fw section" "$COMMON" '^RAUC_SLOT_rootfs\[name\]'
absent "no RAUC_SLOT_appfs[name] renames the app section" "$APPSLOT" '^RAUC_SLOT_appfs\[name\]'

pair "fw image hook (fus-bundle-common.inc)" \
    "$(bb_flag "$COMMON" RAUC_SLOT_rootfs hooks)" "$(lib_default FUS_FW_IMAGE_HOOK)"

# One producer per mode, two different syntactic forms. Container's comes from
# anonymous python and has a library twin. Slot mode's bracket assignment is
# pinned against a literal on purpose: FUS_FW_IMAGE_HOOK carries the same value
# today but states the FW slot's fact, and pinning the app slot to it would let
# a genuine divergence between the two slots pass as agreement. What this line
# guards is the hook's appfs arm, which stops running if the value moves.
pair "app image hook, container mode (fus-app-slot.inc setVarFlag)" \
    "$(bb_setflag "$APPSLOT" RAUC_SLOT_appfs hooks)" "$(lib_default FUS_APP_IMAGE_HOOK)"
pair "app image hook, slot mode (fus-app-slot.inc bracket)" \
    "$(bb_flag "$APPSLOT" RAUC_SLOT_appfs hooks)" "post-install"

pair "app bundle hook (fus-app-bundle.bb setVarFlag)" \
    "$(bb_setflag "$APPBUNDLE" RAUC_BUNDLE_HOOKS hooks)" "$(lib_default FUS_APP_BUNDLE_HOOK)"

# The hook FILE name, a separate thing from the hook VERB above: both tools
# write it into the manifest and name the staged file after it.
HOOK_FILE=$(bb_flag "$COMMON" RAUC_BUNDLE_HOOKS file)
pair "hook file name (fus-bundle-common.inc)" "$HOOK_FILE" "install-check"
case "$HOOK_FILE" in
'!!'*) : ;;
*)
    # Checked at the two places that decide, not at the fus_manifest_begin
    # call: that one is a multi-line invocation, and a line-wise grep against
    # it is exactly the false green this project has collected before. What
    # matters is the name the hook is STAGED under (it becomes the bundle
    # entry) and the default the tool looks for beside itself.
    for _t in fus-mk-fw-bundle.sh fus-mk-app-bundle.sh; do
        has "$_t stages the hook under the layer's name" \
            "\$content/$HOOK_FILE" "$DIR/$_t"
        has "$_t defaults to the layer's hook name beside itself" \
            "\$SCRIPT_DIR/$HOOK_FILE" "$DIR/$_t"
    done
    ;;
esac

pair "app payload name (features.inc)" \
    "$(bb_resolve "$FEATURES" "$(bb_plain "$FEATURES" FUS_UPDATE_APP_CONTAINER_IMAGE)")" \
    "$(lib_default FUS_APP_PAYLOAD_NAME)"

pair "rootfs slot size (fus-update-layout.inc)" \
    "$(bb_plain "$LAYOUT" FUS_UPDATE_SIZE_ROOT_MIB)" "$(lib_default FUS_SIZE_ROOT_MIB)"

# Argument lists compare as WORD SETS: the layer writes -noappend -all-root
# ${EXTRA}, the library ${ARGS} -all-root. Same set, different order, and the
# order means nothing to mksquashfs -- but a missing flag must still fail.
FW_LAYER_ARGS=$(bb_resolve "$UPDCLASS" "$(bb_plain "$UPDCLASS" 'EXTRA_IMAGECMD:squashfs')")
case "$FW_LAYER_ARGS" in
'!!'*) echo "FAIL fw mksquashfs arguments: ${FW_LAYER_ARGS#\!\!}"; fail=1 ;;
*)
    # -noappend is poky's (oe_mksquashfs), not the layer's: compared out on
    # the library side rather than invented on the layer side.
    pair "fw mksquashfs arguments (fus-update.bbclass, minus poky's -noappend)" \
        "$(sorted_words "$FW_LAYER_ARGS")" \
        "$(sorted_words "$(drop_word "$(lib_default FUS_MKSQUASHFS_ARGS)" -noappend)")"
    ;;
esac

# The app door has its own SQUASHFS_* pair in its own class; taking the
# firmware one here would measure the wrong producer.
APP_LAYER_EXTRA=$(bb_resolve "$APPCLASS" "$(bb_plain "$APPCLASS" SQUASHFS_EXTRA_IMAGECMD)")
APP_MKSQ_LINE=$(LC_ALL=C grep -cE '^[[:space:]]*mksquashfs .*-noappend -all-root \$\{SQUASHFS_EXTRA_IMAGECMD\}' "$APPCLASS")
check "the app class still packs -noappend -all-root plus its own arguments" 1 "$APP_MKSQ_LINE"
case "$APP_LAYER_EXTRA" in
'!!'*) echo "FAIL app mksquashfs arguments: ${APP_LAYER_EXTRA#\!\!}"; fail=1 ;;
*)
    pair "app mksquashfs arguments (fus-app-container.bbclass)" \
        "$(sorted_words "-noappend -all-root $APP_LAYER_EXTRA")" \
        "$(sorted_words "$(lib_default FUS_APP_MKSQUASHFS_ARGS)")"
    ;;
esac

# meta-rauc takes the description from SUMMARY, but only with ??=, so a
# recipe-level RAUC_BUNDLE_DESCRIPTION would quietly retire this anchor.
pair "fw bundle description (fus-fw-bundle.bb SUMMARY)" \
    "$(bb_plain "$FWBUNDLE" SUMMARY)" "$(lib_default FUS_FW_DESCRIPTION)"
pair "app bundle description (fus-app-bundle.bb SUMMARY)" \
    "$(bb_plain "$APPBUNDLE" SUMMARY)" "$(lib_default FUS_APP_DESCRIPTION)"
for _f in "$FWBUNDLE" "$APPBUNDLE" "$COMMON"; do
    absent "no RAUC_BUNDLE_DESCRIPTION overrides SUMMARY in ${_f##*/}" "$_f" \
        '^RAUC_BUNDLE_DESCRIPTION'
done

# The tool's app_payload_contract is a declared mirror of the layer's
# selfcheck. A fifth guard in the layer would leave the tool accepting
# payloads the build rejects, so the COUNT is part of the comparison.
LAYER_FN="$TMP/selfcheck.fn"; TOOL_FN="$TMP/contract.fn"
LC_ALL=C sed -n '/^fus_selfcheck_app_payload() {/,/^}/p' "$SELFCHECK" > "$LAYER_FN"
LC_ALL=C sed -n '/^app_payload_contract() {/,/^}/p' "$DIR/fus-mk-app-bundle.sh" > "$TOOL_FN"
check "the layer's app selfcheck is still findable" 1 \
    "$([ -s "$LAYER_FN" ] && echo 1 || echo 0)"
check "the tool's app contract is still findable" 1 \
    "$([ -s "$TOOL_FN" ] && echo 1 || echo 0)"
pair "app payload contract: number of guards" \
    "$(LC_ALL=C grep -c 'bbfatal' "$LAYER_FN")" \
    "$(LC_ALL=C grep -c 'fus_die 5' "$TOOL_FN")"
for _req in app_version app-release IMAGE_ID; do
    has "app payload contract still requires $_req (layer)" "$_req" "$LAYER_FN"
    has "app payload contract still requires $_req (tool)"  "$_req" "$TOOL_FN"
done

echo "# --- group B: device values (what decides on the board) ---"

# The literal twin of the constant is the device hook's fallback lookup, not
# any recipe variable: the name rauc writes into the bundle is built from the
# slot name plus machine and name suffixes, so a glob compared against
# "${FUS_BUNDLE_ROOTFS_IMAGE}.squashfs" would be wrong in both directions.
FW_GLOB=$(lib_default FUS_FW_PAYLOAD_GLOB)
has "fw payload glob is the one the device hook uses" "/$FW_GLOB" "$HOOK"

# The app side of the same pair, and it has no library constant: the hook's
# appfs fallback is built from the slot-mode image name, so a rename in the
# recipe stops it matching -- silently, and only in app=slot.
APP_IMG=$(bb_plain "$APPSLOT" RAUC_SLOT_appfs)
case "$APP_IMG" in
'!!'*) echo "FAIL app payload glob: ${APP_IMG#\!\!}"; fail=1 ;;
*)     has "app payload glob is the one the device hook uses (app=slot)" \
           "/$APP_IMG-*.squashfs" "$HOOK" ;;
esac

# The acceptor on the device, not the producer in the recipe: if those two
# ever disagree, the gate must follow the side that rejects the install.
APP_SUFFIX=$(lib_default FUS_APP_COMPAT_SUFFIX)
has "app compatible suffix is the one the device hook accepts" \
    "\${RAUC_SYSTEM_COMPATIBLE:-}$APP_SUFFIX" "$HOOK"
pair "app compatible suffix (producer side, fus-app-bundle.bb)" \
    "$(bb_plain "$APPBUNDLE" 'RAUC_BUNDLE_COMPATIBLE:append:app-container')" "$APP_SUFFIX"

# Rename this placeholder in the layer and the tool substitutes nothing --
# the raw token would travel to the device inside the hook.
has "the hook token the layer substitutes"  '@@FUS_APP_IMG_DIR@@' "$COMMON"
has "the hook token the hook itself carries" '@@FUS_APP_IMG_DIR@@' "$HOOK"
has "the hook token the tool substitutes"    '@@FUS_APP_IMG_DIR@@' "$DIR/fus-bundle-lib.sh"

pair "app image directory (fus-update-layout.inc)" \
    "$(bb_resolve "$LAYOUT" "$(bb_plain "$LAYOUT" FUS_UPDATE_APP_IMG_DIR)")" \
    "$(lib_default FUS_APP_IMG_DIR)"

# The sharpest pair in the file: lose check-purpose=codesign on the device and
# the tools would keep verifying under a rule the board no longer runs -- the
# mandatory self-verification would become ceremony with nothing turning red.
for _rule in 'check-purpose=codesign' 'use-bundle-signing-time=true'; do
    has "device system.conf still sets $_rule" "$_rule" "$SYSCONF"
    has "the generated verify conf sets $_rule" "$_rule" "$DIR/fus-bundle-lib.sh"
done
has "device system.conf still accepts the bundle format" \
    "bundle-formats=$(lib_default FUS_BUNDLE_FORMAT)" "$SYSCONF"

echo "# --- the gate proves itself: one mutation per pair, and only that pair ---"
# A single mutation in one of nine files would prove one pair and leave the
# rest unmeasured -- including any extractor that silently hands back the
# library's own value. Each mutation is checked to be seen AND to be the only
# thing seen.
# The extractors take the file FIRST; these wrappers put it last so one
# mutation driver can carry any of them.
x_plain()   { bb_plain   "$2" "$1"; }        # x_plain <VAR> <file>
x_flag()    { bb_flag    "$3" "$1" "$2"; }   # x_flag <VAR> <flag> <file>
x_setflag() { bb_setflag "$3" "$1" "$2"; }   # x_setflag <VAR> <flag> <file>

mutate_seen() { # mutate_seen <desc> <file> <sed-expr> <extractor> [args...]
    _md=$1; _mf=$2; _me=$3; shift 3
    # The original is read through the SAME extractor, so this also asserts
    # the extractor works on the pristine file before anything is mutated.
    _morig=$("$@" "$_mf")
    case "$_morig" in
    ''|'!!'*) echo "FAIL $_md: the extractor cannot read the pristine file (${_morig#\!\!})"; fail=1; return ;;
    esac
    cp "$_mf" "$TMP/mut" || { echo "FAIL $_md: cannot copy ${_mf##*/}"; fail=1; return; }
    LC_ALL=C sed -i -E "$_me" "$TMP/mut" || { echo "FAIL $_md: sed failed"; fail=1; return; }
    if cmp -s "$_mf" "$TMP/mut"; then
        echo "FAIL $_md: the mutation changed nothing -- the anchor line moved"
        fail=1
        return
    fi
    if [ "$("$@" "$TMP/mut")" = "$_morig" ]; then
        echo "FAIL $_md: the extractor returned the original value out of a mutated file"
        fail=1
    else
        echo "ok   $_md"
    fi
}

# Each probe replaces WHATEVER value is there, never a literal one: a probe
# pinned to today's value would answer "the anchor line moved" at exactly the
# moment the pair it guards has genuinely drifted, adding a second, misleading
# failure to a real finding.
mutate_seen "mutating the bundle format is seen" "$COMMON" \
    's/^(RAUC_BUNDLE_FORMAT[[:space:]]*=[[:space:]]*)".*"/\1"DRIFT-PROBE"/' \
    x_plain RAUC_BUNDLE_FORMAT
# ... and it is seen ONLY there: a neighbour in the same file must be
# untouched, or one mutation would be indistinguishable from a broken parser.
check "mutating one anchor leaves its file-neighbour alone" \
    "$(bb_flag "$COMMON" RAUC_SLOT_rootfs hooks)" \
    "$(bb_flag "$TMP/mut" RAUC_SLOT_rootfs hooks)"

mutate_seen "mutating the fw image hook is seen" "$COMMON" \
    's/^(RAUC_SLOT_rootfs\[hooks\][[:space:]]*=[[:space:]]*)".*"/\1"DRIFT-PROBE"/' \
    x_flag RAUC_SLOT_rootfs hooks
mutate_seen "mutating the app image hook is seen" "$APPSLOT" \
    "s/(setVarFlag\('RAUC_SLOT_appfs', 'hooks', ')[^']*/\1DRIFT-PROBE/" \
    x_setflag RAUC_SLOT_appfs hooks
mutate_seen "mutating the slot size is seen" "$LAYOUT" \
    's/^(FUS_UPDATE_SIZE_ROOT_MIB[[:space:]]*\?=[[:space:]]*)"256"/\1"512"/' \
    x_plain FUS_UPDATE_SIZE_ROOT_MIB
mutate_seen "mutating the slot-mode app image hook is seen" "$APPSLOT" \
    's/^(RAUC_SLOT_appfs\[hooks\][[:space:]]*=[[:space:]]*)".*"/\1"DRIFT-PROBE"/' \
    x_flag RAUC_SLOT_appfs hooks
mutate_seen "mutating the slot-mode app image name is seen" "$APPSLOT" \
    's/^(RAUC_SLOT_appfs[[:space:]]*=[[:space:]]*)".*"/\1"drift-probe-image"/' \
    x_plain RAUC_SLOT_appfs
mutate_seen "mutating the app payload name is seen" "$FEATURES" \
    's/^(FUS_APP_CONTAINER_NAME[[:space:]]*\?=[[:space:]]*)".*"/\1"other-name"/' \
    x_plain FUS_APP_CONTAINER_NAME
mutate_seen "mutating the fw bundle description is seen" "$FWBUNDLE" \
    's/^(SUMMARY = ")/\1DRIFTED /' \
    x_plain SUMMARY

# A second assignment of the same form must be refused, not silently resolved
# to the first: that is the RAUC_SLOT_appfs[hooks] hazard in general form.
cp "$COMMON" "$TMP/dup" && printf '\nRAUC_BUNDLE_FORMAT = "plain"\n' >> "$TMP/dup"
case "$(bb_plain "$TMP/dup" RAUC_BUNDLE_FORMAT)" in
'!!'*) echo "ok   a second assignment of the same form is refused, not resolved" ;;
*)     echo "FAIL a second assignment of the same form was silently resolved"; fail=1 ;;
esac

# An anchor that vanished must read as drift, never as an empty value that
# would compare clean against another empty value.
LC_ALL=C grep -v '^RAUC_BUNDLE_FORMAT' "$COMMON" > "$TMP/gone"
case "$(bb_plain "$TMP/gone" RAUC_BUNDLE_FORMAT)" in
'!!'*) echo "ok   a vanished anchor reads as drift, not as an empty value" ;;
*)     echo "FAIL a vanished anchor did not read as drift"; fail=1 ;;
esac

# The library side is read with the environment emptied; prove that, or the
# whole suite could be measuring a runner's exports against the layer.
case "$(FUS_BUNDLE_FORMAT=squashed lib_default FUS_BUNDLE_FORMAT)" in
squashed) echo "FAIL the library side reads the caller's environment, not the default"; fail=1 ;;
'')       echo "FAIL the library side reads as empty"; fail=1 ;;
*)        echo "ok   the library side is read with the environment emptied" ;;
esac

echo "---"
if [ "$fail" = 0 ]; then echo "ALL PASS"; else echo "FAILURES"; fi
exit "$fail"
