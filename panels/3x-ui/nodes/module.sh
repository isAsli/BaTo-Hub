#!/usr/bin/env bash
set -Eeuo pipefail

# 3X-UI node interface.
#
# 3X-UI answers its API on the loopback address after a session login, and keeps
# the session in a cookie. BaToHub performs that login once per command, holds
# the cookie in a 0600 temporary file and removes it when the command finishes,
# so no session credential is written to disk permanently or passed on a command
# line.
#
# The endpoint paths, the login request and the registration body are declared in
# panel.json, so a 3X-UI version that expects different fields is corrected in
# metadata, or in ${CONFIG_DIR}/nodes.conf, rather than in this file.

node_api_available() { node_generic_api_available; }

node_list() { node_generic_list; }

node_register() { node_generic_register "$@"; }

node_deregister() { node_generic_deregister "$1"; }

node_restart() { node_generic_restart "$1"; }

node_show() { node_generic_show "$1"; }

node_logs() { node_generic_logs "$1"; }

node_state() { node_generic_state "$1"; }
