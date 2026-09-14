#!/usr/bin/env bash
set -u
[ "$(id -u)" -eq 0 ] || { echo 'Root privileges are required.'; exit 1; }
BASE=/opt/batohub
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils certbot >/dev/null
install -d -m 750 /etc/batohub /var/lib/batohub /var/log/batohub "$BASE"
cp -a "$SRC_DIR/." "$BASE/"
cp "$SRC_DIR/config/batohub.conf" /etc/batohub/batohub.conf
chmod 600 /etc/batohub/batohub.conf
chown -R root:root "$BASE" /etc/batohub /var/lib/batohub /var/log/batohub
chmod +x "$BASE/bin/"* "$BASE/core/"*.sh "$BASE/lib/"*.sh "$BASE/security/"*.sh "$BASE/modules/rebecca/ssl/"*.sh "$BASE/modules/rebecca/templates/"*.sh
ln -sfn "$BASE/bin/batohub" /usr/local/bin/batohub
source "$BASE/security/integrity.sh"
write_integrity
exec /usr/local/bin/batohub
