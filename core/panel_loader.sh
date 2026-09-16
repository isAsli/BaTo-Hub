#!/usr/bin/env bash
set -Eeuo pipefail

# Panel and tool discovery.
#
# Panels are discovered from the presence of panels/<name>/panel.json and
# panels/<name>/module.sh. Tools are discovered the same way under tools/.
# Nothing is registered in a central list, so adding a directory is enough for
# BaToHub to see a new panel or tool.

PANEL_INTERFACE_FUNCTIONS=(
  panel_detect
  panel_version
  panel_available_versions
  panel_install_version
  panel_status
  panel_install
  panel_uninstall
  panel_ssl_issue
  panel_ssl_renew
  panel_ssl_status
  panel_ssl_remove
  panel_template_apply
  panel_template_remove
  panel_template_status
  panel_update
  panel_logs
  panel_menu
)

TOOL_INTERFACE_FUNCTIONS=(
  tool_detect
  tool_version
  tool_status
  tool_install
  tool_update
  tool_logs
  tool_configure
  tool_uninstall
  tool_menu
)

loader_panels() {
  local metadata
  shopt -s nullglob
  for metadata in "${PANEL_DIR}"/*/panel.json; do
    basename "$(dirname "$metadata")"
  done
  shopt -u nullglob
}

loader_tools() {
  local metadata
  shopt -s nullglob
  for metadata in "${TOOL_DIR}"/*/tool.json; do
    basename "$(dirname "$metadata")"
  done
  shopt -u nullglob
}

loader_validate_panel() {
  local name="$1" fn missing=0
  for fn in "${PANEL_INTERFACE_FUNCTIONS[@]}"; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      err "Panel ${name} does not export ${fn}."
      missing=1
    fi
  done
  return "$missing"
}

loader_load_panel() {
  local name="$1"
  valid_panel_name "$name" || {
    err "Invalid panel name: $name"
    return 1
  }
  panel_load "$name" || return 1
  loader_validate_panel "$name" || return 1
  return 0
}

loader_validate_panel_files() {
  local name="$1" sub missing=0
  for sub in module.sh panel.json ssl/module.sh templates/module.sh update/module.sh menu/module.sh; do
    if [[ ! -r "${PANEL_DIR}/${name}/${sub}" ]]; then
      err "Panel ${name} is missing required file: ${sub}"
      missing=1
    fi
  done
  return "$missing"
}

tool_exists() {
  [[ -r "${TOOL_DIR}/${1}/tool.json" && -r "${TOOL_DIR}/${1}/module.sh" ]]
}

tool_load() {
  local name="$1"
  tool_exists "$name" || {
    err "Tool is not available in this BaToHub release: $name"
    return 1
  }
  export TOOL_NAME TOOL_JSON TOOL_MODULE_DIR TOOL_DISPLAY TOOL_SUBMODULES
  TOOL_NAME="$name"
  TOOL_JSON="${TOOL_DIR}/${name}/tool.json"
  TOOL_MODULE_DIR="${TOOL_DIR}/${name}"
  TOOL_DISPLAY="$(json_get "$TOOL_JSON" display_name)"
  TOOL_SUBMODULES=""
  # shellcheck source=/dev/null
  source "${TOOL_MODULE_DIR}/module.sh"
}

tool_submodule() {
  local sub="$1" file
  file="${TOOL_MODULE_DIR}/${sub}/module.sh"
  [[ -r "$file" ]] || {
    err "Tool ${TOOL_NAME} has no ${sub} module in this release."
    return 1
  }
  case " ${TOOL_SUBMODULES:-} " in
  *" ${sub} "*) return 0 ;;
  esac
  # shellcheck source=/dev/null
  source "$file"
  TOOL_SUBMODULES="${TOOL_SUBMODULES:-} ${sub}"
}

loader_validate_tool() {
  local name="$1" fn missing=0
  for fn in "${TOOL_INTERFACE_FUNCTIONS[@]}"; do
    if ! declare -F "$fn" >/dev/null 2>&1; then
      err "Tool ${name} does not export ${fn}."
      missing=1
    fi
  done
  return "$missing"
}

loader_validate_all() {
  # Used by the installer and by the integrity report: every shipped panel and
  # tool is loaded once and checked against the documented interface.
  local name status=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if (loader_load_panel "$name") >/dev/null 2>&1; then
      printf 'panel %-12s interface ok\n' "$name"
    else
      printf 'panel %-12s interface FAILED\n' "$name"
      status=1
    fi
  done < <(loader_panels)

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if (tool_load "$name" && loader_validate_tool "$name") >/dev/null 2>&1; then
      printf 'tool  %-12s interface ok\n' "$name"
    else
      printf 'tool  %-12s interface FAILED\n' "$name"
      status=1
    fi
  done < <(loader_tools)
  return "$status"
}
