#!/bin/sh
# pins the process-exit contract between the fs-updater CLI and the exec
# backend: exit codes are type-encoded, and only 0 (firmware), 4
# (application), 8 (combined) and 48 (untyped raw bundle) mean a completed
# install. everything else must map to failure -- including other verb
# families' success codes (12 rollback, 16 commit, 50 apply) and 47
# (install still running past the CLI's no-progress watchdog).
set -u

driver="$1"
pass=0
fail=0

run_driver() {
    if [ -n "${2:-}" ]; then
        FAKE_FSUP_EXIT="$1" "$driver" "$2"
    else
        FAKE_FSUP_EXIT="$1" "$driver"
    fi
}

expect_success() {
    if run_driver "$1" "${2:-}"; then
        pass=$((pass + 1))
    else
        echo "FAIL: exit code $1 (${2:-default}) must map to install SUCCESS" >&2
        fail=$((fail + 1))
    fi
}

expect_failure() {
    if run_driver "$1" "${2:-}"; then
        echo "FAIL: exit code $1 (${2:-default}) must map to install FAILURE" >&2
        fail=$((fail + 1))
    else
        pass=$((pass + 1))
    fi
}

for c in 0 4 8 48; do
    expect_success "$c"
    expect_success "$c" --with-notify
done

for c in 1 2 3 5 6 7 9 10 11 12 16 17 20 24 26 27 34 46 47 49 50 52 61 66 67 99 124; do
    expect_failure "$c"
done

expect_failure signal
expect_failure 0 --with-auth

echo "backend exit-code contract: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
