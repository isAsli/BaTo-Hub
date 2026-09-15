#!/usr/bin/env bash
set -Eeuo pipefail

# Clean system installation verification.
#
# Pulls the root filesystem of an official container image straight from the
# container registry (no container runtime required), mounts the needed kernel
# filesystems, copies this repository into it, and runs install.sh inside the
# chroot. The result is an installation performed on a clean distribution
# userland with its own package manager.
#
# Usage: bash scripts/container-verify.sh IMAGE [WORK_DIR]
#   IMAGE   for example ubuntu:22.04 or debian:12
#
# The script must run as root. It exits non-zero when any step fails.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${1:?usage: container-verify.sh IMAGE [WORK_DIR]}"
IMAGE_REF="${IMAGE%%:*}"
IMAGE_TAG="${IMAGE#*:}"
[[ "$IMAGE_TAG" == "$IMAGE" ]] && IMAGE_TAG="latest"
REGISTRY="registry-1.docker.io"
REPOSITORY="library/${IMAGE_REF}"
WORK="${2:-/tmp/batohub-container-$(printf '%s' "${IMAGE_REF}-${IMAGE_TAG}" | tr -c 'A-Za-z0-9._-' '_')}"
ROOTFS="${WORK}/rootfs"

step() { printf '[container-verify] %s\n' "$1"; }
fail() {
  printf '[container-verify] FAIL: %s\n' "$1" >&2
  exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "this script must run as root"

cleanup() {
  local mount_point
  for mount_point in "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/dev/pts" "${ROOTFS}/dev" "${ROOTFS}/etc/resolv.conf"; do
    if mountpoint -q "$mount_point" 2>/dev/null; then
      umount -l "$mount_point" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT

step "preparing work directory ${WORK}"
# A previous run may have left kernel filesystems mounted in this directory, so
# they are unmounted before the directory is removed.
for mount_point in "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/dev/pts" "${ROOTFS}/dev" "${ROOTFS}/etc/resolv.conf"; do
  if mountpoint -q "$mount_point" 2>/dev/null; then
    umount -l "$mount_point" 2>/dev/null || true
  fi
done
rm -rf "$WORK" 2>/dev/null || true
mkdir -p "$ROOTFS"

token="$(curl -fsS --retry 3 \
  "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPOSITORY}:pull" |
  python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')" ||
  fail "the registry token could not be obtained"

accept="application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.v2+json"

step "resolving ${IMAGE}"
index="$(curl -fsS --retry 3 -H "Authorization: Bearer ${token}" -H "Accept: ${accept}" \
  "https://${REGISTRY}/v2/${REPOSITORY}/manifests/${IMAGE_TAG}")" ||
  fail "the image manifest could not be read"

manifest_digest="$(printf '%s' "$index" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
if "manifests" in data:
    for entry in data["manifests"]:
        platform = entry.get("platform", {})
        if platform.get("architecture") == "amd64" and platform.get("os") == "linux":
            print(entry["digest"])
            break
    else:
        raise SystemExit(1)
else:
    print("")
')" || fail "no amd64 manifest was found for ${IMAGE}"

if [[ -n "$manifest_digest" ]]; then
  manifest="$(curl -fsS --retry 3 -H "Authorization: Bearer ${token}" \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "https://${REGISTRY}/v2/${REPOSITORY}/manifests/${manifest_digest}")" ||
    fail "the amd64 manifest could not be read"
else
  manifest="$index"
fi

mapfile -t layers < <(printf '%s' "$manifest" | python3 -c '
import json
import sys

data = json.load(sys.stdin)
for layer in data.get("layers", []):
    print(layer["digest"])
')
[[ "${#layers[@]}" -gt 0 ]] || fail "the image does not list any layer"

step "extracting ${#layers[@]} layer(s)"
index_layer=0
for layer in "${layers[@]}"; do
  index_layer=$((index_layer + 1))
  blob="${WORK}/layer-${index_layer}.tar.gz"
  curl -fsSL --retry 3 -H "Authorization: Bearer ${token}" \
    "https://${REGISTRY}/v2/${REPOSITORY}/blobs/${layer}" -o "$blob" ||
    fail "layer ${layer} could not be downloaded"
  # Device nodes cannot be created without mknod privileges; the host /dev is
  # bind mounted instead, which is what a container runtime would provide.
  tar -xzf "$blob" -C "$ROOTFS" --exclude './dev/*' --exclude 'dev/*' 2>>"${WORK}/extract.log" ||
    fail "layer ${layer} could not be extracted"
  rm -f "$blob"
done

[[ -x "${ROOTFS}/bin/sh" ]] || fail "the extracted root filesystem has no shell"

step "mounting kernel filesystems"
mount --bind /dev "$ROOTFS/dev" || fail "binding /dev failed"
[[ -d "$ROOTFS/dev/pts" ]] && mount --bind /dev/pts "$ROOTFS/dev/pts" 2>/dev/null || true
mount -t proc proc "$ROOTFS/proc" 2>/dev/null || mount --bind /proc "$ROOTFS/proc" || fail "mounting /proc failed"
mount --bind /sys "$ROOTFS/sys" 2>/dev/null || true

if [[ -r /etc/resolv.conf ]]; then
  mkdir -p "$(dirname "$ROOTFS/etc/resolv.conf")"
  [[ -f "$ROOTFS/etc/resolv.conf" ]] || : >"$ROOTFS/etc/resolv.conf"
  mount --bind /etc/resolv.conf "$ROOTFS/etc/resolv.conf" || true
fi

step "copying the release into the image"
rm -rf "${ROOTFS}/src"
mkdir -p "${ROOTFS}/src"
for entry in "$ROOT"/*; do
  [[ -e "$entry" ]] || continue
  case "$(basename "$entry")" in
    .git | node_modules) continue ;;
  esac
  cp -a "$entry" "${ROOTFS}/src/"
done

step "running install.sh inside ${IMAGE}"
if ! chroot "$ROOTFS" /bin/bash -c 'cd /src && BATOHUB_SOURCE_DIR=/src bash install.sh' \
  >"${WORK}/install.log" 2>&1; then
  tail -n 40 "${WORK}/install.log" >&2
  fail "install.sh failed inside ${IMAGE}"
fi
tail -n 6 "${WORK}/install.log"

step "running the documented commands inside ${IMAGE}"
# The check script captures command output into variables before matching:
# a pipeline such as `BaToHub --validate | grep -q` would fail under pipefail
# as soon as grep exits and the writer receives SIGPIPE.
checks_script='
set -Eeuo pipefail
fail() { echo "CHECK FAILED: $1"; exit 1; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

version="$(BaToHub --version)"
contains "$version" "0.0.3" || fail "--version: $version"
validate="$(BaToHub --validate)"
contains "$validate" "interface ok" || fail "--validate"
BaToHub --check || fail "--check"
status="$(BaToHub --status)"
contains "$status" "Integrity: verified" || fail "--status integrity"
detect="$(BaToHub --detect)"
contains "$detect" "No supported panel was detected." || echo "note: a panel was detected on this image"
panels="$(BaToHub --list-panels)"
contains "$panels" "vpn-ui" || fail "--list-panels"
tools="$(BaToHub --tools)"
contains "$tools" "foxima" || fail "--tools"

test -L /usr/local/bin/BaToHub || fail "global command link"
test "$(stat -c "%a" /etc/batohub/batohub.conf)" = "600" || fail "configuration permissions"

BaToHub --select-panel rebecca >/dev/null || fail "--select-panel"
panel_conf="$(cat /etc/batohub/panel.conf)"
contains "$panel_conf" "PANEL=rebecca" || fail "panel.conf content"
test "$(stat -c "%a" /etc/batohub/panel.conf)" = "600" || fail "panel configuration permissions"
contains "$(BaToHub --status)" "Rebecca" || fail "--status panel"
panel_state="$(BaToHub --panel rebecca status)"
contains "$panel_state" "not_installed" || contains "$panel_state" "stopped" || contains "$panel_state" "running" || fail "panel status"

archive="$(BaToHub --backup | tail -n 1)"
test -f "$archive" || fail "backup archive"
test -f "${archive}.sha256" || fail "backup checksum"
BaToHub --restore "$archive" >/dev/null || fail "--restore"

BaToHub --rebuild-integrity >/dev/null || fail "--rebuild-integrity"
BaToHub --check || fail "--check after rebuild"

printf "tamper detection: "
rebecca_marker=""
echo "" >> /opt/batohub/core/main.sh
if BaToHub --check >/dev/null 2>&1; then
  echo "FAILED: modification was not detected"
  exit 1
fi
echo "modification detected"
BaToHub --rebuild-integrity >/dev/null || fail "--rebuild-integrity after tamper"

/opt/batohub/bin/uninstall --yes >/dev/null || fail "uninstall"
test ! -d /opt/batohub || fail "installation directory after uninstall"
test ! -d /etc/batohub || fail "configuration directory after uninstall"
test ! -e /usr/local/bin/BaToHub || fail "global command after uninstall"
echo "container verification passed"
'
if ! chroot "$ROOTFS" /bin/bash -c "$checks_script" >"${WORK}/checks.log" 2>&1; then
  tail -n 40 "${WORK}/checks.log" >&2
  fail "the verification commands failed inside ${IMAGE}"
fi
cat "${WORK}/checks.log"

step "result"
printf '%s installation and command verification passed\n' "$IMAGE"
printf 'logs: %s\n' "$WORK"
