# Security Audit

Scope: BaToHub shell source tree at the initial release state.

Files audited:
- install.sh
- bin/batohub
- bin/uninstall
- core/main.sh
- core/license.sh
- core/update.sh
- lib/common.sh
- security/integrity.sh
- modules/rebecca/rebecca_core.sh
- modules/rebecca/ssl/module.sh
- modules/rebecca/templates/module.sh
- config/batohub.conf
- manifest.json

This audit reports findings only. Fixes are written in the patch column. Each finding includes file, line context, severity, root cause, and a concrete patch.

## 1. install.sh

### 1.1 Missing strict mode and fragile dependency install
- File: install.sh
- Lines: 2, 8
- Severity: Medium
- Root cause: `set -u` only is used, apt output is fully silenced, and apt failures can be ignored by the redirected output while the script continues.
- Patch:
```diff
-#!/usr/bin/env bash
-set -u
+#!/usr/bin/env bash
+set -euo pipefail
```

```diff
-apt-get update -qq
-apt-get install -y -qq curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils certbot >/dev/null
+apt-get update -qq || { echo 'apt-get update failed.' >&2; exit 1; }
+if ! apt-get install -y -qq curl ca-certificates openssl unzip rsync python3 whiptail dnsutils iproute2 procps coreutils certbot; then
+  echo 'Required package installation failed.' >&2
+  exit 1
+fi
```

### 1.2 Unscoped glob chmod on bin/core/lib/security
- File: install.sh
- Lines: 14
- Severity: Medium
- Root cause: `chmod +x .../*` on each directory globbing path can succeed with zero matching files and can also match unexpected entries if the directory contents change between listing and chmod.
- Patch:
```diff
-chmod +x "$BASE/bin/"* "$BASE/core/"*.sh "$BASE/lib/"*.sh "$BASE/security/"*.sh "$BASE/modules/rebecca/ssl/"*.sh "$BASE/modules/rebecca/templates/"*.sh
+find "$BASE/bin" "$BASE/core" "$BASE/lib" "$BASE/security" "$BASE/modules/rebecca/ssl" "$BASE/modules/rebecca/templates" -type f -name '*.sh' -exec chmod +x {} + || true
```

### 1.3 Symlink logic and unquoted install source
- File: install.sh
- Lines: 11, 15
- Severity: Low
- Root cause: `cp` from `$SRC_DIR/."` is acceptable, but the global command name and paths are different across the repo, and the symlink target directory should be verified before creating the link.
- Patch:
```diff
-ln -sfn "$BASE/bin/batohub" /usr/local/bin/batohub
+BATOHUB_CMD="${GLOBAL_CMD_NAME:-/usr/local/bin/BaToHub}"
+if [ ! -d "/usr/local/bin" ]; then
+  echo '/usr/local/bin does not exist.' >&2
+  exit 1
+fi
+ln -sfn "$BASE/bin/batohub" "$BATOHUB_CMD"
```

### 1.4 Idempotency and existing config handling
- File: install.sh
- Lines: 9, 11, 12
- Severity: Medium
- Root cause: Re-running the installer overwrites the config file without preserving prior site-specific values and does not verify prior installation state cleanly.
- Patch:
```diff
-cp "$SRC_DIR/config/batohub.conf" /etc/batohub/batohub.conf
+if [ ! -f /etc/batohub/batohub.conf ]; then
+  cp "$SRC_DIR/config/batohub.conf" /etc/batohub/batohub.conf
+else
+  echo 'Existing /etc/batohub/batohub.conf preserved.' >&2
+fi
```

## 2. bin/batohub

### 2.1 No guard against missing installation
- File: bin/batohub
- Line: 2
- Severity: Low
- Root cause: If the installation is missing or broken, the entrypoint fails inside the called script with a less useful error than a direct check here.
- Patch:
```diff
 #!/usr/bin/env bash
-exec /opt/batohub/core/main.sh "$@"
+#!/usr/bin/env bash
+set -euo pipefail
+if [ ! -f /opt/batohub/core/main.sh ]; then
+  echo 'BaToHub is not installed or the core file is missing.' >&2
+  exit 1
+fi
+exec /opt/batohub/core/main.sh "$@"
```

