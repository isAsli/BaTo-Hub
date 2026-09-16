#!/usr/bin/env bash
set -Eeuo pipefail

# Migration between panels.
#
# A migration reads what the source panel publishes, maps it to the shape the
# destination panel expects, shows the operator what will be created, backs up
# both panels, writes the records one at a time and then reads the destination
# back. Nothing on the source is ever changed or deleted.
#
# Two shapes exist, and they are not interchangeable:
#
#   users     a flat list of accounts, as Marzban, PasarGuard and Rebecca publish
#             them. Every pair of panels in this group can be migrated.
#   inbounds  clients kept inside inbounds, as 3X-UI and VPN-UI store them. A
#             migration in this group copies whole inbounds.
#
# A migration between the two groups is refused with an explanation, because
# approximating one shape with the other would silently invent configuration.

MIGRATION_STATE_SUBDIR="migrations"

migration_dir() { printf '%s/%s\n' "$STATE_DIR" "$MIGRATION_STATE_SUBDIR"; }

migration_mode() {
  local mode
  mode="$(panel_meta_get "${1:-}" users.mode 2>/dev/null)"
  printf '%s\n' "${mode:-none}"
}

# A pair is supported when both panels publish the same shape.
migration_pair_supported() {
  local source="$1" destination="$2" source_mode destination_mode
  panel_exists "$source" || {
    err "Unsupported panel: $source"
    return 1
  }
  panel_exists "$destination" || {
    err "Unsupported panel: $destination"
    return 1
  }
  [[ "$source" != "$destination" ]] || {
    err "The source and the destination are the same panel: ${source}"
    return 1
  }
  source_mode="$(migration_mode "$source")"
  destination_mode="$(migration_mode "$destination")"
  if [[ "$source_mode" == "none" || "$destination_mode" == "none" ]]; then
    err "One of these panels does not publish a migration interface."
    return 1
  fi
  if [[ "$source_mode" != "$destination_mode" ]]; then
    err "$(panel_display_for "$source") stores its clients as ${source_mode}, and $(panel_display_for "$destination") stores them as ${destination_mode}."
    err "The two shapes are not interchangeable, so this migration is not offered."
    err "Move the clients into the destination panel with that panel's own tooling, or migrate between two panels of the same family."
    return 1
  fi
  return 0
}

# The names a migration is offered for, computed from the metadata rather than
# written down here.
migration_supported_pairs() {
  local source destination source_mode destination_mode
  while IFS= read -r source; do
    [[ -n "$source" ]] || continue
    source_mode="$(migration_mode "$source")"
    [[ "$source_mode" == "none" ]] && continue
    while IFS= read -r destination; do
      [[ -n "$destination" ]] || continue
      [[ "$source" == "$destination" ]] && continue
      destination_mode="$(migration_mode "$destination")"
      [[ "$destination_mode" == "$source_mode" ]] || continue
      printf '%s -> %s (%s)\n' "$source" "$destination" "$source_mode"
    done < <(loader_panels)
  done < <(loader_panels)
  return 0
}

# Reads the source and writes one tab separated line per record into a file with
# mode 0600. The line is the record itself, so a later step never has to consult
# the source panel again.
migration_export() {
  local source="$1" target="$2" url
  local -a fields=()
  local mode
  mode="$(migration_mode "$source")"
  [[ "$mode" != "none" ]] || {
    err "Panel ${source} does not publish a migration interface."
    return 1
  }
  install -d -m 0750 -o root -g root "$(migration_dir)"
  url="$(nodes_endpoint "$source" "" 2>/dev/null || true)"
  url="${url:-$(nodes_api_base "$source")$(panel_meta_get "$source" users.list_path)}"
  while IFS= read -r field; do
    [[ -n "$field" ]] && fields+=("$field")
  done < <(panel_meta_list "$source" users.list_fields 2>/dev/null || true)
  nodes_api_call "$source" GET "$url" || return 1
  nodes_api_succeeded || return 1
  if [[ "$mode" == "users" ]]; then
    [[ "${#fields[@]}" -gt 0 ]] || fields=(username status expire data_limit used_traffic)
    printf '%s' "$API_BODY" |
      api_json_rows "$(panel_meta_get "$source" users.list_container 2>/dev/null || printf '')" "${fields[@]}" \
        >"$target" || return 1
  else
    # An inbound is copied whole, so the export keeps the complete object.
    printf '%s' "$API_BODY" | python3 -c '
import json
import sys

container = sys.argv[1] if len(sys.argv) > 1 else ""
raw = sys.stdin.read()
try:
    value = json.loads(raw) if raw.strip() else []
except ValueError:
    raise SystemExit(2)
for part in [p for p in container.split(".") if p]:
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        raise SystemExit(1)
if not isinstance(value, list):
    raise SystemExit(1)
for item in value:
    print(json.dumps(item, separators=(",", ":")))
' "$(panel_meta_get "$source" users.list_container 2>/dev/null || printf '')" >"$target" || return 1
  fi
  chmod 0600 "$target"
  chown root:root "$target" 2>/dev/null || true
  return 0
}

migration_record_count() {
  local file="$1"
  [[ -r "$file" ]] || {
    printf '0\n'
    return 0
  }
  grep -c . "$file" 2>/dev/null || printf '0\n'
  return 0
}

# The identifier of a record: the username for a user list, the inbound remark
# for an inbound list. It is what the operator sees in the preview and in the
# report of records that could not be migrated.
migration_record_id() {
  local mode="$1" line="$2"
  if [[ "$mode" == "users" ]]; then
    printf '%s\n' "${line%%$'\t'*}"
    return 0
  fi
  printf '%s' "$line" | api_json_value remark 2>/dev/null || true
  printf '\n'
}

