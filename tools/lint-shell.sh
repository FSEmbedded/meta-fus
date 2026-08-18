#!/bin/sh
# static gate for this layer's POSIX-sh scripts: shellcheck in POSIX mode
# catches bug classes a bare syntax check cannot.
#
# scripts are discovered, not hand-listed: any git-tracked file with a
# #!/bin/sh shebang or a `# shellcheck shell=sh` directive (the convention
# for sourced, shebang-less scripts). bash scripts are deliberately
# excluded: checking them under -s sh would flag intentional bashisms.
set -u

cd "$(dirname "$0")/.." || exit 2

fail=0
count=0
git ls-files | while IFS= read -r f; do
    [ -f "$f" ] || continue
    case "$(head -c 200 "$f" 2>/dev/null | head -2)" in
        '#!/bin/sh'*) : ;;
        *'shellcheck shell=sh'*) : ;;
        *) continue ;;
    esac
    echo "$f"
done > "${TMPDIR:-/tmp}/lint-shell.$$"

while IFS= read -r f; do
    count=$((count + 1))
    # warning+: info/style hits are accepted idiom in these busybox-sh
    # scripts; regressions gate on warning-or-worse.
    shellcheck -s sh --severity=warning "$f" || fail=1
    sh -n "$f" || fail=1
done < "${TMPDIR:-/tmp}/lint-shell.$$"
rm -f "${TMPDIR:-/tmp}/lint-shell.$$"

if [ "$count" -eq 0 ]; then
    echo "lint-shell: discovered zero scripts -- the discovery filter itself is broken" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "lint-shell: OK ($count scripts)"
exit $fail
