#!/usr/bin/env bash
. /opt/batohub/lib/common.sh
LICENSE_FILE=/etc/batohub/license.json
fingerprint(){ local m h; m=$(cat /etc/machine-id 2>/dev/null || true); h=$(hostname 2>/dev/null || true); printf '%s|%s|%s' "$m" "$h" "$APP_NAME" | sha256sum | awk '{print $1}'; }
license_prompt(){
 printf '\n%s\n' "$(white 'OpenLicense API Key')"; read -r -p '> ' key; [ -n "$key" ] || { err 'License key is empty.'; return 1; }
 validate_license "$key"
}
validate_license(){
 local key="$1" fp payload out tmp
 fp=$(fingerprint)
 payload=$(python3 - "$key" "$LICENSE_PRODUCT" "$fp" "$APP_VERSION" <<'PY'
import json,sys,platform,socket
print(json.dumps({'key':sys.argv[1],'product':sys.argv[2],'fingerprint':sys.argv[3],'hostname':socket.gethostname(),'version':sys.argv[4]}))
PY
 )
 tmp=$(mktemp)
 local code; code=$(curl -sS -o "$tmp" -w '%{http_code}' --connect-timeout 8 --max-time 20 -H 'Content-Type: application/json' -d "$payload" "$LICENSE_API" 2>>"$LOG_FILE" || true); if [ -z "$code" ] || [ "$code" = 000 ]; then rm -f "$tmp"; err "License server unreachable: $LICENSE_API"; return 1; fi
 if [ "$(json_get "$tmp" valid)" != "True" ] && [ "$(json_get "$tmp" valid)" != "true" ]; then
   local e; e=$(json_get "$tmp" error); rm -f "$tmp"; [ -n "$e" ] || e='license_rejected'; err "License rejected: $e"; printf '%s\n' "Contact $SUPPORT for a valid license."; return 1
 fi
 install -m 600 "$tmp" "$LICENSE_FILE"; rm -f "$tmp"
 printf '%s\n' "$key" | install -m 600 /dev/stdin /etc/batohub/.license_key
 ok 'License verified'
 return 0
}
ensure_license(){
 if [ -s /etc/batohub/.license_key ] && [ -s "$LICENSE_FILE" ]; then
   local key; key=$(cat /etc/batohub/.license_key)
   validate_license "$key" >/dev/null 2>&1 && return 0
 fi
 while ! license_prompt; do :; done
}
