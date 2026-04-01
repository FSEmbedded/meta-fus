require linux-mainline-fus.inc

SRC_URI:append  = " \
	 file://0001-Add-F-S-device-trees.patch \
	 file://0003-Add-fus-version-of-pca963x-led-driver.patch \
	 file://0005-Improve-rtc-pcf85363-driver.patch \
"

SRC_URI:append:mx8-mainline-bsp = " \
	 file://0002-Improve-fsimx8mp-device-trees-for-mainline.patch \
	 file://0004-Add-gpio-switch-driver-for-usb-c.patch \
	 file://0006-Add-pwm-functionallity-to-pca953x-gpio-driver.patch \
	 file://0007-Add-support-for-the-EE0350ET-F-S-MIPI-display.patch \
	 file://0008-Fix-sgtl5000-i2c-codec-driver.patch \
	 file://0010-Improve-fsimx8mm-devicetees-for-mainline-support.patch \
	 file://0011-Hoftfix-for-tc35877-MIPI2LVDS-bridge.patch \
"

SRC_URI:append:mx8-mainline-bsp = " file://fsimx8_defconfig "

SRCBRANCH="linux-6.12.y"
SRCREV = "c2d104a355013a14bcd73e31fb2c4bc21922115a"

# LINUX_VERSION define should match to the kernel version referenced by SRC_URI and
# should be updated once patchlevel is merged.
LINUX_VERSION = "6.12.79"

SCMVERSION = "n"
LOCALVERSION = "-fus-patched"