migration_preview() {
  local source="$1" destination="$2" file="$3" mode="$4"
  local count line id index=0
  count="$(migration_record_count "$file")"
  printf 'Source: %s (%s)\n' "$(panel_display_for "$source")" "$mode"
  printf 'Destination: %s\n' "$(panel_display_for "$destination")"
  printf 'Records read: %s\n\n' "$count"
  if [[ "$count" -eq 0 ]]; then
    warn "The source panel published no record, so there is nothing to migrate."
    return 1
  fi
  printf 'Records that will be created in the destination:\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    index=$((index + 1))
    id="$(migration_record_id "$mode" "$line")"
    if [[ "$index" -le 20 ]]; then
      printf '  %s\n' "${id:-<unnamed>}"
    fi
  done <"$file"
  if [[ "$count" -gt 20 ]]; then
    printf '  ... and %s more\n' "$((count - 20))"
  fi
  printf '\nNothing was written to the destination yet.\n'
  return 0
}

# The body of a create request for one exported record.
migration_create_body() {
  local destination="$1" mode="$2" line="$3" template
  if [[ "$mode" == "inbounds" ]]; then
    # The inbound keeps its structure and receives a new identifier, so the
    # destination never has to resolve a collision on the source's identifier.
    printf '%s' "$line" | python3 -c '
import json
import secrets
import sys

raw = sys.stdin.read()
try:
    value = json.loads(raw)
except ValueError:
    raise SystemExit(2)
if not isinstance(value, dict):
    raise SystemExit(2)
value["id"] = secrets.randbelow(900000000) + 100000000
sys.stdout.write(json.dumps(value, separators=(",", ":")))
'
    return $?
  fi
  template="$(panel_meta_get "$destination" users.create_body 2>/dev/null)"
  [[ -n "$template" ]] || {
    err "Panel ${destination} does not declare the body of a user creation."
    return 1
  }
  migration_fill_user_body "$template" "$line"
}

# Substitutes one exported user record into the destination's body template.
# Text fields are quoted as JSON strings, numeric fields are written as numbers
# with an empty value becoming zero, so a missing value cannot produce invalid
# JSON.
migration_fill_user_body() {
  local template="$1" line="$2"
  python3 -c '
import json
import sys

template = sys.argv[1]
fields = sys.argv[2].split("\t")

def take(index):
    return fields[index] if index < len(fields) else ""

def number(value):
    value = (value or "").strip()
    try:
        return int(value)
    except ValueError:
        return 0

values = {
    "{username}": json.dumps(take(0)),
    "{status}": json.dumps(take(1) or "active"),
    "{expire}": str(number(take(2))),
    "{data_limit}": str(number(take(3))),
    "{used_traffic}": str(number(take(4))),
}
body = template
for key, value in values.items():
    body = body.replace(key, value)
sys.stdout.write(body)
' "$template" "$line"
}

# Creates one record in the destination. A record whose identifier already
# exists is skipped with a reason instead of being overwritten.
migration_create_record() {
  local destination="$1" mode="$2" line="$3" url body
  url="$(nodes_api_base "$destination")$(panel_meta_get "$destination" users.create_path)"
  body="$(migration_create_body "$destination" "$mode" "$line")" || {
    err "The record could not be mapped to the destination format."
    return 1
  }
  nodes_api_call "$destination" POST "$url" "$body" || return 1
  if ! api_status_ok; then
    printf '%s\n' "$(printf '%s' "${API_BODY:-}" | api_json_value detail 2>/dev/null || true)"
    return 1
  fi
  return 0
}

# Reads the destination back and counts how many of the migrated identifiers are
# present. The count is what the report states, so an unverified claim is never
# printed.
migration_verify() {
  local destination="$1" mode="$2" file="$3" url found=0 expected=0 id line
  local -a fields=()
  url="$(nodes_api_base "$destination")$(panel_meta_get "$destination" users.list_path)"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    expected=$((expected + 1))
  done <"$file"
  if [[ "$mode" == "users" ]]; then
    while IFS= read -r field; do
      [[ -n "$field" ]] && fields+=("$field")
    done < <(panel_meta_list "$destination" users.list_fields 2>/dev/null || true)
    [[ "${#fields[@]}" -gt 0 ]] || fields=(username status expire data_limit used_traffic)
  fi
  nodes_api_call "$destination" GET "$url" || return 1
  nodes_api_succeeded || return 1
  local listing
  if [[ "$mode" == "users" ]]; then
    listing="$(printf '%s' "$API_BODY" | api_json_rows \
      "$(panel_meta_get "$destination" users.list_container 2>/dev/null || printf '')" "${fields[0]}" | cut -f1)"
  else
    listing="$(printf '%s' "$API_BODY" | python3 -c '
import json
import sys

container = sys.argv[1] if len(sys.argv) > 1 else ""
raw = sys.stdin.read()
try:
    value = json.loads(raw) if raw.strip() else []
except ValueError:
    raise SystemExit(2)
for part in [p for p in container.split(".") if p]:
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        raise SystemExit(1)
if not isinstance(value, list):
    raise SystemExit(1)
for item in value:
    print(item.get("remark", ""))
' "$(panel_meta_get "$destination" users.list_container 2>/dev/null || printf '')")"
  fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="$(migration_record_id "$mode" "$line")"
    [[ -n "$id" ]] || continue
    if grep -Fxq "$id" <<<"$listing"; then
      found=$((found + 1))
    fi
  done <"$file"
  printf 'Verified in %s: %s of %s records\n' "$(panel_display_for "$destination")" "$found" "$expected"
  [[ "$found" -eq "$expected" ]]
}