## 3. bin/uninstall

### 3.1 Local variable safety and confirm race
- File: bin/uninstall
- Lines: 9, 20, 24, 34
- Severity: Medium
- Root cause: Read-variables are unscoped and the confirmation input can be confused by trailing whitespace or empty input handling, and the Certbot hook path is hardcoded without quoting in a conditional.
- Patch:
```diff
-if ! read -r -p 'Type REMOVE to continue: ' _input; then
+local _input
+if ! read -r -p 'Type REMOVE to continue: ' _input; then
```

```diff
-if [ "$_input" != "REMOVE" ]; then
+if [ "${_input:-}" != "REMOVE" ]; then
```

```diff
-if [ -f /etc/letsencrypt/renewal-hooks/deploy/batohub-rebecca.sh ]; then
+if [ -f /etc/letsencrypt/renewal-hooks/deploy/batohub-rebecca.sh ]; then
```

### 3.2 Unquoted globbing-like directory removal logic
- File: bin/uninstall
- Lines: 36, 40, 44, 48
- Severity: Low
- Root cause: `rm -rf "$BASE"` is acceptable, but future edits could add unquoted globs; the current script is mostly safe. Add explicit local and quoting discipline here to prevent later regression.
- Patch:
```diff
-if [ -d "$BASE" ]; then
+local _base _conf _state _log _cmd
+_base="${INSTALL_DIR:-/opt/BaToHub}"
+_conf="${CONFIG_DIR:-/etc/BaToHub}"
+_state="${STATE_DIR:-/var/lib/BaToHub}"
+_log="${LOG_DIR:-/var/log/BaToHub}"
+_cmd="/usr/local/bin/BaToHub"
+
+if [ -d "$_base" ]; then
```

## 4. lib/common.sh

### 4.1 Missing strict mode and unsafe log helper for arbitrary input
- File: lib/common.sh
- Lines: 2, 8, 15, 16
- Severity: Medium
- Root cause: `set -u` only, and `log` and `err` receive arbitrary caller strings that may include sensitive runtime values if callers misuse them. Logging is not sanitized centrally.
- Patch:
```diff
-#!/usr/bin/env bash
-set -u
+#!/usr/bin/env bash
+set -euo pipefail
```

```diff
-log(){ printf '[%s] %s\\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
+log(){ printf '[%s] %s\\n' "$(date '+%F %T')" "$*" >> "$LOG_FILE" 2>/dev/null || true; }
```

```diff
-err(){ log "ERROR $*"; printf '\\033[31m✗ %s\\033[0m\\n' "$*"; }
+err(){ log "ERROR $*"; printf '%s\\n' "ERROR: $*" >&2; }
```

### 4.3 Color helpers overriding logs incorrectly
- File: lib/common.sh
- Lines: 9-13
- Severity: Low
- Root cause: Color functions output terminal escapes only, but downstream code mixes terminal colors with logging in ways that reduce readability and auditability.
- Patch:
- Keep color helpers, but do not use them inside `log`. Use plain text in logs.

## 5. core/license.sh

### 5.1 Fingerprint sent over HTTP channel without manifest signature verification concept
- File: core/license.sh
- Lines: 10, 18
- Severity: High
- Root cause: License validation uses curl against a configurable API, but the manifest/license trust model depends on network calls without an enforceable signing verification step in the code.
- Patch:
```diff
-validate_license(){\n local key=\"$1\" fp payload out tmp\n fp=$(fingerprint)\n payload=...\n tmp=$(mktemp)\n local code; code=$(curl -sS -o \"$tmp\" -w '%{http_code}' --connect-timeout 8 --max-time 20 -H 'Content-Type: application/json' -d \"$payload\" \"$LICENSE_API\" 2>>\"$LOG_FILE\" || true);\n ...
+validate_license(){\n local key=\"$1\" fp payload out tmp\n fp=$(fingerprint)\n payload=...\n tmp=$(mktemp)\n local code\n code=$(curl -sS -o \"$tmp\" -w '%{http_code}' --connect-timeout 8 --max-time 20 --cacert /etc/ssl/certs/ca-certificates.crt -H 'Content-Type: application/json' -d \"$payload\" \"$LICENSE_API\" 2>>\"$LOG_FILE\" || true)\n ...
```

