#!/usr/bin/env bash
set -u
ROOT=/opt/batohub
MANIFEST=/etc/batohub/integrity.sha256
verify_integrity(){ [ -f "$MANIFEST" ] || return 0; sha256sum -c "$MANIFEST" --quiet 2>/dev/null; }
write_integrity(){
 : > "$MANIFEST"
 find "$ROOT/core" "$ROOT/lib" "$ROOT/modules" "$ROOT/bin" -type f -perm /111 -o -type f -name '*.sh' 2>/dev/null | sort | while read -r f; do sha256sum "$f"; done > "$MANIFEST"
 chmod 600 "$MANIFEST"; chown root:root "$MANIFEST"
}
