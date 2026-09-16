#!/usr/bin/env bash
set -Eeuo pipefail

# Marzban node interface.
#
# Marzban manages remote workers through Marzban-node. BaToHub reaches the panel
# API on the loopback address, opens a session with the panel's own administrator
# credentials, and registers, restarts, inspects or deregisters a node through
# that API. Marzban addresses a node by its record id, so the id the panel
# returns at registration is stored with the node record and used afterwards.
#
# The endpoint paths, the login request and the registration body are declared in
# panel.json, so a panel version that expects different fields is corrected in
# metadata, or in ${CONFIG_DIR}/nodes.conf, rather than in this file.

node_api_available() { node_generic_api_available; }

node_list() { node_generic_list; }

node_register() { node_generic_register "$@"; }

node_deregister() { node_generic_deregister "$1"; }

node_restart() { node_generic_restart "$1"; }

node_show() { node_generic_show "$1"; }

node_logs() { node_generic_logs "$1"; }

node_state() { node_generic_state "$1"; }