### 5.2 License file permissions and key storage
- File: core/license.sh
- Lines: 22, 23
- Severity: Medium
- Root cause: License receipt is written with `install -m 600`, which is good, but the logic depends on a temp file being moved correctly; the key file is stored separately and must be checked for existence before reading it later.
- Patch: keep `install -m 600` and add check before reading key.

## 6. core/update.sh

### 6.1 Unsigned manifest with fallback trust
- File: core/update.sh
- Lines: 8, 10, 14
- Severity: Critical
- Root cause: The update system trusts a remote manifest without signature verification and compares the package SHA-256 only if the manifest provides it; if the manifest is tampered, the update can be redirected to a malicious package.
- Patch:
```diff
-if curl -fsS --max-time 15 "$UPDATE_MANIFEST" -o "$tmp" 2>>"$LOG_FILE"; then\n latest=$(json_get "$tmp" version); url=$(json_get "$tmp" package); sha=$(json_get "$tmp" sha256)\n ...
+if curl -fsS --max-time 15 --cacert /etc/ssl/certs/ca-certificates.crt "$UPDATE_MANIFEST" -o "$tmp" 2>>"$LOG_FILE"; then\n if ! gpg --verify "$MANIFEST_SIGNATURE" "$tmp" 2>>"$LOG_FILE"; then\n   err 'Manifest signature verification failed.'\n   rm -f "$tmp"\n   return 1\n fi\n latest=$(json_get "$tmp" version); url=$(json_get "$tmp" package); sha=$(json_get "$tmp" sha256)\n ...
```

### 6.2 Missing mandatory SHA-256 enforcement
- File: core/update.sh
- Lines: 13, 14
- Severity: High
- Root cause: If the manifest provides no SHA-256, the script proceeds with the download and can install an unverified package.
- Patch:
```diff
-if [ -n "$sha" ] && [ "$(sha256sum "$z"|awk '{print $1}')" != "$sha" ]; then err 'Update checksum mismatch.'; rm -f "$z"; rm -f "$tmp"; pause; return; fi
+if [ -z "$sha" ]; then\n   err 'Update manifest is missing the package SHA-256.'\n   rm -f "$z" "$tmp"\n   return 1\n fi\n if [ "$(sha256sum "$z" | awk '{print $1}')" != "$sha" ]; then\n   err 'Update checksum mismatch.'\n   rm -f "$z" "$tmp"\n   return 1\n fi
```

### 6.3 Temp file suffix and known path
- File: core/update.sh
- Lines: 13, 23, 32
- Severity: Medium
- Root cause: Update package and helper script paths use fixed names under /tmp, which can be predicted by other processes or races.
- Patch:
```diff
-z=/tmp/batohub-update.zip\n ...
+local z; z=$(mktemp /tmp/batohub-update.XXXXXX.zip)
```

```diff
-github_json=$(mktemp)\n ...
+local github_json; github_json=$(mktemp /tmp/batohub-github.XXXXXX.json)
```

```diff
-ru='...'; rf=/tmp/rebecca-update.sh\n ...
+local ru rf\n ru='...'\n rf=$(mktemp /tmp/rebecca-update.XXXXXX.sh)\n ...
```

