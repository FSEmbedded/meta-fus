#!/bin/sh
case "$1" in
    pre)
        /usr/sbin/clocksource.sh suspend
        ;;
    post)
        /usr/sbin/clocksource.sh wakeup
        ;;
esac

