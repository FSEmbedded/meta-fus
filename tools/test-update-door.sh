#!/bin/sh
# Run the update door's contract tests against the sources in this layer.
#
# The two gates live with the recipe that owns the library, and the recipe's
# do_compile runs what its own work directory holds. The boot guard belongs to
# a different recipe, so the full set only comes together here, at layer level:
# same files, all three sources, no build needed. Seconds, no container, no
# board -- the runtime suite keeps only what needs a kernel.
set -eu

here=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
core="$here/meta-fus-bsp/recipes-core"

confirm="$core/fus-update-confirm/files/fus-update-confirm"
lib="$core/fus-update-confirm/files/pending-state.sh"
runtime="$core/fus-app-container-runtime/files/fus-app-container-runtime"

for f in "$confirm" "$lib" "$runtime"; do
    [ -f "$f" ] || { echo "test-update-door: missing $f" >&2; exit 1; }
done

sh "$core/fus-update-confirm/files/test-pending-state.sh" "$lib"
sh "$core/fus-update-confirm/files/test-update-confirm.sh" "$confirm" "$lib" "$runtime"
