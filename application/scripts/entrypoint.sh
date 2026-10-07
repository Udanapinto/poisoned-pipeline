#!/bin/sh
set -eu

umask 027

APP_FILE="/opt/nexora/app/app.py"

echo "=================================================="
echo " Operation Poisoned Pipeline"
echo " Application Challenge"
echo "=================================================="

if [ ! -r "$APP_FILE" ]; then
    echo "[ERROR] Application source is missing."
    exit 1
fi

echo "[+] Starting Nexora application."
echo "[+] Service account: pipeline-app"
echo "[+] TCP service: 5000"

exec gosu pipeline-app:pipeline-app \
    /usr/local/bin/python \
    "$APP_FILE"