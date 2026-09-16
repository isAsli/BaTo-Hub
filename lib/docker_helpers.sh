#!/usr/bin/env bash
set -Eeuo pipefail

# Docker support.
#
# A panel can be installed natively or as a container, and the two require
# different operations: a native installation is driven through systemd, a
# container through the Docker CLI. The detection below never guesses:
#
#   - a panel is only treated as a container when a container that belongs to it
#     is actually present, as its declared container name or as a container whose
#     name or image identifies that panel;
#   - a panel is only treated as native when no such container exists. Docker
#     being installed says nothing, and Docker being absent says nothing either.
#
# Nothing here removes a container, an image or a volume. Updating a container
# runs `docker compose pull` and `docker compose up -d` on the compose file the
# panel itself declares, which recreates the service and keeps its named volumes.

DOCKER_BIN="${DOCKER_BIN:-docker}"

docker_available() {
  need_cmd "$DOCKER_BIN" || return 1
  "$DOCKER_BIN" info >/dev/null 2>&1
}

docker_container_exists() {
  local name="$1"
  [[ -n "$name" ]] || return 1
  docker_available || return 1
  "$DOCKER_BIN" inspect --type container "$name" >/dev/null 2>&1
}

# The container name of a panel: the declared name when that container exists,
# otherwise a container whose name or image identifies the panel. A panel that
# declares no container and has no matching container prints nothing.
docker_panel_container() {
  local panel="${1:-}" declared candidate name image
  [[ -n "$panel" ]] || return 1
  if ! docker_available; then
    return 1
  fi
  if [[ "$(panel_meta_get "$panel" supports_docker 2>/dev/null)" != "true" ]]; then
    return 1
  fi
  declared="$(panel_meta_get "$panel" docker_container_name 2>/dev/null)"
  if [[ -n "$declared" ]] && docker_container_exists "$declared"; then
    printf '%s\n' "$declared"
    return 0
  fi
  while IFS=$'\t' read -r name image; do
    [[ -n "$name" ]] || continue
    candidate="$(printf '%s %s' "$name" "$image" | tr '[:upper:]' '[:lower:]')"
    case "$candidate" in
    *"$panel"*)
      printf '%s\n' "$name"
      return 0
      ;;
    esac
  done < <("$DOCKER_BIN" ps -a --format '{{.Names}}\t{{.Image}}' 2>/dev/null || true)
  return 1
}

docker_panel_runs_in_container() { docker_panel_container "${1:-}" >/dev/null 2>&1; }

docker_container_state() {
  local name="$1" state
  docker_container_exists "$name" || {
    printf 'absent\n'
    return 1
  }
  state="$("$DOCKER_BIN" inspect --format '{{.State.Status}}' "$name" 2>/dev/null || true)"
  printf '%s\n' "${state:-unknown}"
}

docker_container_image() {
  local name="$1"
  docker_container_exists "$name" || return 1
  "$DOCKER_BIN" inspect --format '{{.Config.Image}}' "$name" 2>/dev/null
}

docker_container_logs() {
  local name="$1" lines="${2:-80}"
  docker_container_exists "$name" || {
    warn "Container is not present: $name"
    return 1
  }
  "$DOCKER_BIN" logs --tail "$lines" "$name" 2>&1
}

docker_container_restart() {
  local name="$1"
  docker_container_exists "$name" || {
    err "Container is not present: $name"
    return 1
  }
  log "DOCKER restart container=${name}"
  if ! "$DOCKER_BIN" restart "$name" >>"${LOG_FILE}" 2>&1; then
    err "Restarting the container failed: $name. Output: ${LOG_FILE}"
    return 1
  fi
  ok "Container ${name} restarted."
  return 0
}

docker_container_stats() {
  local name="$1"
  docker_container_exists "$name" || {
    warn "Container is not present: $name"
    return 1
  }
  "$DOCKER_BIN" stats --no-stream --format \
    'container {{.Name}} cpu {{.CPUPerc}} memory {{.MemUsage}} network {{.NetIO}} block {{.BlockIO}}' \
    "$name" 2>/dev/null
}

# The compose file a panel declares in its own metadata, when it exists.
docker_panel_compose_file() {
  local panel="$1" path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
    *docker-compose.yml | *docker-compose.yaml | *compose.yml | *compose.yaml)
      if [[ -f "$path" ]]; then
        printf '%s\n' "$path"
        return 0
      fi
      ;;
    esac
  done < <(panel_meta_list "$panel" config_paths 2>/dev/null || true)
  return 1
}

# Recreates a container from the compose file the panel declares: the image is
# pulled, the service is recreated, and named volumes are kept because compose
# owns them. A panel without a compose file is reported instead of being updated
# by guessing its run arguments.
docker_panel_update() {
  local panel="$1" compose container
  need_root || return 1
  docker_available || {
    err "Docker is not available."
    return 1
  }
  if ! compose="$(docker_panel_compose_file "$panel")"; then
    err "Panel ${panel} declares no compose file, so BaToHub will not recreate its container."
    err "Update the container with the tooling that created it."
    return 1
  fi
  container="$(docker_panel_container "$panel" || true)"
  printf 'Compose file: %s\n' "$compose"
  printf 'Container: %s\n\n' "${container:-not detected}"
  printf 'The image is pulled and the service is recreated. Named volumes are kept.\n\n'
  if ! ui_confirm "Update the container of ${panel}?"; then
    printf 'Nothing was changed.\n'
    return 0
  fi
  log "DOCKER compose pull panel=${panel} file=${compose}"
  if ! "$DOCKER_BIN" compose -f "$compose" pull >>"${LOG_FILE}" 2>&1; then
    err "Pulling the image failed. Output: ${LOG_FILE}"
    return 1
  fi
  log "DOCKER compose up panel=${panel} file=${compose}"
  if ! "$DOCKER_BIN" compose -f "$compose" up -d >>"${LOG_FILE}" 2>&1; then
    err "Recreating the service failed. Output: ${LOG_FILE}"
    return 1
  fi
  ok "Container of ${panel} was recreated from ${compose}."
  return 0
}

# Prints how a panel is installed, without asserting more than was observed.
docker_panel_mode() {
  local panel="$1" container
  if ! docker_available; then
    printf 'native\n'
    return 0
  fi
  if container="$(docker_panel_container "$panel")"; then
    printf 'container:%s\n' "$container"
    return 0
  fi
  printf 'native\n'
}