### 6.4 curl pipe to bash equivalent for Rebecca updater
- File: core/update.sh
- Lines: 32, 33
- Severity: High
- Root cause: The remote Rebecca updater is downloaded to a temp file and executed with bash. This is effectively `curl ... | bash` behavior with an extra write step and has the same trust profile: remote code execution if the upstream script is compromised.
- Patch:
```diff
-if curl -fsSL --max-time 20 "$ru" -o "$rf" 2>>"$LOG_FILE"; then bash "$rf" update 2>&1 | tee -a "$LOG_FILE" && ok 'Rebecca update completed' || { err 'Rebecca update failed'; show_error; }; rm -f "$rf"; else err 'Rebecca updater unavailable'; fi
+if curl -fsSL --max-time 20 --cacert /etc/ssl/certs/ca-certificates.crt "$ru" -o "$rf" 2>>"$LOG_FILE"; then\n   if ! gpg --verify "$REBECCA_UPDATER_SIGNATURE" "$rf" 2>>"$LOG_FILE"; then\n     err 'Rebecca updater signature verification failed.'\n     rm -f "$rf"\n     return 1\n   fi\n   bash "$rf" update 2>&1 | tee -a "$LOG_FILE" && ok 'Rebecca update completed' || { err 'Rebecca update failed'; show_error; }\n   rm -f "$rf"\nelse\n   err 'Rebecca updater unavailable'\nfi
```

## 7. core/main.sh

### 7.1 Mixed UI model and missing confirmation wrappers
- File: core/main.sh
- Lines: multiple
- Severity: Medium
- Root cause: The menu uses both `read -r -p` prompts and a future whiptail model; destructive actions rely on string matches and some paths lack explicit confirmation wrappers.
- Patch: wrap destructive actions in a shared confirmation helper and log the action outcome.

### 7.2 License enforcement at startup
- File: core/main.sh
- Lines: 6, 50
- Severity: Medium
- Root cause: `ensure_license` is called once in `main_menu`, but some submenus could still be reachable indirectly in future code paths if module loading changes; the current load order is acceptable but should be explicit.
- Patch: keep startup license check and document load order.

## 8. security/integrity.sh

### 8.1 Find -o precedence bug
- File: security/integrity.sh
- Lines: 8
- Severity: High
- Root cause: `find ... -type f -perm /111 -o -type f -name '*.sh'` does not group the two predicates correctly. `-o` has lower precedence than implied, so the second clause applies to all found files, not only to the files matched under the intended union.
- Patch:
```diff
-find "$ROOT/core" "$ROOT/lib" "$ROOT/modules" "$ROOT/bin" -type f -perm /111 -o -type f -name '*.sh' 2>/dev/null | sort | while read -r f; do sha256sum "$f"; done > "$MANIFEST"
+find "$ROOT/core" "$ROOT/lib" "$ROOT/modules" "$ROOT/bin" -type f \( -perm /111 -o -name '*.sh' \) 2>/dev/null | sort | while read -r f; do sha256sum "$f"; done > "$MANIFEST"
```

### 8.2 Missing manifest is not an error on verify
- File: security/integrity.sh
- Lines: 5
- Severity: High
- Root cause: `verify_integrity` returns success when the manifest is missing, so a destroyed manifest is silently treated as passing.
- Patch:
```diff
-verify_integrity(){ [ -f "$MANIFEST" ] || return 0; sha256sum -c "$MANIFEST" --quiet 2>/dev/null; }
+verify_integrity(){\n  if [ ! -f "$MANIFEST" ]; then\n    echo 'Integrity manifest is missing.' >&2\n    return 1\n  fi\n  sha256sum -c "$MANIFEST" --quiet 2>/dev/null\n}
```

### 8.3 Non-atomic manifest write
- File: security/integrity.sh
- Lines: 6, 8
- Severity: Medium
- Root cause: Manifest is overwritten directly, which can race with readers and leave a truncated manifest if the process is interrupted.
- Patch:
```diff
-write_integrity(){\n : > "$MANIFEST"\n find ... | while read -r f; do sha256sum "$f"; done > "$MANIFEST"\n ...
+write_integrity(){\n  local tmp\n  tmp=$(mktemp /etc/batohub/integrity.XXXXXX.sha256)\n  : > "$tmp"\n  find "$ROOT/core" "$ROOT/lib" "$ROOT/modules" "$ROOT/bin" -type f \( -perm /111 -o -name '*.sh' \) 2>/dev/null | sort | while read -r f; do sha256sum "$f"; done > "$tmp"\n  chmod 600 "$tmp"\n  chown root:root "$tmp"\n  mv -f "$tmp" "$MANIFEST"\n}
```

