#!/usr/bin/env bash
set -Eeuo pipefail

# The Docker section: how each panel is installed, and the container operations
# for the panels that run in a container.

container_state_for() {
  local panel="$1" container
  if ! container="$(docker_panel_container "$panel")"; then
    printf 'native\n'
    return 0
  fi
  docker_container_state "$container" 2>/dev/null || printf 'unknown\n'
}

containers_list_lines() {
  local name container state mode
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    mode="$(docker_panel_mode "$name")"
    if [[ "$mode" == container:* ]]; then
      container="${mode#container:}"
      state="$(docker_container_state "$container" 2>/dev/null || printf 'unknown')"
    else
      container="-"
      state="$(panel_status_text "$(panel_state_of "$name")")"
    fi
    printf '  %-10s %-16s %-18s %s\n' "$name" "$mode" "$container" "$state"
  done < <(loader_panels)
  return 0
}

containers_list_menu() {
  ui_title "Panels and containers"
  if ! docker_available; then
    warn "Docker is not available on this server, so every panel is treated as a native installation."
  fi
  printf '  %-10s %-16s %-18s %s\n' PANEL MODE CONTAINER STATE
  containers_list_lines
  pause
}

containers_choose_panel() {
  local panels=() name choice index=0
  while IFS= read -r name; do
    [[ -n "$name" ]] && panels+=("$name")
  done < <(loader_panels)
  ui_title "Choose a panel"
  for name in "${panels[@]}"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$(panel_display_for "$name")"
  done
  printf '0) Back\n'
  choice="$(ui_menu_choice)"
  [[ "$choice" == 0 ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || {
    warn "Invalid selection."
    return 1
  }
  name="${panels[$((choice - 1))]:-}"
  [[ -n "$name" ]] || {
    warn "Invalid selection."
    return 1
  }
  printf '%s\n' "$name"
}

container_show_flow() {
  local panel container
  panel="$(containers_choose_panel)" || return 0
  ui_title "Container - $(panel_display_for "$panel")"
  printf 'Panel: %s\n' "$panel"
  printf 'Declared container name: %s\n' "$(panel_meta_get "$panel" docker_container_name 2>/dev/null)"
  printf 'Supports Docker: %s\n' "$(panel_meta_get "$panel" supports_docker 2>/dev/null)"
  if ! container="$(docker_panel_container "$panel")"; then
    printf 'Mode: native\n'
    printf 'No container of this panel was found, so BaToHub manages it through systemd.\n'
    pause
    return 0
  fi
  printf 'Mode: container\n'
  printf 'Container: %s\n' "$container"
  printf 'Image: %s\n' "$(docker_container_image "$container" 2>/dev/null || printf 'unknown')"
  printf 'State: %s\n' "$(docker_container_state "$container" 2>/dev/null || printf 'unknown')"
  printf '\n'
  docker_container_stats "$container" || true
  pause
}

container_logs_flow() {
  local panel container lines
  panel="$(containers_choose_panel)" || return 0
  if ! container="$(docker_panel_container "$panel")"; then
    ui_title "Logs - $(panel_display_for "$panel")"
    panel_logs || true
    pause
    return 0
  fi
  ui_title "Container logs - $(panel_display_for "$panel")"
  lines="$(trim "$(ui_prompt 'Number of lines [80]: ' '80')")"
  [[ "$lines" =~ ^[0-9]{1,6}$ ]] || lines=80
  docker_container_logs "$container" "$lines" || true
  pause
}

container_restart_flow() {
  local panel container
  need_root || return 1
  panel="$(containers_choose_panel)" || return 0
  if ! container="$(docker_panel_container "$panel")"; then
    ui_title "Restart - $(panel_display_for "$panel")"
    warn "No container of this panel was found; restarting through systemd instead."
    panel_restart_safe || true
    pause
    return 0
  fi
  ui_title "Restart container - $(panel_display_for "$panel")"
  printf 'Container: %s\n\n' "$container"
  if ! ui_confirm "Restart the container of ${panel}?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  docker_container_restart "$container" || true
  pause
}

container_update_flow() {
  local panel
  need_root || return 1
  panel="$(containers_choose_panel)" || return 0
  ui_title "Update container - $(panel_display_for "$panel")"
  docker_panel_update "$panel" || true
  pause
}

container_menu() {
  local choice
  while true; do
    ui_title "Docker"
    printf '1) Show how every panel is installed\n'
    printf '2) Container details for one panel\n'
    printf '3) Container logs\n'
    printf '4) Restart a container\n'
    printf '5) Update a container image\n'
    printf '0) Back\n'
    choice="$(ui_menu_choice)"
    case "$choice" in
    1) containers_list_menu ;;
    2) container_show_flow ;;
    3) container_logs_flow ;;
    4) container_restart_flow ;;
    5) container_update_flow ;;
    0) return 0 ;;
    *) warn 'Invalid selection.' ;;
    esac
  done
}

# Loads the panel so its own interface is available. The container commands fall
# back to that interface when the panel does not run in a container, so the panel
# has to be loaded before either path is taken.
container_cli_panel() {
  local panel="$1"
  loader_load_panel "$panel" >/dev/null 2>&1 || {
    err "Panel could not be loaded: ${panel}"
    return 1
  }
  return 0
}

container_cli() {
  local command="${1:-}" panel="${2:-}" container
  case "$command" in
  mode)
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container mode <panel>"
      return 2
    }
    docker_panel_mode "$panel"
    ;;
  list)
    printf '  %-10s %-16s %-18s %s\n' PANEL MODE CONTAINER STATE
    containers_list_lines
    ;;
  status)
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container status <panel>"
      return 2
    }
    container_state_for "$panel"
    ;;
  logs)
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container logs <panel>"
      return 2
    }
    container_cli_panel "$panel" || return 1
    if container="$(docker_panel_container "$panel")"; then
      docker_container_logs "$container" "${3:-80}"
      return $?
    fi
    panel_logs
    ;;
  restart)
    need_root || return 1
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container restart <panel>"
      return 2
    }
    container_cli_panel "$panel" || return 1
    if container="$(docker_panel_container "$panel")"; then
      docker_container_restart "$container"
      return $?
    fi
    panel_restart_safe
    ;;
  stats)
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container stats <panel>"
      return 2
    }
    docker_container_stats "$(docker_panel_container "$panel")"
    ;;
  update)
    need_root || return 1
    [[ -n "$panel" ]] || {
      err "Usage: BaToHub --container update <panel>"
      return 2
    }
    docker_panel_update "$panel"
    ;;
  *)
    err "Unknown container command: ${command:-<none>}"
    printf 'Container commands: list, mode, status, logs, restart, stats, update\n'
    return 2
    ;;
  esac
}
