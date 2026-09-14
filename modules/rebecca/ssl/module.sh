#!/usr/bin/env bash
. /opt/batohub/lib/common.sh
set -o pipefail
ssl_menu(){
 while :; do clear; banner "Rebecca / SSL"; printf '%s\n' '1) دریافت و نصب SSL' '2) تمدید SSL' '3) وضعیت SSL' '4) حذف تنظیمات SSL' '0) بازگشت'; read -r -p 'انتخاب: ' c; case "$c" in 1) ssl_install;; 2) ssl_renew;; 3) ssl_status;; 4) ssl_remove;; 0) return;; esac; done
}
rebecca_env(){ [ -f "$REBECCA_DIR/.env" ] && printf '%s' "$REBECCA_DIR/.env" || printf '%s' ''; }
set_env(){ local k="$1" v="$2" f; f=$(rebecca_env); [ -n "$f" ] || { err 'Rebecca .env not found.'; return 1; }; if grep -qE "^${k}=" "$f"; then sed -i "s|^${k}=.*|${k}=${v}|" "$f"; else printf '\n%s=%s\n' "$k" "$v" >> "$f"; fi; }
ssl_install(){
 clear; banner "Rebecca / SSL / Install"; [ -d "$REBECCA_DIR" ] || { err 'Rebecca installation was not detected at /opt/rebecca.'; pause; return; }
 read -r -p 'دامنه پنل: ' domain; read -r -p 'ایمیل Certbot: ' email
 [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]] || { err 'Invalid domain.'; pause; return; }
 [ -n "$email" ] || { err 'Email is required.'; pause; return; }
 local ip dip certdir; ip=$(curl -4fsS --max-time 8 https://api.ipify.org 2>/dev/null || true); dip=$(getent ahostsv4 "$domain" | awk 'NR==1{print $1}')
 [ -n "$dip" ] || { err 'DNS does not resolve for the domain.'; pause; return; }
 [ -z "$ip" ] || [ "$ip" = "$dip" ] || { err "DNS mismatch: domain=$dip server=$ip"; pause; return; }
 command -v certbot >/dev/null 2>&1 || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq certbot || { err 'Certbot installation failed.'; pause; return; }; }
 if ss -ltn 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)80$'; then err 'Port 80 is occupied. Stop the HTTP service or configure a webroot challenge before retrying.'; pause; return; fi
 certdir="$REBECCA_DIR/certs/$domain"; install -d -m 750 "$certdir"; chown -R root:root "$REBECCA_DIR/certs"
 install -d -m 755 /etc/letsencrypt/renewal-hooks/deploy
cat > /etc/letsencrypt/renewal-hooks/deploy/batohub-rebecca.sh <<HOOK
#!/usr/bin/env bash
set -e
domain="${RENEWED_DOMAINS%% *}"
certdir="/opt/rebecca/certs/$domain"
install -d -m 750 "$certdir"
install -m 640 "/etc/letsencrypt/live/batohub-$domain/fullchain.pem" "$certdir/fullchain.pem"
install -m 600 "/etc/letsencrypt/live/batohub-$domain/privkey.pem" "$certdir/privkey.pem"
chown root:root "$certdir"/*
systemctl restart rebecca >/dev/null 2>&1 || true
HOOK
chmod 700 /etc/letsencrypt/renewal-hooks/deploy/batohub-rebecca.sh
if ! certbot certonly --standalone --non-interactive --agree-tos --email "$email" --cert-name "batohub-$domain" -d "$domain" 2>&1 | tee -a "$LOG_FILE"; then err 'Certbot failed.'; show_error; pause; return; fi
 install -m 640 "/etc/letsencrypt/live/batohub-$domain/fullchain.pem" "$certdir/fullchain.pem" || { err 'Certificate copy failed.'; pause; return; }
 install -m 600 "/etc/letsencrypt/live/batohub-$domain/privkey.pem" "$certdir/privkey.pem" || { err 'Private key copy failed.'; pause; return; }
 chown root:root "$certdir"/*; set_env REBECCA_CERT_BASE "$REBECCA_DIR/certs"; set_env UVICORN_SSL_CERTFILE "$certdir/fullchain.pem"; set_env UVICORN_SSL_KEYFILE "$certdir/privkey.pem"; set_env UVICORN_SSL_CA_TYPE public
 systemctl daemon-reload 2>>"$LOG_FILE" || true; systemctl restart rebecca 2>>"$LOG_FILE" || true
 ok "Certificate saved to $certdir"; ok 'Rebecca SSL environment updated'; ok 'Renewal is managed by Certbot'; pause
}
ssl_renew(){ clear; banner 'Rebecca / SSL / Renew'; certbot renew --quiet && ok 'Renewal check completed' || err 'Renewal failed'; pause; }
ssl_status(){ clear; banner 'Rebecca / SSL / Status'; certbot certificates 2>&1 | sed -n '/Certificate Name/,$p'; pause; }
ssl_remove(){ clear; banner 'Rebecca / SSL / Remove'; read -r -p 'برای حذف تنظیمات SSL عبارت REMOVE را وارد کنید: ' x; [ "$x" = REMOVE ] || return; set_env UVICORN_SSL_CERTFILE ''; set_env UVICORN_SSL_KEYFILE ''; systemctl restart rebecca 2>>"$LOG_FILE" || true; ok 'Rebecca SSL settings cleared'; pause; }
