#!/bin/sh
set -eu

umask 027

APP_FILE="/opt/nexora/app/app.py"

echo "==============================================="
echo " Operation Poisoned Pipeline"
echo " Application Challenge"
echo "==============================================="

if [ ! -r "${APP_FILE}" ]; then
  echo "[ERROR] Application source is missing."
  exit 1
fi

# ------------------------------------------------------------
# S06 - Start the SSH pivot endpoint.
#
# sshd is started as root (required to bind port 22 and read
# host keys) but the pivot user is strictly controlled by
# /etc/ssh/sshd_config.d/pp-pipeline.conf.
# ------------------------------------------------------------

# Generate host keys if they do not exist yet (first start).
if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
  echo "[+] Generating SSH host keys..."
  ssh-keygen -A >/dev/null 2>&1 || true
fi

mkdir -p /run/sshd
chmod 0755 /run/sshd

echo "[+] Starting sshd..."
/usr/sbin/sshd -D -e -f /etc/ssh/sshd_config &
SSHD_PID=$!

# Give sshd a moment to bind before Flask comes up.
sleep 1

if kill -0 "${SSHD_PID}" 2>/dev/null; then
  echo "[+] sshd running (PID ${SSHD_PID}) listening on TCP 22"
else
  echo "[ERROR] sshd failed to start."
  exit 1
fi

echo "[+] Service account: pipeline-app"
echo "[+] TCP service: 5000"

exec gosu pipeline-app:pipeline-app \
  /usr/local/bin/python \
  "${APP_FILE}"