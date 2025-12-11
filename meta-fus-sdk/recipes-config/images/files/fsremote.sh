#!/bin/sh


# Directory for RDP keys (default path for FreeRDP)
KEY_DIR="/etc/freerdp/keys/"
KEY_NAME="server"

PRIV_KEY="$KEY_DIR/$KEY_NAME.key"
PUB_KEY="$KEY_DIR/$KEY_NAME.crt"

WESTON="/usr/bin/weston"
INI="/etc/xdg/weston/weston.ini"

# 1. Generate RDP keys with FreeRDP if not present
if [ ! -f "$PRIV_KEY" ] || [ ! -f "$PUB_KEY" ]; then
    mkdir -p "$KEY_DIR"
    echo "Generating RDP keys with FreeRDP..."
    winpr-makecert -rdp -path "$KEY_DIR" -n "$KEY_NAME"
fi


# 2. Check if Weston is running
if pgrep -f $WESTON > /dev/null; then
    echo "Weston is already running."

    if [ -f "$INI" ]; then
        # Only uncomment if not already uncommented
        if grep -q '^#start-on-startup=true' "$INI" && ! grep -q '^start-on-startup=true' "$INI"; then
            echo "Updating weston.ini..."
            sed -i 's/^#\(start-on-startup=true\)/\1/' "$INI"
            systemctl restart weston.service
        fi
    fi

else
    echo "Starting Weston with RDP backend..."
    $WESTON --backend=rdp-backend.so --rdp-tls-cert=$PUB_KEY --rdp-tls-key=$PRIV_KEY --modules=systemd-notify.so --log /var/log/weston.log &
fi
sleep 1
