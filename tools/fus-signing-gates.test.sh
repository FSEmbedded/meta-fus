#!/bin/sh
# Hermetic tests for the two build-time signing gates in fus-selfcheck.bbclass.
#
# The functions are BitBake shell. Extracted, given a bbfatal that exits, they
# run as plain sh -- the same trick the removable-medium suite uses for the unit
# guard. No BitBake, no bundle, no keys.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
CLASS="${FUS_SELFCHECK_CLASS:-$HERE/../meta-fus-sdk/classes-recipe/fus-selfcheck.bbclass}"
[ -f "$CLASS" ] || { echo "FAIL: $CLASS not found" >&2; exit 1; }

fails=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s: %s\n' "$1" "$2" >&2; fails=$((fails + 1)); }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# One runnable copy of both functions, with a bbfatal that stops the run and
# says what it said.
{
    printf 'bbfatal() { echo "$*" >&2; exit 1; }\n'
    sed -n '/^fus_selfcheck_signing_material()/,/^}$/p' "$CLASS"
    sed -n '/^fus_selfcheck_keyring_material()/,/^}$/p' "$CLASS"
    sed -n '/^fus_selfcheck_production_material()/,/^}$/p' "$CLASS"
    printf '"$@"\n'
} >"$T/gates.sh"

run() { sh "$T/gates.sh" "$@" >"$T/out" 2>&1; }

# A real file to stand in for material that is on disk.
mkdir -p "$T/certs/dev" "$T/certs/prod"
: >"$T/certs/dev/sign.key.pem"
: >"$T/certs/prod/sign.key.pem"

# --- the material gate ------------------------------------------------------
run fus_selfcheck_signing_material ctx "$T/certs/dev/sign.key.pem" \
    && ok "material: a file that exists passes" \
    || bad "material" "a present file was rejected: $(cat "$T/out")"

run fus_selfcheck_signing_material ctx "$T/certs/dev/absent.pem" \
    && bad "material" "a missing file passed" \
    || ok "material: a missing file stops the build"

# The finding this gate exists for: a key in a token has no path.
run fus_selfcheck_signing_material ctx "pkcs11:token=fus;object=sign;type=private" \
    && ok "material: a pkcs11 URI is not looked for on disk" \
    || bad "material" "a pkcs11 URI was treated as a path: $(cat "$T/out")"

# It must not be doing that by ignoring everything.
run fus_selfcheck_signing_material ctx "/nonexistent/pkcs11-lookalike.pem" \
    && bad "material" "a path with pkcs11 in its name passed" \
    || ok "material: only the URI scheme is exempt, not the word"

# --- the keyring gate -------------------------------------------------------
# The keyring is copied into the rootfs as a file, so the URI exemption above
# must not reach it.
run fus_selfcheck_keyring_material ctx "$T/certs/dev/ca.pem" \
    && bad "keyring" "a missing keyring passed" \
    || ok "keyring: a missing keyring stops the build"

: >"$T/certs/dev/ca.pem"
run fus_selfcheck_keyring_material ctx "$T/certs/dev/ca.pem" \
    && ok "keyring: a real file passes" \
    || bad "keyring" "a present keyring was rejected: $(cat "$T/out")"

# The message matters, not just the failure: without the URI refusal the run
# would still fail -- on the file test, because a URI is not a path -- and this
# case would pass for the wrong reason.
run fus_selfcheck_keyring_material ctx "pkcs11:token=fus;object=ca" \
    && bad "keyring" "a pkcs11 URI passed as the device keyring" \
    || case "$(cat "$T/out")" in
       *"cannot be a PKCS#11 URI"*)
           ok "keyring: a pkcs11 URI is refused for being one" ;;
       *)
           bad "keyring" "refused for the wrong reason: $(cat "$T/out")" ;;
       esac

# --- the production gate ----------------------------------------------------
run fus_selfcheck_production_material ctx prod "$T/certs/dev/sign.key.pem" \
    && bad "production" "a prod image signed with dev material passed" \
    || ok "production: prod plus dev material stops the build"

case "$(cat "$T/out")" in
*"declares FUS_UPDATE_CERT_VARIANT=prod"*) ok "production: the message names the cause" ;;
*) bad "production" "unhelpful message: $(cat "$T/out")" ;;
esac

run fus_selfcheck_production_material ctx prod "$T/certs/prod/sign.key.pem" \
    && ok "production: prod material passes" \
    || bad "production" "prod material was rejected: $(cat "$T/out")"

# A dev build is the normal case here and must not be gated at all.
run fus_selfcheck_production_material ctx dev "$T/certs/dev/sign.key.pem" \
    && ok "production: a dev build is not gated" \
    || bad "production" "a dev build was gated: $(cat "$T/out")"

# A variant this layer does not know must not read as "not production": the
# comparison is exact, so a near miss would wave dev material through a build
# that meant to be production -- and put the typo on the device as its label.
run fus_selfcheck_production_material ctx Prod "$T/certs/dev/sign.key.pem" \
    && bad "production" "an unknown variant disabled the gate in silence" \
    || case "$(cat "$T/out")" in
       *"not a variant this layer knows"*)
           ok "production: an unknown variant stops the build" ;;
       *)
           bad "production" "refused for the wrong reason: $(cat "$T/out")" ;;
       esac

if [ "$fails" -eq 0 ]; then
    echo "fus-signing-gates.test: ok"
    # The verdict line the CI loop reads. It has to be the LAST line: a run
    # that stops early must not look like a pass.
    echo "ALL PASS"
    exit 0
fi
echo "fus-signing-gates.test: $fails failure(s)" >&2
exit 1
