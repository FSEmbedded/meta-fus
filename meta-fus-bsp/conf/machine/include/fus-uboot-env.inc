# Location of the U-Boot environment block per machine; the source for
# fw_env.config and for fus_selfcheck_fw_env.

# emmc-boot: boot0/boot1 hardware partitions; nand: MTD partition FUS_ENV_MTD_NAME.
FUS_ENV_MEDIUM   ?= "emmc-boot"

# FUS_ENV_OFFSETS has no default, an unlisted machine fails at build. One offset = single
# copy, two = redundant; equal offsets on emmc-boot = boot0 + boot1. NAND: partition-relative.

# Must equal CONFIG_ENV_SIZE; a wrong size or copy count fails every read.
FUS_ENV_SIZE     ?= "0x4000"

# eMMC sector size or NAND erase size; NSECT (NAND only) = erase blocks per copy.
FUS_ENV_SECT     ?= "0x200"
FUS_ENV_NSECT    ?= ""
FUS_ENV_MTD_NAME ?= "UBootEnv"

# nboot boards, eMMC boot: values read from the nboot-info "emmc-boot" node.
FUS_ENV_OFFSETS:fsimx8mp  = "0x40000 0x40000"
FUS_ENV_OFFSETS:fsimx8mm  = "0x0 0x0"
FUS_ENV_OFFSETS:fsimx8mn  = "0x40000 0x40000"
FUS_ENV_OFFSETS:fsimx8ulp = "0x3cc800 0x3cc800"
FUS_ENV_OFFSETS:fsimx91   = "0x3cc800 0x3cc800"
FUS_ENV_OFFSETS:fsimx93   = "0x3cc800 0x3cc800"

# NAND variants of fsimx8mm/8mn are not supported by the update layout.

# Defconfig-driven boards, single copy. Unverified on hardware; the build check compares with the defconfig.
FUS_ENV_OFFSETS:fsimx8x   = "0x200000"
FUS_ENV_SIZE:fsimx8x      = "0x2000"
FUS_ENV_OFFSETS:fsimx7ulp = "0x100000"
FUS_ENV_SIZE:fsimx7ulp    = "0x8000"

# NAND boards, single copy, two erase blocks reserved. Unverified on hardware.
FUS_ENV_MEDIUM:fsimx6     = "nand"
FUS_ENV_MEDIUM:fsimx6sx   = "nand"
FUS_ENV_MEDIUM:fsimx6ul   = "nand"
FUS_ENV_OFFSETS:fsimx6    = "0x0"
FUS_ENV_OFFSETS:fsimx6sx  = "0x0"
FUS_ENV_OFFSETS:fsimx6ul  = "0x0"
FUS_ENV_SECT:fsimx6       = "0x20000"
FUS_ENV_SECT:fsimx6sx     = "0x20000"
FUS_ENV_SECT:fsimx6ul     = "0x20000"
FUS_ENV_NSECT:fsimx6      = "2"
FUS_ENV_NSECT:fsimx6sx    = "2"
FUS_ENV_NSECT:fsimx6ul    = "2"
