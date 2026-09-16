#!/usr/bin/env bash
set -Eeuo pipefail

# Multi-server node management.
#
# A node is a remote machine a panel uses for its own workers. BaToHub owns
# three things and nothing else:
#
#   - one record per node under ${STATE_DIR}/nodes, mode 0600, holding the
#     connection details the operator entered;
#   - the calls that register, deregister and restart that node through the
#     panel's own API;
#   - the log lines that record what happened.
#
# The remote machine, its data and its configuration belong to the operator.
# Removing a node deregisters it from the panel and deletes the local record; it
# never deletes anything on the remote host.
#
# Field names, endpoint paths and even the shape of the registration body differ
# between panels, so they are declared in each panel.json under "nodes" and are
# read here. An operator can override any of them in ${CONFIG_DIR}/nodes.conf
# without editing the shipped metadata.

NODES_CONF_FILE="${CONFIG_DIR}/nodes.conf"
NODES_STATE_SUBDIR="nodes"

# Node session state for the lifetime of one command. A token or a cookie jar
# lives in memory or in a 0600 temporary file and is never written to a log or
# to the node records.
NODES_SESSION_JAR=""
NODES_SESSION_JARS=()
NODES_SESSION_TOKEN=""
NODES_SESSION_PANEL=""
NODES_AUTH_ARGS=()

# Every value that reaches a URL or a JSON body is validated first.
NODE_NAME_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$'
NODE_ROLE_PATTERN='^[A-Za-z0-9][A-Za-z0-9._-]{0,31}$'
NODE_FINGERPRINT_PATTERN='^([0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$'

nodes_dir() { printf '%s/%s\n' "$STATE_DIR" "$NODES_STATE_SUBDIR"; }

nodes_config_key() {
  printf 'NODES_%s\n' "$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
}

nodes_override() {
  local key
  key="$(nodes_config_key "$1")"
  read_env_value "$NODES_CONF_FILE" "$key" 2>/dev/null || true
}

node_name_valid() { [[ "${1:-}" =~ $NODE_NAME_PATTERN ]]; }
node_role_valid() { [[ "${1:-}" =~ $NODE_ROLE_PATTERN ]]; }
node_fingerprint_valid() { [[ "${1:-}" =~ $NODE_FINGERPRINT_PATTERN ]]; }

node_panel_supports_nodes() {
  [[ "$(panel_meta_get "${1:-}" nodes.supported 2>/dev/null)" == "true" ]]
}

node_panels_with_nodes() {
  local name
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    node_panel_supports_nodes "$name" && printf '%s\n' "$name"
  done < <(loader_panels)
}

# --- records ---------------------------------------------------------------

node_record_path() {
  local panel="${1:-}" name="${2:-}"
  printf '%s/%s.%s.conf\n' "$(nodes_dir)" "$panel" "$name"
}

node_record_exists() {
  local panel="${1:-}" name="${2:-}"
  [[ -r "$(node_record_path "$panel" "$name")" ]]
}

node_record_read() {
  local panel="$1" name="$2" key="$3" file
  file="$(node_record_path "$panel" "$name")"
  read_env_value "$file" "$key" 2>/dev/null || true
}

