# Copyright (C) 2020 F&S Elektronik Systeme GmbH
# Released under the MIT license (see COPYING.MIT for the terms)

require u-boot-fus.inc
require u-boot-fus-src-2024.04.inc

UBOOT_VERSION = "2024.04"
SRCBRANCH = "master"

CVE_STATUS[CVE-2024-42040] = "backported-patch: Fixed through \
41aafb5eb963c95d19ba4319049b0de8950737ee"
CVE_STATUS[CVE-2024-57254] = "backported-patch: Fixed through \
37269f3cbac6043cd52afd994c6528b861477e0c"
CVE_STATUS[CVE-2024-57255] = "backported-patch: Fixed through \
d118b6b0ad2743fc510f6771604135173c360680"
CVE_STATUS[CVE-2024-57256] = "backported-patch: Fixed through \
4380dbd879a8100f5e8c4bc2f1c263e599516089"
CVE_STATUS[CVE-2024-57257] = "backported-patch: Fixed through \
c94d15ba88b0e267d931a9441991b7f1dba5af76"
CVE_STATUS[CVE-2024-57258] = "backported-patch: Fixed through \
8fa7c4df1b5684cdc17e6ae4e80b61a6b43c4dca \
0420c0a6a4a09d7ea897a93b73c09077fb433426 \
234693a87930859b0c9a719cd33059faf483e769 "
CVE_STATUS[CVE-2024-57259] = "backported-patch: Fixed through \
1f34793295e4319421ec78df9de623517bbc4609"
CVE_STATUS[CVE-2026-33243] = "backported-patch: Fixed through \
ccff41df4a6a4470077fd220f153746613aa3a9f"
CVE_STATUS[CVE-2026-29009] = "backported-patch: Fixed through \
fd73df3824bf8ef3d6e316d3aae111c9b1fb387b"
CVE_STATUS[CVE-2026-29007] = "backported-patch: Fixed through \
d80d493a43a94511c3b1d2fc3792d4a3116a6133"
CVE_STATUS[CVE-2026-29008] = "backported-patch: Fixed through \
d80d493a43a94511c3b1d2fc3792d4a3116a6133"
CVE_STATUS[CVE-2026-46728] = "not-applicable-config: \
FIT signature verification is not used"
