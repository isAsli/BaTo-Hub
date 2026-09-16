#!/usr/bin/env python3
"""Local service endpoints used by the integration suite.

The script implements the two external services BaToHub talks to:

  panel     the node and user endpoints a panel declares in its own panel.json
  telegram  the Bot API methods the delivery and the management bot use

Both are real HTTP services: the suite drives the shipped code against them, so
authentication, request bodies, response parsing and error handling are all
exercised. The behaviour of each panel endpoint is derived from the panel.json of
the checkout it is pointed at, so the double follows the contract that ships.

Usage: integration-stub.py panel|telegram PORT STATE_DIR CHECKOUT
Writes requests to STATE_DIR/<mode>-requests.jsonl and prints "ready" once the
socket is listening.
"""

import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODE = sys.argv[1]
PORT = int(sys.argv[2])
STATE = sys.argv[3]
CHECKOUT = sys.argv[4]
PANELS = ("rebecca", "marzban", "pasarguard", "3x-ui", "vpn-ui")

os.makedirs(STATE, exist_ok=True)
LOG = open(os.path.join(STATE, f"{MODE}-requests.jsonl"), "a", encoding="utf-8")


def metadata(panel):
    path = os.path.join(CHECKOUT, "panels", panel, "panel.json")
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


META = {panel: metadata(panel) for panel in PANELS}


def accounts():
    path = os.path.join(STATE, "accounts.json")
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


DATA_PATH = os.path.join(STATE, "panel-data.json")


def data():
    if os.path.exists(DATA_PATH):
        with open(DATA_PATH, encoding="utf-8") as handle:
            return json.load(handle)
    return {}


def save_data(payload):
    with open(DATA_PATH, "w", encoding="utf-8") as handle:
        json.dump(payload, handle)


def record(entry):
    LOG.write(json.dumps(entry) + "\n")
    LOG.flush()


def match_endpoint(template, path):
    """Returns the identifier a request carries when the path matches a template.

    A template such as "/api/node/{id}/restart" matches "/api/node/4/restart" and
    yields "4", so an endpoint is addressed the way the panel declares it.
    """
    if not template:
        return None
    pattern = re.sub(r"\{[a-z_]+\}", r"([^/]+)", template)
    match = re.match("^" + pattern + "$", path)
    return match.group(1) if match else None


def set_path(target, dotted, value):
    """Sets a dotted path such as "obj.id" in a response object."""
    parts = dotted.split(".")
    node = target
    for part in parts[:-1]:
        node = node.setdefault(part, {})
    node[parts[-1]] = value


