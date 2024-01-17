# Firmware Sentinel 0.9 has some issues with the reset command. Because of this, a downgrade is required.
PV = "0.8"

LIC_FILES_CHKSUM = "file://COPYING;md5=5a0bf11f745e68024f37b4724a5364fe"
SRC_URI = "${FSL_MIRROR}/${BP}.bin;fsl-eula=true"
SRC_URI[sha256sum] = "1003d4c6773c153ea341911a74e25c249423644f70f3d8f8d085599e00770b3f"
SRC_URI[md5sum] = "be47a5e59c1192ee36246af97d5d1532"
