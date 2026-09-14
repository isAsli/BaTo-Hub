#!/usr/bin/env bash
set -euo pipefail

need_root

BASE="${INSTALL_DIR:-/opt/batohub}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive

echo
info "BaToHub install - starting."

if ! need_cmds curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils; then
  err "One or more required commands are missing. Install them and retry."
  exit 1
fi

if ! apt-get update -qq; then
  err "apt-get update failed."
  exit 1
fi

if ! apt-get install -y -qq curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils certbot; then
  err "Required package installation failed."
  exit 1
fi

install -d -m 750 /etc/batohub /var/lib/batohub /var/log/batohub "$BASE"

if [ ! -f /etc/batohub/batohub.conf ]; then
  cp "$SRC_DIR/config/batohub.conf" /etc/batohub/batohub.conf
else
  info "Existing /etc/batohub/batohub.conf preserved."
fi

chmod 600 /etc/batohub/batohub.conf
chown -R root:root "$BASE" /etc/batohub /var/lib/batohub /var/log/batohub

find "$BASE/bin" "$BASE/core" "$BASE/lib" "$BASE/security" \
  "$BASE/modules/rebecca/ssl" "$BASE/modules/rebecca/templates" \
  -type f -name '*.sh' -exec chmod +x {} + || true

if [ ! -d /usr/local/bin ]; then
  err "/usr/local/bin does not exist."
  exit 1
fi

BATOHUB_CMD="${GLOBAL_CMD_NAME:-/usr/local/bin/BaToHub}"
ln -sfn "$BASE/bin/batohub" "$BATOHUB_CMD"

. "$BASE/security/integrity.sh"
write_integrity

echo
info "BaToHub installed."
info "Run: BaToHub"
