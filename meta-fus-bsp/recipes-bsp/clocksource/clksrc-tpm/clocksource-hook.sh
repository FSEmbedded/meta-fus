#!/bin/sh
case "$1" in
    pre)
        exec /usr/sbin/clocksource.sh suspend
        ;;
    post)
        exec /usr/sbin/clocksource.sh wakeup
        ;;
esac

