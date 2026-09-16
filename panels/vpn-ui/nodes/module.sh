#!/usr/bin/env bash
set -Eeuo pipefail

# VPN-UI node interface.
#
# VPN-UI answers its API on the loopback address after a session login and keeps
# the session in a cookie. BaToHub performs that login once per command, holds
# the cookie in a 0600 temporary file and removes it when the command finishes.
#
# VPN-UI does not publish a node installer script, so the connection information
# is printed for the operator to use on the remote machine and BaToHub reports
# that no installer URL is declared instead of inventing one. The endpoint paths
# and the registration body are declared in panel.json and can be overridden in
# ${CONFIG_DIR}/nodes.conf.

node_api_available() { node_generic_api_available; }

node_list() { node_generic_list; }

node_register() { node_generic_register "$@"; }

node_deregister() { node_generic_deregister "$1"; }

node_restart() { node_generic_restart "$1"; }

node_show() { node_generic_show "$1"; }

node_logs() { node_generic_logs "$1"; }

node_state() { node_generic_state "$1"; }
