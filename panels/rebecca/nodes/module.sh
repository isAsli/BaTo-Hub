#!/usr/bin/env bash
set -Eeuo pipefail

# Rebecca node interface.
#
# Rebecca manages remote workers through its node service. Its API is reached on
# the loopback address with an API token that BaToHub reads from Rebecca's own
# configuration; the token is never copied into a BaToHub record and never
# logged.
#
# The endpoint paths and the registration body are declared in panel.json, so a
# Rebecca version that expects different fields is corrected in metadata, or in
# ${CONFIG_DIR}/nodes.conf, rather than in this file.

node_api_available() { node_generic_api_available; }

node_list() { node_generic_list; }

node_register() { node_generic_register "$@"; }

node_deregister() { node_generic_deregister "$1"; }

node_restart() { node_generic_restart "$1"; }

node_show() { node_generic_show "$1"; }

node_logs() { node_generic_logs "$1"; }

node_state() { node_generic_state "$1"; }
