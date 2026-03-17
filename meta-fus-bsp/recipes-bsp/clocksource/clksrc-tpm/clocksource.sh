#!/bin/sh

DEFAULT_CLKSRC="arch_sys_counter"
IMX_CLKSRC="imx-tpm"

SYSFS_CLKSRC_PATH="/sys/devices/system/clocksource/clocksource0/"

case $1 in
    "suspend")
        echo "Set $DEFAULT_CLKSRC as current Clock Source"
        SET_CLKSRC=$DEFAULT_CLKSRC
        ;;
    "wakeup")
        echo "Set $IMX_CLKSRC as current Clock Source"
        SET_CLKSRC=$IMX_CLKSRC
        ;;
    *)
        echo "Usage: $0 [suspend|wakeup]"
        exit 0
        ;;
esac

grep -q $SET_CLKSRC $SYSFS_CLKSRC_PATH/available_clocksource
if [ $? -ne 0 ]; then
    echo "Error: Clock Source $SET_CLKSRC not found in available_clocksource"
    exit 0
fi

echo $SET_CLKSRC > $SYSFS_CLKSRC_PATH/current_clocksource
if [ $? -ne 0 ]; then
    echo "Error: Failed to set $SET_CLKSRC as current Clock Source"
    exit 0
fi

if [ "$1" == "wakeup" ] && [ ! -f /dev/rtc0 ]; then
    echo sync system-time
    /usr/sbin/hwclock -s
fi

exit 0