# Writes keys into a node record. Keys that are written are replaced; keys the
# record already holds and that are not part of this call are kept, so a later
# update of one field cannot drop the identifier the panel returned earlier.
node_record_write() {
  local panel="$1" name="$2"
  shift 2
  local file content="" existing="" line key chunk
  node_name_valid "$name" || {
    err "Invalid node name: $name"
    return 1
  }
  local value i skip
  local -a keys=() values=()
  while [[ "$#" -gt 1 ]]; do
    key="$1"
    value="$2"
    shift 2
    valid_env_key "$key" || {
      err "Invalid record key: $key"
      return 1
    }
    keys+=("$key")
    values+=("$value")
  done
  install -d -m 0750 -o root -g root "$(nodes_dir)"
  file="$(node_record_path "$panel" "$name")"
  [[ -r "$file" ]] && existing="$(cat -- "$file" 2>/dev/null || true)"
  if [[ -n "$existing" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      skip=0
      for key in "${keys[@]}"; do
        [[ "${line%%=*}" == "$key" ]] && skip=1
      done
      if [[ "$skip" -eq 0 ]]; then
        # printf -v keeps the newline: a command substitution would strip it and
        # the record would end up as a single line.
        printf -v chunk '%s\n' "$line"
        content+="$chunk"
      fi
    done <<<"$existing"
  fi
  for i in "${!keys[@]}"; do
    printf -v chunk '%s=%s\n' "${keys[$i]}" "${values[$i]}"
    content+="$chunk"
  done
  with_lock nodes atomic_write "$file" 0600 "$content" || {
    err "Failed to write the node record: $file"
    return 1
  }
  harden_file "$file" 0600
  return 0
}

node_record_delete() {
  local panel="$1" name="$2" file
  file="$(node_record_path "$panel" "$name")"
  [[ -e "$file" ]] || return 0
  rm -f -- "$file"
  log "Node record removed: ${panel}/${name}"
  return 0
}

# Prints "panel<TAB>name" for every record, optionally filtered to one panel.
node_records() {
  local filter="${1:-}" file base panel name
  [[ -d "$(nodes_dir)" ]] || return 0
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    base="$(basename "$file")"
    base="${base%.conf}"
    panel="${base%%.*}"
    name="${base#*.}"
    [[ -n "$filter" && "$panel" != "$filter" ]] && continue
    printf '%s\t%s\n' "$panel" "$name"
  done < <(find "$(nodes_dir)" -maxdepth 1 -type f -name '*.conf' 2>/dev/null | sort)
  return 0
}

# --- panel API -------------------------------------------------------------

nodes_api_base() {
  local panel="$1" declared override port
  override="$(nodes_override "API_BASE_$(printf '%s' "$panel" | tr '[:lower:]-' '[:upper:]_')")"
  if [[ -n "$override" ]]; then
    printf '%s\n' "${override%/}"
    return 0
  fi
  declared="$(panel_meta_get "$panel" nodes.api_base 2>/dev/null)"
  [[ -n "$declared" ]] || {
    err "Panel ${panel} does not declare a node API address."
    return 1
  }
  port="$(panel_port_for "$panel")"
  declared="${declared//\{port\}/$port}"
  declared="${declared//\{panel\}/$panel}"
  printf '%s\n' "${declared%/}"
}

# The API token is read from the panel's own configuration, or from the operator
# override file. It is printed to the caller and never logged.
nodes_api_token() {
  local panel="$1" value key env_file
  local upper
  upper="$(printf '%s' "$panel" | tr '[:lower:]-' '[:upper:]_')"
  value="$(nodes_override "API_TOKEN_${upper}")"
  if [[ -n "$value" ]]; then
    printf '%s\n' "$value"
    return 0
  fi
  env_file="$(panel_meta_get "$panel" default_path 2>/dev/null)/.env"
  [[ -r "$env_file" ]] || return 1
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    value="$(read_env_value "$env_file" "$key" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
      printf '%s\n' "$value"
      return 0
    fi
  done < <(panel_meta_list "$panel" nodes.token_env_keys 2>/dev/null || true)
  return 1
}

nodes_api_auth_mode() {
  local mode
  mode="$(panel_meta_get "${1:-}" nodes.api_auth 2>/dev/null)"
  printf '%s\n' "${mode:-bearer}"
}

# nodes_endpoint PANEL OPERATION [IDENTIFIER] prints a full URL.
#
# The identifier is the value the panel itself uses for the node: its name in a
# simple API, its record id when the API addresses nodes by id. Both placeholders
# are substituted with it, so a panel that uses "{id}" in its path needs no
# special handling.
nodes_endpoint() {
  local panel="$1" operation="$2" identifier="${3:-}" path base upper
  upper="$(printf '%s' "$panel" | tr '[:lower:]-' '[:upper:]_')"
  path="$(nodes_override "API_PATH_${upper}_$(printf '%s' "$operation" | tr '[:lower:]-' '[:upper:]_')")"
  if [[ -z "$path" ]]; then
    path="$(panel_meta_get "$panel" "nodes.endpoints.${operation}" 2>/dev/null)"
  fi
  [[ -n "$path" ]] || {
    err "Panel ${panel} does not declare an endpoint for the ${operation} node operation."
    return 1
  }
  path="${path//\{name\}/$identifier}"
  path="${path//\{id\}/$identifier}"
  path="${path//\{port\}/$(panel_port_for "$panel")}"
  path="${path//\{panel\}/$panel}"
  case "$path" in
  http://* | https://*)
    printf '%s\n' "$path"
    return 0
    ;;
  esac
  base="$(nodes_api_base "$panel")" || return 1
  case "$path" in
  /*) printf '%s%s\n' "$base" "$path" ;;
  *) printf '%s/%s\n' "$base" "$path" ;;
  esac
}

# nodes_api_call PANEL METHOD URL [BODY]
#
# The token is handed to the HTTP layer, which writes it into a curl
# configuration file rather than a command line.
url_encode() {
  python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.stdin.read(), safe=""))'
}

nodes_panel_upper() { printf '%s\n' "$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"; }

# The username and password used to open a panel session. They come from the
# operator override file, or from keys the panel itself declares. They are
# printed to the caller and never written to a log.
nodes_api_credentials() {
  local panel="$1" user password user_key password_key env_file
  local upper
  upper="$(nodes_panel_upper "$panel")"
  user="$(nodes_override "USER_${upper}")"
  password="$(nodes_override "PASSWORD_${upper}")"
  if [[ -z "$user" || -z "$password" ]]; then
    env_file="$(panel_meta_get "$panel" default_path 2>/dev/null)/.env"
    user_key="$(panel_meta_get "$panel" nodes.credentials.username_env 2>/dev/null)"
    password_key="$(panel_meta_get "$panel" nodes.credentials.password_env 2>/dev/null)"
    if [[ -r "$env_file" ]]; then
      [[ -n "$user" ]] || user="$(read_env_value "$env_file" "$user_key" 2>/dev/null || true)"
      [[ -n "$password" ]] || password="$(read_env_value "$env_file" "$password_key" 2>/dev/null || true)"
    fi
  fi
  if [[ -z "$user" || -z "$password" ]]; then
    err "No administrator credentials are configured for the ${panel} API."
    err "Set NODES_USER_${upper} and NODES_PASSWORD_${upper} in ${NODES_CONF_FILE}."
    return 1
  fi
  printf '%s\n%s\n' "$user" "$password"
}

# The cookie jar of a panel session. It holds a session credential, so it is
# created with mode 0600 and removed when the command finishes.
nodes_session_jar() {
  if [[ -z "${NODES_SESSION_JAR:-}" ]]; then
    NODES_SESSION_JAR="$(mktemp_file nodes-session)"
    chmod 0600 "$NODES_SESSION_JAR"
    NODES_SESSION_JARS+=("$NODES_SESSION_JAR")
  fi
  printf '%s\n' "$NODES_SESSION_JAR"
}

nodes_session_cleanup() {
  local file
  if [[ -n "${NODES_SESSION_JAR:-}" ]]; then
    rm -f -- "$NODES_SESSION_JAR"
    NODES_SESSION_JAR=""
  fi
  for file in "${NODES_SESSION_JARS[@]:-}"; do
    [[ -n "$file" ]] && rm -f -- "$file"
  done
  NODES_SESSION_JARS=()
  NODES_SESSION_TOKEN=""
  return 0
}

nodes_api_login_request() {
  local panel="$1" jar="${2:-}" url body creds user password
  local content_type
  url="$(trim "$(nodes_endpoint "$panel" login "")")" || return 1
  creds="$(nodes_api_credentials "$panel")" || return 1
  user="${creds%%$'\n'*}"
  password="${creds#*$'\n'}"
  body="$(panel_meta_get "$panel" nodes.login_body 2>/dev/null)"
  [[ -n "$body" ]] || {
    err "Panel ${panel} does not declare a login body."
    return 1
  }
  body="${body//\{user_encoded\}/$(printf '%s' "$user" | url_encode)}"
  body="${body//\{password_encoded\}/$(printf '%s' "$password" | url_encode)}"
  body="${body//\{user\}/$user}"
  body="${body//\{password\}/$password}"
  content_type="$(panel_meta_get "$panel" nodes.login_content_type 2>/dev/null)"
  local -a args=(--body "$body")
  if [[ -n "$content_type" ]]; then
    args+=(--header "Content-Type: ${content_type}")
  fi
  if [[ -n "$jar" ]]; then
    args+=(--cookie-jar "$jar" --cookie "$jar")
  fi
  api_request POST "$url" "${args[@]}" || return 1
  nodes_api_succeeded || return 1
  return 0
}

nodes_api_login_token() {
  local panel="$1" field
  if [[ -n "${NODES_SESSION_TOKEN:-}" && "${NODES_SESSION_PANEL:-}" == "$panel" ]]; then
    printf '%s\n' "$NODES_SESSION_TOKEN"
    return 0
  fi
  nodes_api_login_request "$panel" || return 1
  field="$(panel_meta_get "$panel" nodes.login_token_field 2>/dev/null)"
  [[ -n "$field" ]] || field="access_token"
  NODES_SESSION_TOKEN="$(printf '%s' "$API_BODY" | api_json_value "$field" 2>/dev/null || true)"
  if [[ -z "$NODES_SESSION_TOKEN" ]]; then
    err "The ${panel} login did not return a token in the field ${field}."
    return 1
  fi
  NODES_SESSION_PANEL="$panel"
  printf '%s\n' "$NODES_SESSION_TOKEN"
}

# Fills NODES_AUTH_ARGS with the arguments the HTTP layer needs for the mode the
# panel declares.
nodes_api_auth_args() {
  local panel="$1" mode token
  NODES_AUTH_ARGS=()
  mode="$(nodes_api_auth_mode "$panel")"
  case "$mode" in
  none) return 0 ;;
  bearer)
    token="$(nodes_api_token "$panel" || true)"
    if [[ -z "$token" ]]; then
      err "No API token is configured for ${panel}."
      err "Set NODES_API_TOKEN_$(nodes_panel_upper "$panel") in ${NODES_CONF_FILE}."
      return 1
    fi
    NODES_AUTH_ARGS=(--token "$token")
    ;;
  login)
    token="$(nodes_api_login_token "$panel")" || return 1
    NODES_AUTH_ARGS=(--token "$token")
    ;;
  login-cookie)
    nodes_api_login_request "$panel" "$(nodes_session_jar)" || return 1
    NODES_AUTH_ARGS=(--cookie "$(nodes_session_jar)")
    ;;
  *)
    err "Unknown node API authentication mode: ${mode}"
    return 1
    ;;
  esac
  return 0
}

# nodes_api_call PANEL METHOD URL [BODY]
#
# Every credential is handed to the HTTP layer, which writes it into a curl
# configuration file rather than a command line.
nodes_api_call() {
  local panel="$1" method="$2" url="$3" body="${4:-}"
  local -a args=()
  nodes_api_auth_args "$panel" || return 1
  if [[ -n "$body" ]]; then
    args+=(--body "$body")
  fi
  if [[ "${#NODES_AUTH_ARGS[@]}" -gt 0 ]]; then
    args+=("${NODES_AUTH_ARGS[@]}")
  fi
  if [[ "${#args[@]}" -gt 0 ]]; then
    api_request "$method" "$url" "${args[@]}"
  else
    api_request "$method" "$url"
  fi
}

nodes_api_succeeded() {
  api_status_ok && return 0
  err "The panel API answered with status ${API_STATUS}."
  log "NODES api status=${API_STATUS}"
  return 1
}

# --- panel operations ------------------------------------------------------

# Prints one tab separated line per node as the panel reports them. The field
# list is declared per panel, so a panel that reports different field names is
# described in its own metadata instead of being special cased here.
nodes_panel_list() {
  local panel="$1" url
  local -a fields=()
  url="$(nodes_endpoint "$panel" list)" || return 1
  while IFS= read -r field; do
    [[ -n "$field" ]] && fields+=("$field")
  done < <(panel_meta_list "$panel" nodes.list_fields 2>/dev/null || true)
  [[ "${#fields[@]}" -gt 0 ]] || fields=(name address status)
  nodes_api_call "$panel" GET "$url" || return 1
  nodes_api_succeeded || return 1
  printf '%s' "$API_BODY" | api_json_rows "$(panel_meta_get "$panel" nodes.list_container 2>/dev/null || printf '')" "${fields[@]}"
}

nodes_registration_body() {
  local panel="$1" name="$2" role="$3" host="$4" port="$5" fingerprint="$6" tls="$7"
  local template
  template="$(panel_meta_get "$panel" nodes.add_body 2>/dev/null)"
  [[ -n "$template" ]] || {
    err "Panel ${panel} does not declare the body of a node registration."
    return 1
  }
  template="${template//\{name\}/$name}"
  template="${template//\{role\}/$role}"
  template="${template//\{host\}/$host}"
  template="${template//\{port\}/$port}"
  template="${template//\{cert\}/$fingerprint}"
  template="${template//\{tls\}/$tls}"
  printf '%s\n' "$template"
}

nodes_panel_add() {
  local panel="$1" name="$2" role="$3" host="$4" port="$5" fingerprint="$6" tls="${7:-1}"
  local url body id_field id
  url="$(nodes_endpoint "$panel" add)" || return 1
  body="$(nodes_registration_body "$panel" "$name" "$role" "$host" "$port" "$fingerprint" "$tls")" || return 1
  nodes_api_call "$panel" POST "$url" "$body" || return 1
  nodes_api_succeeded || return 1
  # A panel that addresses its nodes by an identifier returns it in the
  # registration response. It is stored in the node record so that every later
  # call addresses the node the way that panel expects.
  id_field="$(panel_meta_get "$panel" nodes.add_id_field 2>/dev/null)"
  if [[ -n "$id_field" ]]; then
    id="$(printf '%s' "$API_BODY" | api_json_value "$id_field" 2>/dev/null || true)"
    if [[ -n "$id" ]]; then
      node_record_write "$panel" "$name" NODE_REMOTE_ID "$id" || return 1
    fi
  fi
  return 0
}

# The identifier the panel uses for a node: the recorded one when the panel
# returned it, otherwise the node name.
node_record_identifier() {
  local panel="$1" name="$2" recorded
  recorded="$(node_record_read "$panel" "$name" NODE_REMOTE_ID)"
  printf '%s\n' "${recorded:-$name}"
}

nodes_panel_remove() {
  local panel="$1" identifier="$2" url
  url="$(nodes_endpoint "$panel" remove "$identifier")" || return 1
  nodes_api_call "$panel" DELETE "$url" || return 1
  nodes_api_succeeded || return 1
  return 0
}

nodes_panel_restart() {
  local panel="$1" identifier="$2" url
  url="$(nodes_endpoint "$panel" restart "$identifier")" || return 1
  nodes_api_call "$panel" POST "$url" || return 1
  nodes_api_succeeded || return 1
  return 0
}

nodes_panel_detail() {
  local panel="$1" identifier="$2" url
  url="$(nodes_endpoint "$panel" status "$identifier")" || return 1
  nodes_api_call "$panel" GET "$url" || return 1
  nodes_api_succeeded || return 1
  printf '%s\n' "$API_BODY"
}

nodes_panel_logs() {
  local panel="$1" identifier="$2" url
  url="$(nodes_endpoint "$panel" logs "$identifier")" || {
    warn "Panel ${panel} does not expose node logs through its API."
    return 1
  }
  nodes_api_call "$panel" GET "$url" || return 1
  nodes_api_succeeded || return 1
  printf '%s\n' "$API_BODY"
}

# --- connection information ------------------------------------------------

# The installer URL a panel publishes for its own node runtime. BaToHub never
# invents one: a panel that has no node installer prints nothing here.
nodes_node_installer_url() {
  panel_meta_get "${1:-}" nodes.node_installer_url 2>/dev/null
}

# The lines the operator runs on the remote machine. The installer is downloaded
# to a file and then run, so the remote shell never pipes a download into an
# interpreter and every step is visible in the remote shell history.
nodes_remote_install_lines() {
  local panel="$1" url
  url="$(nodes_node_installer_url "$panel")"
  [[ -n "$url" ]] || return 1
  printf 'curl -fsSL --location %q -o /tmp/batohub-node-install.sh\n' "$url"
  printf 'bash /tmp/batohub-node-install.sh'
  local argument
  while IFS= read -r argument; do
    [[ -n "$argument" ]] && printf ' %q' "$argument"
  done < <(panel_meta_list "$panel" nodes.node_install_arguments 2>/dev/null || true)
  printf '\n'
}

# The connection information for a node, printed so the operator can install the
# runtime on the remote machine by hand.
nodes_connection_bundle() {
  local panel="$1" name="$2" host="$3" port="$4" role="$5" fingerprint="$6" lines
  printf 'Node: %s (%s)\n' "$name" "$(panel_display_for "$panel")"
  printf 'Role: %s\n' "$role"
  printf 'Address: %s:%s\n' "$host" "$port"
  printf 'Certificate fingerprint: %s\n\n' "$fingerprint"
  if lines="$(nodes_remote_install_lines "$panel")"; then
    printf 'Run these lines on the remote machine as root:\n\n'
    printf '%s\n' "$lines" | sed 's/^/  /'
    printf '\n'
  else
    printf 'Panel %s does not declare a node runtime installer.\n' "$panel"
    printf 'Install the node runtime for this panel on the remote machine and\n'
    printf 'register it with the address and fingerprint above.\n\n'
  fi
  printf 'The node has to be registered with the panel before it accepts traffic.\n'
  return 0
}

# Installs the node runtime on the remote machine when the operator supplies SSH
# access. The installer URL and its arguments come from the panel metadata.
nodes_install_over_ssh() {
  local panel="$1" host="$2" user="$3" key_file="${4:-}" remote_command
  need_cmd ssh || {
    err "ssh is required to install the node runtime on a remote machine."
    return 1
  }
  if ! remote_command="$(nodes_remote_install_lines "$panel")"; then
    err "Panel ${panel} does not declare a node runtime installer."
    return 1
  fi
  if [[ -n "$key_file" && ! -r "$key_file" ]]; then
    err "SSH key file is not readable: $key_file"
    return 1
  fi
  local -a ssh_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new)
  [[ -n "$key_file" ]] && ssh_args+=(-i "$key_file")
  printf 'Running the node runtime installer on %s@%s\n' "$user" "$host"
  log "NODES ssh install panel=${panel} target=${user}@${host}"
  if ! ssh "${ssh_args[@]}" "${user}@${host}" "${remote_command}" >>"${LOG_FILE}" 2>&1; then
    err "The remote installer did not complete. Output: ${LOG_FILE}"
    return 1
  fi
  ok "The node runtime installer finished on ${user}@${host}."
  return 0
}

nodes_log() {
  install -d -m 0750 -o root -g root "$LOG_DIR" 2>/dev/null || true
  printf '[%s] %s\n' "$(date '+%F %T%z')" "$*" >>"${LOG_DIR}/nodes.log" 2>/dev/null || true
  log "NODES $*"
}

# --- the node interface of a loaded panel ----------------------------------
#
# Every panel exposes the same node interface from its own nodes/module.sh. The
# functions below are the shared implementation that a panel module delegates
# to; a panel whose API differs replaces the function it needs, so no panel is
# special cased here.

node_generic_api_available() {
  node_panel_supports_nodes "${PANEL_NAME:-}" || return 1
  nodes_api_base "${PANEL_NAME:-}" >/dev/null 2>&1 || return 1
  return 0
}

node_generic_list() { nodes_panel_list "$PANEL_NAME"; }
node_generic_register() { nodes_panel_add "$PANEL_NAME" "$@"; }
node_generic_deregister() { nodes_panel_remove "$PANEL_NAME" "$(node_record_identifier "$PANEL_NAME" "$1")"; }
node_generic_restart() { nodes_panel_restart "$PANEL_NAME" "$(node_record_identifier "$PANEL_NAME" "$1")"; }
node_generic_show() { nodes_panel_detail "$PANEL_NAME" "$(node_record_identifier "$PANEL_NAME" "$1")"; }
node_generic_logs() { nodes_panel_logs "$PANEL_NAME" "$(node_record_identifier "$PANEL_NAME" "$1")"; }

node_generic_state() {
  local name="$1" body field
  field="$(panel_meta_get "$PANEL_NAME" nodes.detail_status_field 2>/dev/null)"
  [[ -n "$field" ]] || field="status"
  if ! body="$(nodes_panel_detail "$PANEL_NAME" "$(node_record_identifier "$PANEL_NAME" "$name")" 2>/dev/null)"; then
    printf 'unreachable\n'
    return 0
  fi
  printf '%s\n' "$(printf '%s' "$body" | api_json_value "$field" 2>/dev/null || true)"
}