def wrap(container, items):
    if not container:
        return items
    payload = {}
    set_path(payload, container, items)
    return payload


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        return

    def reply(self, code, payload, headers=None):
        body = payload if isinstance(payload, bytes) else json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        self.wfile.write(body)

    def fail(self, code, message):
        self.reply(code, {"detail": message})

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(length) if length else b""

    # -- panel service ----------------------------------------------------

    def panel_request(self, panel, path, method, raw):
        meta = META.get(panel, {})
        nodes = meta.get("nodes", {})
        users = meta.get("users", {})
        auth = nodes.get("api_auth", "bearer")
        account = accounts().get(panel, {})
        header = self.headers.get("Authorization") or ""
        cookie = self.headers.get("Cookie") or ""
        record({"panel": panel, "method": method, "path": path,
                "authenticated": bool(header or cookie), "bytes": len(raw)})

        endpoints = nodes.get("endpoints", {})
        login_path = endpoints.get("login", "")

        if path == login_path and method == "POST":
            text = raw.decode("utf-8", "replace")
            if f"username={account.get('user')}" not in text:
                return self.fail(401, "unknown credentials")
            if f"password={account.get('password')}" not in text:
                return self.fail(401, "unknown credentials")
            if auth == "login-cookie":
                return self.reply(200, {"success": True},
                                  {"Set-Cookie": f"SESSIONID={account.get('cookie')}; Path=/"})
            token_field = nodes.get("login_token_field", "access_token")
            return self.reply(200, {token_field: account.get("token")})

        if auth == "bearer" and header != f"Bearer {account.get('token')}":
            return self.fail(401, "not authenticated")
        if auth == "login" and header != f"Bearer {account.get('token')}":
            return self.fail(401, "not authenticated")
        if auth == "login-cookie" and f"SESSIONID={account.get('cookie')}" not in cookie:
            return self.fail(401, "not authenticated")

        state = data()
        key = f"{panel}/nodes"
        items = state.setdefault(key, account.get("nodes", []))
        user_key = f"{panel}/users"
        user_items = state.setdefault(user_key, account.get("users", []))

        if path == endpoints.get("list") and method == "GET":
            return self.reply(200, wrap(nodes.get("list_container", ""), items))
        if path == endpoints.get("add") and method == "POST":
            new_id = max([item.get("id", 0) for item in items] or [0]) + 1
            body = json.loads(raw or b"{}")
            items.append({
                "id": new_id,
                "name": body.get("name", f"node-{new_id}"),
                "address": body.get("address", ""),
                "port": body.get("port"),
                "status": "connecting",
            })
            save_data(state)
            payload = {}
            set_path(payload, nodes.get("add_id_field", "id"), new_id)
            return self.reply(200, payload)
        identifier = match_endpoint(endpoints.get("remove"), path)
        if identifier is not None and method in ("POST", "DELETE"):
            items[:] = [item for item in items if str(item.get("id")) != identifier]
            save_data(state)
            return self.reply(200, {"success": True})
        identifier = match_endpoint(endpoints.get("restart"), path)
        if identifier is not None and method == "POST":
            for item in items:
                if str(item.get("id")) == identifier:
                    item["status"] = "connected"
            save_data(state)
            return self.reply(200, {"success": True})
        identifier = match_endpoint(endpoints.get("status"), path)
        if identifier is not None and method == "GET":
            payload = {}
            set_path(payload, nodes.get("detail_status_field", "status"), "connected")
            return self.reply(200, payload)
        identifier = match_endpoint(endpoints.get("logs"), path)
        if identifier is not None and method == "GET":
            return self.reply(200, {"log": "stub node log line"})

        if path == users.get("list_path") and method == "GET":
            return self.reply(200, wrap(users.get("list_container", ""), user_items))
        if path == users.get("create_path") and method == "POST":
            body = json.loads(raw or b"{}")
            user_items.append(body)
            save_data(state)
            return self.reply(200, {"success": True})

        return self.fail(404, f"no endpoint for {method} {path}")

    # -- telegram service -------------------------------------------------

    def telegram_request(self, token, method, path, raw):
        record({"method": method, "token_ok": token == accounts().get("bot_token")})
        if token != accounts().get("bot_token"):
            return self.fail(401, "unauthorized")
        if method == "getMe":
            return self.reply(200, {"ok": True, "result": {"id": 1, "username": "batohub_test_bot"}})
        if method == "getUpdates":
            queue = accounts().get("updates", [])
            offset = int(re.search(r"offset=(\d+)", path).group(1)) if "offset=" in path else 0
            result = [item for item in queue if item["update_id"] >= offset]
            record({"method": "getUpdates", "returned": len(result)})
            return self.reply(200, {"ok": True, "result": result})
        if method == "sendMessage":
            text, chat = "", ""
            try:
                payload = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                body = raw.decode("utf-8", "replace")
                match = re.search(r'name="text"\r?\n\r?\n(.*?)\r?\n--', body, re.S)
                text = match.group(1) if match else ""
                match = re.search(r'name="chat_id"\r?\n\r?\n(.*?)\r?\n--', body, re.S)
                chat = match.group(1) if match else ""
            else:
                text = payload.get("text", "")
                chat = str(payload.get("chat_id", ""))
            record({"method": "sendMessage", "chat_id": chat, "text": text, "bytes": len(raw)})
            return self.reply(200, {"ok": True, "result": {"message_id": 1}})
        if method == "sendDocument":
            body = raw.decode("utf-8", "replace")
            match = re.search(r'filename="([^"]*)"', body)
            caption = re.search(r'name="caption"\r?\n\r?\n(.*?)\r?\n--', body, re.S)
            record({
                "method": "sendDocument",
                "filename": match.group(1) if match else "",
                "bytes": len(raw),
                "caption": caption.group(1) if caption else "",
            })
            return self.reply(200, {"ok": True, "result": {"message_id": 2}})
        record({"method": method})
        return self.reply(200, {"ok": True, "result": {}})

    def handle_request(self, method):
        parsed = self.path.split("?", 1)
        path, query = parsed[0], (parsed[1] if len(parsed) > 1 else "")
        raw = self.body()
        if MODE == "panel":
            parts = path.strip("/").split("/", 1)
            if len(parts) != 2 or parts[0] not in PANELS:
                return self.fail(404, "unknown panel")
            return self.panel_request(parts[0], "/" + parts[1], method, raw)
        match = re.match(r"^/bot([^/]+)/([A-Za-z]+)$", path)
        if not match:
            return self.fail(404, "unknown method")
        return self.telegram_request(match.group(1), match.group(2), query, raw)

    def do_GET(self):
        self.handle_request("GET")

    def do_POST(self):
        self.handle_request("POST")

    def do_DELETE(self):
        self.handle_request("DELETE")

    def do_PUT(self):
        self.handle_request("PUT")


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print("ready", flush=True)
    server.serve_forever()
