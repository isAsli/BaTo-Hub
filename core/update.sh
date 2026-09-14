#!/usr/bin/env bash
. /opt/batohub/lib/common.sh
set -o pipefail
update_all(){
 clear; banner
 local tmp latest url sha z github_json ghver ghurl ru rf
 printf '%s\n' 'Checking central update server...'
 tmp=$(mktemp)
 if curl -fsS --max-time 15 "$UPDATE_MANIFEST" -o "$tmp" 2>>"$LOG_FILE"; then
  latest=$(json_get "$tmp" version); url=$(json_get "$tmp" package); sha=$(json_get "$tmp" sha256)
  if [ -n "$latest" ] && [ "$latest" != "$APP_VERSION" ] && [ -n "$url" ]; then
   ok "New BaToHub version: $latest"; z=/tmp/batohub-update.zip
   if curl -fL --max-time 120 "$url" -o "$z" 2>>"$LOG_FILE"; then
    if [ -n "$sha" ] && [ "$(sha256sum "$z"|awk '{print $1}')" != "$sha" ]; then err 'Update checksum mismatch.'; rm -f "$z"; rm -f "$tmp"; pause; return; fi
    rm -rf /opt/batohub.new; install -d /opt/batohub.new; unzip -q -o "$z" -d /opt/batohub.new
    if [ -f /opt/batohub.new/VERSION ]; then cp -a /opt/batohub /opt/batohub.backup.$(date +%Y%m%d%H%M%S); rsync -a --delete /opt/batohub.new/ /opt/batohub/; ok "BaToHub updated to $latest"; else err 'Invalid update package.'; fi
    rm -rf /opt/batohub.new "$z"
   else err 'Central update package unavailable.'; fi
  else ok "BaToHub $APP_VERSION is current"; fi
 else err 'Central update manifest unavailable.'; fi
 rm -f "$tmp"
 printf '\n%s\n' 'Checking GitHub...'
 github_json=$(mktemp)
 if curl -fsS --max-time 15 "https://api.github.com/repos/$GITHUB_REPO/releases/latest" -H 'Accept: application/vnd.github+json' -o "$github_json" 2>>"$LOG_FILE"; then
  ghver=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("tag_name", ""))' "$github_json" 2>/dev/null || true)
  ghurl=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); a=d.get("assets") or []; print(a[0].get("browser_download_url", "") if a else "")' "$github_json" 2>/dev/null || true)
  [ -n "$ghver" ] && printf 'GitHub latest: %s\n' "$ghver" || true
  if [ -n "$ghver" ] && [ "$ghver" != "v$APP_VERSION" ] && [ "$ghver" != "$APP_VERSION" ] && [ -n "$ghurl" ]; then printf '%s\n' 'GitHub release is newer than the installed version.'; fi
 else err 'GitHub release check unavailable.'; fi
 rm -f "$github_json"
 printf '\n%s\n' 'Updating Rebecca...'
 ru='https://raw.githubusercontent.com/rebeccapanel/Rebecca/master/scripts/rebecca/rebecca-binary.sh'; rf=/tmp/rebecca-update.sh
 if curl -fsSL --max-time 20 "$ru" -o "$rf" 2>>"$LOG_FILE"; then bash "$rf" update 2>&1 | tee -a "$LOG_FILE" && ok 'Rebecca update completed' || { err 'Rebecca update failed'; show_error; }; rm -f "$rf"; else err 'Rebecca updater unavailable'; fi
 printf '\n%s\n' 'Module state'
 [ -f "$TEMPLATE_ROOT/subscription/index.html" ] && ok 'Rebecca / BaTo-Ui installed' || printf '%s\n' 'Rebecca / BaTo-Ui not installed'
 pause
}
