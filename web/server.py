#!/usr/bin/env python3
"""The SBM cover page and idea box.

Deliberately stdlib-only: this runs on the same little box as the game server,
which has Python but no Node and no spare cores. It serves the static page and
accepts idea submissions, appending each to a JSONL queue. Nothing here decides
anything - an agent enriches the queue later, a human triages, and only then
does an idea become a GitHub issue.

Submissions are UNTRUSTED public input. They are length-capped, stripped of
control characters, and stored as data. The agent that reads them must treat
them as data too, never as instructions.
"""
import json
import os
import re
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

HERE = Path(__file__).resolve().parent
PUBLIC = HERE / "public"
DATA = Path(os.environ.get("SBM_DATA", HERE / "submissions"))
QUEUE = DATA / "incoming.jsonl"

HOST = os.environ.get("SBM_HOST", "0.0.0.0")
PORT = int(os.environ.get("SBM_PORT", "8099"))

MAX_BODY = 8 * 1024          # bytes; an idea is a sentence, not a novel
MAX_IDEA = 1500              # characters
MAX_NAME = 40
RATE_MAX = 6                 # submissions...
RATE_WINDOW = 3600           # ...per IP per hour

MODES = {"any", "infected", "pint", "chase", "squadmate", "nick-of-time", "new-mode"}

CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

DATA.mkdir(parents=True, exist_ok=True)

_hits: dict[str, list[float]] = {}
_lock = Lock()


def clean(text: str, limit: int) -> str:
    text = CONTROL.sub("", str(text)).strip()
    return text[:limit]


def rate_ok(ip: str) -> bool:
    now = time.time()
    with _lock:
        seen = [t for t in _hits.get(ip, []) if now - t < RATE_WINDOW]
        if len(seen) >= RATE_MAX:
            _hits[ip] = seen
            return False
        seen.append(now)
        _hits[ip] = seen
        return True


class Handler(BaseHTTPRequestHandler):
    server_version = "sbm/1.0"

    def log_message(self, fmt, *args):  # quieter default logging
        print(f"[web] {self.address_string()} {fmt % args}")

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (extra or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def client_ip(self) -> str:
        # Behind Cloudflare, the real client is in this header; fall back to the
        # socket for direct LAN access.
        return self.headers.get("CF-Connecting-IP") or self.client_address[0]

    # ---- static files ----

    def do_GET(self):
        route = self.path.split("?", 1)[0]

        if route in ("/", ""):
            route = "/index.html"
        if route == "/api/health":
            return self._send(200, b'{"ok":true}', "application/json")

        target = (PUBLIC / route.lstrip("/")).resolve()

        # No escaping the public directory.
        if not str(target).startswith(str(PUBLIC)) or not target.is_file():
            return self._send(404, b"not found")

        ctype = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".svg": "image/svg+xml",
            ".png": "image/png",
            ".ico": "image/x-icon",
        }.get(target.suffix, "application/octet-stream")

        self._send(200, target.read_bytes(), ctype)

    # ---- idea submissions ----

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/idea":
            return self._send(404, b"not found")

        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > MAX_BODY:
            return self._reject("that idea is the wrong size")

        ip = self.client_ip()
        if not rate_ok(ip):
            return self._reject("steady on - a few ideas an hour is plenty", 429)

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return self._reject("could not read that")

        # Honeypot: a hidden field only a bot would fill.
        if payload.get("website"):
            return self._send(200, b'{"ok":true}', "application/json")  # pretend success

        idea = clean(payload.get("idea", ""), MAX_IDEA)
        name = clean(payload.get("name", ""), MAX_NAME) or "anon"
        mode = payload.get("mode", "any")
        if mode not in MODES:
            mode = "any"

        if len(idea) < 3:
            return self._reject("needs a few more words than that")

        record = {
            "t": datetime.now(timezone.utc).isoformat(),
            "name": name,
            "mode": mode,
            "idea": idea,
            "ip": ip,
            "status": "new",
        }

        with _lock, QUEUE.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")

        print(f"[web] idea from {name} ({mode}): {idea[:80]}")
        self._send(200, b'{"ok":true}', "application/json")

    def _reject(self, message, code=400):
        body = json.dumps({"ok": False, "error": message}).encode("utf-8")
        self._send(code, body, "application/json")


def main():
    print(f"[web] serving {PUBLIC} on {HOST}:{PORT}, queue at {QUEUE}")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[web] stopped")