### 8.4 No lock around write_integrity
- File: security/integrity.sh
- Lines: 6
- Severity: Low
- Root cause: Concurrent installs or repair actions could interleave manifest writes.
- Patch: add flock on a manifest.lock file when writing or verifying.

## 9. modules/rebecca/rebecca_core.sh

### 9.1 Unquoted grep/sed extractions
- File: modules/rebecca/rebecca_core.sh
- Lines: 30, 31
- Severity: Medium
- Root cause: `tr -d '"\'` is fragile and the value may still contain whitespace or control characters; better to sanitize after extraction.
- Patch: trim with `xargs` or parameter expansion after extraction and reject empty results.

## 10. modules/rebecca/ssl/module.sh

### 10.1 Domain validation is permissive
- File: modules/rebecca/ssl/module.sh
- Lines: 12
- Severity: Medium
- Root cause: The regex allows strings like `.-.` or leading/trailing dots in some cases; better validation should reject empty labels and invalid characters.
- Patch:
```diff
-if [[ "$domain" =~ ^[A-Za-z0-9.-]+$ ]]; then\n   ...\nfi
+local _clean\n_clean=$(printf '%s' "$domain" | sed 's/[[:space:]]//g')\nif [ -z "$_clean" ] || [[ "$_clean" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; then\n   domain="$_clean"\nelse\n   err 'Invalid domain.'\n   return 1\nfi
```

### 10.2 Certificate directory permissions order
- File: modules/rebecca/ssl/module.sh
- Lines: 19, 36
- Severity: Low
- Root cause: Cert directory is created, then chown runs on parent, then files are copied; this is acceptable but should set directory permissions before writing sensitive files.
- Patch: set `certdir` permissions to 750 before any file write.

### 10.3 Certbot output logged with private key handling
- File: modules/rebecca/ssl/module.sh
- Lines: 33, 34, 35
- Severity: Medium
- Root cause: Certbot output is appended to the log; this is acceptable, but any future change that logs environment or key paths in a raw way should be blocked by policy.
- Patch: keep log line but ensure no private key material is echoed.

## 11. modules/rebecca/templates/module.sh

### 11.1 .env write path is not atomic
- File: modules/rebecca/templates/module.sh
- Lines: 8, 9
- Severity: Medium
- Root cause: sed in-place followed by append can interleave if multiple processes edit the same env file; use lock or atomic rewrite for sensitive env updates.
- Patch: use flock on a lock file in `$REBECCA_DIR/.env.lock` around env edits.

## 12. config/batohub.conf

### 12.1 Config permissions depend on installer behavior
- File: config/batohub.conf
- Lines: 1-14
- Severity: Medium
- Root cause: The config file content is not secret-heavy, but installer permissions and runtime sourcing must ensure it is not world-readable.
- Patch: enforce `chmod 600` in installer and require `600` at repair time.

## 13. manifest.json

### 13.1 Placeholder hash and missing signature fields
- File: manifest.json
- Lines: 4, 5
- Severity: High
- Root cause: `sha256` is a placeholder, and the manifest has no signature reference, so consumers cannot verify authenticity without a separate signing step.
- Patch:
- Remove placeholder and write the real computed hash during packaging.
- Add `signature` and `signing_key_fingerprint` fields after signing.

## Summary

Critical:
- Unsigned update manifest with SHA-256 optional enforcement, allowing MITM or downgrade to a malicious package

High:
- Manifest treated as valid even when missing in integrity verification
- find -o precedence bug reducing integrity coverage
- Remote updater execution with curl-to-bash trust model
- License validation over HTTP channel without explicit CA certificate usage and without manifest signing integration

Medium:
- Installer silent apt failures and weak strict mode
- Non-atomic integrity and env writes
- Unscoped chmod/glob patterns
- Unquoted input handling in several prompts
- Domain validation gap
- Temp file predictability in update flow

Low:
- Entrypoint missing installation-guard check
- Color and logging mixing concerns
- Unnecessary cosmetic UI elements

These findings are remediated in the next patch phase.
