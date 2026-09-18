# Common settings for all F&S boards

UBOOT_ENTRYPOINT:mx6-generic-bsp    = "0x10800000"
UBOOT_ENTRYPOINT:mx6sx-generic-bsp  = "0x80800000"
UBOOT_ENTRYPOINT:mx6ul-generic-bsp  = "0x80800000"
UBOOT_ENTRYPOINT:mx7ulp-generic-bsp = "0x60008000"

UBOOT_ENTRYPOINT:mx8mm-generic-bsp  = "0x40008000"
UBOOT_ENTRYPOINT:mx8mn-generic-bsp  = "0x40008000"
UBOOT_ENTRYPOINT:mx8mp-generic-bsp  = "0x40008000"

PREFERRED_PROVIDER_virtual/kernel:mx6-generic-bsp    ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx6sx-generic-bsp  ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx6ul-generic-bsp  ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx7ulp-generic-bsp ??= "linux-fus"

PREFERRED_PROVIDER_virtual/kernel:mx6-mainline-bsp ??= "linux-mainline-fus"

PREFERRED_PROVIDER_virtual/kernel:mx8mm-generic-bsp ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx8mn-generic-bsp ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx8mp-generic-bsp ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx8ulp-generic-bsp ??= "linux-fus"

PREFERRED_PROVIDER_virtual/kernel:mx8mp-mainline-bsp ??= "linux-mainline-fus"
PREFERRED_PROVIDER_virtual/kernel:mx8mm-mainline-bsp ??= "linux-mainline-fus"

PREFERRED_PROVIDER_virtual/kernel:mx93-generic-bsp ??= "linux-fus"
PREFERRED_PROVIDER_virtual/kernel:mx95-generic-bsp ??= "linux-fus"

PREFERRED_PROVIDER_virtual/bootloader:mx6-generic-bsp    ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx6sx-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx6ul-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx7ulp-generic-bsp ??= "u-boot-fus"

PREFERRED_PROVIDER_virtual/bootloader:mx8mm-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx8mn-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx8mp-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:mx8ulp-generic-bsp  ??= "u-boot-fus"

PREFERRED_PROVIDER_virtual/bootloader:imx93-generic-bsp  ??= "u-boot-fus"
PREFERRED_PROVIDER_virtual/bootloader:imx95-generic-bsp  ??= "u-boot-fus"

