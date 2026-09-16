#!/usr/bin/env bash
set -Eeuo pipefail

# HTTP client and JSON helpers.
#
# Every remote operation of BaToHub goes through this file. Two properties are
# enforced here rather than by each caller:
#
#   1. A secret is never passed on a command line. Curl would otherwise expose
#      an API token to any local user through the process list. Request headers,
#      including an authorization header, are written to a curl configuration
#      file with mode 0600 which curl reads with --config, and the file is
#      removed as soon as the request returns.
#
#   2. A request is only made over HTTPS, or over plain HTTP to the loopback
#      address. Panel APIs run on the same server, so loopback HTTP is needed;
#      anything else must be encrypted.

API_TIMEOUT="${API_TIMEOUT:-30}"
API_STATUS=""
API_BODY=""

api_url_allowed() {
  local url="$1"
  case "$url" in
  https://*) return 0 ;;
  http://127.0.0.1 | http://127.0.0.1/* | http://127.0.0.1:*) return 0 ;;
  http://localhost | http://localhost/* | http://localhost:*) return 0 ;;
  'http://[::1]' | 'http://[::1]'/*) return 0 ;;
  *) return 1 ;;
  esac
}

# A value written into the curl configuration file is escaped so that it cannot
# terminate the quoted string early and cannot be read as a second directive.
# A newline matters as much as a double quote here: a reply that spans several
# lines is carried as a form field, and a literal newline inside the quoted value
# ends the value at that point and silently drops the rest. curl reads the two
# characters backslash and n inside a quoted value as a newline, so the value
# keeps its line breaks and reaches the service whole.
api_config_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  printf '%s' "$value"
}

api_require_tools() {
  need_cmd curl || {
    err "curl is required for this operation."
    return 1
  }
  need_cmd python3 || {
    err "python3 is required for this operation."
    return 1
  }
}

# api_request METHOD URL [--body JSON] [--header 'Name: value'] [--token TOKEN] [--basic USER:PASS]
#
# API_STATUS holds the HTTP status code and API_BODY the response body. A
# transport failure before any response sets API_STATUS to 000 and returns 1.
api_request() {
  local method="${1:-}" url="${2:-}"
  if [[ -z "$method" ]]; then
    err "api_request needs an HTTP method."
    return 2
  fi
  # The URL may be passed empty when the request is addressed with --private-url
  # instead, which is how a URL that carries a credential is supplied. Whether a
  # usable URL is present is therefore decided after the options are parsed.
  if [[ "$#" -ge 2 ]]; then
    shift 2
  else
    shift "$#"
  fi
  local body="" token="" basic="" header="" cookie="" jar="" private_url=""
  local -a header_list=()
  local -a form_list=()
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
    --body)
      body="${2:-}"
      shift 2
      ;;
    --header)
      header_list+=("${2:-}")
      shift 2
      ;;
    --token)
      token="${2:-}"
      shift 2
      ;;
    --basic)
      basic="${2:-}"
      shift 2
      ;;
    --cookie)
      cookie="${2:-}"
      shift 2
      ;;
    --cookie-jar)
      jar="${2:-}"
      shift 2
      ;;
    --private-url)
      # A URL that carries a credential in its path, such as a Bot API request.
      # It is written into the configuration file and never passed as an
      # argument, so it cannot be read from the process list.
      private_url="${2:-}"
      shift 2
      ;;
    --form)
      form_list+=("${2:-}")
      shift 2
      ;;
    *)
      err "api_request: unknown argument: $1"
      return 2
      ;;
    esac
  done

  api_require_tools || return 1
  if [[ -n "$private_url" ]]; then
    api_url_allowed "$private_url" || {
      err "Refusing a request to a URL that is neither HTTPS nor loopback: ${private_url%%/bot*}"
      return 1
    }
  else
    api_url_allowed "$url" || {
      err "Refusing a request to a URL that is neither HTTPS nor loopback: ${url%%\?*}"
      return 1
    }
    if [[ -z "$url" ]]; then
      err "api_request needs a URL or --private-url."
      return 2
    fi
  fi

  local dir cfg body_file out_file protoredir status
  dir="$(mktemp_dir api)" || return 1
  cfg="${dir}/curl.conf"
  body_file="${dir}/body.json"
  out_file="${dir}/response.body"
  chmod 0700 "$dir"
  : >"$cfg"
  chmod 0600 "$cfg"

  # The configuration file carries every header, so no header value ever
  # reaches the process list.
  printf 'header = "Accept: application/json"\n' >>"$cfg"
  for header in "${header_list[@]}"; do
    [[ -n "$header" ]] || continue
    printf 'header = "%s"\n' "$(api_config_escape "$header")" >>"$cfg"
  done
  if [[ -n "$token" ]]; then
    printf 'header = "Authorization: Bearer %s"\n' "$token" >>"$cfg"
  fi
  if [[ -n "$basic" ]]; then
    printf 'user = "%s"\n' "$basic" >>"$cfg"
  fi
  # A session cookie is a credential, so the cookie file is read through the
  # configuration file rather than being named on the command line.
  if [[ -n "$cookie" ]]; then
    printf 'cookie = "%s"\n' "$cookie" >>"$cfg"
  fi
  if [[ -n "$jar" ]]; then
    printf 'cookie-jar = "%s"\n' "$jar" >>"$cfg"
  fi
  if [[ -n "$private_url" ]]; then
    printf 'url = "%s"\n' "$private_url" >>"$cfg"
  fi
  # A multipart form is written here as well: it can carry a file path and a
  # chat identifier, and a field value can carry a credential.
  for header in "${form_list[@]:-}"; do
    [[ -n "$header" ]] || continue
    printf 'form = "%s"\n' "$(api_config_escape "$header")" >>"$cfg"
  done

  # A loopback service may legitimately answer over plain HTTP; anything that
  # started as HTTPS is never allowed to redirect down to HTTP.
  if [[ "$url" == https://* ]]; then
    protoredir="=https"
  else
    protoredir="=https,http"
  fi

  local log_target="/dev/null"
  if [[ -n "${LOG_FILE:-}" ]]; then
    ensure_runtime_dirs >/dev/null 2>&1 || true
    [[ -e "$LOG_FILE" ]] && log_target="$LOG_FILE"
  fi

  local -a common=(
    --silent --show-error --location --retry 2 --max-time "$API_TIMEOUT"
    --proto '=https,http' --proto-redir "$protoredir"
    --config "$cfg" --request "$method"
    --output "$out_file" --write-out '%{http_code}'
  )

  # With --private-url the request URL comes from the configuration file, so no
  # URL argument is passed at all: curl reads an empty argument as a URL of its
  # own and fails the request even after the response has been received.
  local -a target_args=()
  [[ -n "$url" ]] && target_args=("$url")
  local shown="${url%%\?*}"
  if [[ -n "$private_url" ]]; then
    # The part after /bot carries a credential and is never printed.
    shown="${private_url%%/bot*}"
  fi

  status=""
  if [[ -n "$body" ]]; then
    printf '%s' "$body" >"$body_file"
    chmod 0600 "$body_file"
    status="$(curl "${common[@]}" --data-binary "@${body_file}" \
      "${target_args[@]+${target_args[@]}}" 2>>"$log_target")" || status=""
  else
    status="$(curl "${common[@]}" "${target_args[@]+${target_args[@]}}" 2>>"$log_target")" || status=""
  fi

  API_STATUS="${status:-000}"
  API_BODY="$(cat "$out_file" 2>/dev/null || true)"
  rm -rf -- "$dir"

  if [[ ! "$API_STATUS" =~ ^[0-9]{3}$ ]]; then
    API_STATUS="000"
    err "The request to ${shown} failed before a response was received."
    return 1
  fi
  return 0
}

api_status_ok() { [[ "${API_STATUS:-}" =~ ^2[0-9]{2}$ ]]; }

# One line of the response, for a log that must never hold a credential.
api_response_summary() {
  local limit="${1:-200}"
  printf 'status=%s body=%s' "${API_STATUS:-000}" "$(printf '%s' "${API_BODY:-}" | tr -d '\n' | cut -c1-"$limit")"
}

# ---------------------------------------------------------------------------
# JSON
# ---------------------------------------------------------------------------

# Prints the value at a dotted path of a JSON document read on stdin. A missing
# path prints nothing and returns 1; a document that is not JSON returns 2.
api_json_value() {
  local path="${1:-}"
  python3 -c '
import json
import sys

raw = sys.stdin.read()
try:
    value = json.loads(raw) if raw.strip() else None
except ValueError:
    raise SystemExit(2)
for part in [p for p in sys.argv[1].split(".") if p]:
    if isinstance(value, list):
        try:
            value = value[int(part)]
        except (ValueError, IndexError):
            raise SystemExit(1)
    elif isinstance(value, dict):
        if part not in value:
            raise SystemExit(1)
        value = value[part]
    else:
        raise SystemExit(1)
if value is None:
    print("")
elif isinstance(value, bool):
    print("true" if value else "false")
elif isinstance(value, (dict, list)):
    print(json.dumps(value, separators=(",", ":")))
else:
    print(value)
' "$path"
}

api_json_file_value() {
  local file="$1" path="$2"
  [[ -r "$file" ]] || return 1
  api_json_value "$path" <"$file"
}

# api_json_rows PATH FIELD [FIELD]...
#
# Reads a JSON document on stdin, takes the array at PATH and prints one
# tab separated line per element holding the named fields. A nested field is
# written as a dotted path. Used to turn an API response into display rows.
api_json_rows() {
  local path="${1:-}"
  shift || true
  python3 -c '
import json
import sys

path = sys.argv[1]
fields = sys.argv[2:]
raw = sys.stdin.read()
try:
    value = json.loads(raw) if raw.strip() else []
except ValueError:
    raise SystemExit(2)
for part in [p for p in path.split(".") if p]:
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        raise SystemExit(1)
if not isinstance(value, list):
    raise SystemExit(1)
for item in value:
    row = []
    for field in fields:
        current = item
        for part in field.split("."):
            if isinstance(current, dict) and part in current:
                current = current[part]
            else:
                current = ""
                break
        if current is None:
            current = ""
        elif isinstance(current, bool):
            current = "true" if current else "false"
        elif isinstance(current, (dict, list)):
            current = json.dumps(current, separators=(",", ":"))
        row.append(str(current))
    print("\t".join(row))
' "$path" "$@"
}

# Prints the number of elements of the array at PATH of a JSON document read on
# stdin, or 0 when the path is absent.
api_json_count() {
  local path="${1:-}"
  python3 -c '
import json
import sys

raw = sys.stdin.read()
try:
    value = json.loads(raw) if raw.strip() else None
except ValueError:
    raise SystemExit(2)
for part in [p for p in sys.argv[1].split(".") if p]:
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        raise SystemExit(0)
print(len(value) if isinstance(value, list) else 0)
' "$path"
}

# json_object KEY VALUE [KEY VALUE]...
#
# Builds a JSON object. Values are typed with an explicit prefix so no value is
# ever guessed from its appearance:
#   @str:name   a string (also the default)
#   @int:5      a number
#   @bool:true  a boolean
#   @null:      null
#   @json:{..}  a literal JSON document, used for nested objects and arrays
json_object() {
  python3 -c '
import json
import sys

items = sys.argv[1:]
if len(items) % 2 != 0:
    raise SystemExit(2)
obj = {}
for index in range(0, len(items), 2):
    key = items[index]
    raw = items[index + 1]
    if raw.startswith("@int:"):
        obj[key] = int(raw[5:])
    elif raw.startswith("@bool:"):
        obj[key] = raw[6:].lower() == "true"
    elif raw.startswith("@null:"):
        obj[key] = None
    elif raw.startswith("@json:"):
        obj[key] = json.loads(raw[6:])
    elif raw.startswith("@str:"):
        obj[key] = raw[5:]
    else:
        obj[key] = raw
print(json.dumps(obj, separators=(",", ":")))
' "$@"
}

# json_array ITEM [ITEM]... builds a JSON array of strings.
json_array() {
  python3 -c '
import json
import sys

print(json.dumps(list(sys.argv[1:]), separators=(",", ":")))
' "$@"
}
