#!/usr/bin/env python3
"""The SBM scope board: live player tagging + gametype scope forms.

Deliberately stdlib-only, same as web/server.py: this runs on a slim LXC with
Python and nothing else. It serves two pages and a small JSON API:

  - the tag page: who's in the game right now (proxied from the FiveM
    telemetry endpoint) and a way to tag a player's current spot with a role
    and a note, filed under a gametype. Tags become VERIFIED map coordinates -
    the build agents are forbidden from guessing coords, so these tags are the
    only way locations get automated.
  - the scope form: a long-form, autosaving scope-of-work document per owner
    per gametype.

There are no accounts and no sessions. A token in tokens.json IS the identity:
hand-created on the box, never in the repo, one line per owner. Everything
except /api/health requires one. Submissions are trusted-ish (mates only) but
still cleaned and capped - a token is a link in a group chat, not a vault.
"""
import json
import math
import os
import re
import secrets
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

HERE = Path(__file__).resolve().parent
PUBLIC = HERE / "public"
DATA = Path(os.environ.get("SCOPE_DATA", "./data"))
TOKENS = DATA / "tokens.json"
SCOPES = DATA / "scopes"
SUBMITTED = SCOPES / "submitted"
TAGS = DATA / "tags"
PROFILES = DATA / "profiles.json"

HOST = os.environ.get("SCOPE_HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8099"))
TELEMETRY_URL = os.environ.get("TELEMETRY_URL", "http://192.168.0.212:30120/telemetry")
TELEMETRY_KEY = os.environ.get("TELEMETRY_KEY", "")
TELEMETRY_MODE_KEY = os.environ.get("TELEMETRY_MODE_KEY", "")

MAX_BODY = 8 * 1024          # bytes; a tag is a note, not a novel
MAX_SCOPE_BODY = 64 * 1024   # bytes; the scope form alone gets the big cap
MAX_SECTION = 4000           # characters per scope section
MAX_NOTE = 300               # characters on a tag note
MAX_NAME = 64
MAX_PROFILE_FIELD = 40       # characters; fivem / discord on the profile card
RATE_MAX = 6                 # invalid-token attempts...
RATE_WINDOW = 3600           # ...per IP per hour (valid tokens are never limited)

SLUG_RE = re.compile(r"^[a-z0-9-]{1,30}$")
COLOUR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# The only roles a tag may carry. Matches the dropdown in public/tag.html.
TAG_ROLES = (
    "player spawn", "vehicle spawn", "ai spawn", "objective", "item spawn",
    "round start area", "extraction point", "safe zone", "zone boundary",
    "shop / interaction", "set dressing", "director cam", "other",
)

CONTROL = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

for d in (SCOPES, SUBMITTED, TAGS):
    d.mkdir(parents=True, exist_ok=True)

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


def load_tokens():
    """tokens.json, re-read on every request (it is tiny; rotation needs no
    restart). None means 'not configured' - missing or unreadable."""
    try:
        data = json.loads(TOKENS.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError, OSError):
        return None
    return data if isinstance(data, dict) else None


def read_json_file(path: Path, fallback):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, ValueError, OSError):
        return fallback


def write_json_atomic(path: Path, payload) -> None:
    """Temp + rename so a crash mid-write never leaves a torn file. Callers
    hold _lock, so the fixed tmp name cannot collide."""
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)


def load_profiles() -> dict:
    """profiles.json - self-serve owner details. Missing file just means
    nobody has saved one yet, so an empty dict (not None) is the fallback."""
    data = read_json_file(PROFILES, {})
    return data if isinstance(data, dict) else {}


def profile_fivem(owner: str, token_fivem) -> str:
    """The fivem name to use for this owner: their profile's, if they've set
    one, otherwise tokens.json's. This is the single place anything matching
    an owner to an in-game player should look."""
    saved = load_profiles().get(owner)
    fivem = saved.get("fivem") if isinstance(saved, dict) else None
    return fivem or clean(str(token_fivem or ""), MAX_NAME)


def profile_view(owner: str, entry: dict) -> dict:
    """The caller's profile for the API: unset fields default empty, except
    fivem, which falls back to tokens.json's (via entry, already resolved by
    _auth) so the card is never blank on someone's first visit."""
    saved = load_profiles().get(owner)
    saved = saved if isinstance(saved, dict) else {}
    return {
        "owner": owner,
        "fivem": saved.get("fivem") or (entry or {}).get("fivem", "") or "",
        "discord": saved.get("discord") or "",
        "colour": saved.get("colour") or "",
        "updated": saved.get("updated") or "",
    }


def num(value, default=None):
    try:
        value = float(value)
    except (TypeError, ValueError):
        return default
    if not math.isfinite(value):
        return default
    return round(value, 2)


def sanitise(value, depth=0):
    """Recursive per-field clean for the scope form: strings capped, numbers
    kept finite, structure depth- and width-limited. The 64KB body cap has
    already bounded the total size."""
    if depth > 5:
        return None
    if isinstance(value, str):
        return clean(value, MAX_SECTION)
    if isinstance(value, bool) or value is None:
        return value
    if isinstance(value, (int, float)):
        return num(value, 0)
    if isinstance(value, list):
        return [sanitise(v, depth + 1) for v in value[:200]]
    if isinstance(value, dict):
        return {clean(str(k), 60): sanitise(v, depth + 1)
                for k, v in list(value.items())[:60]}
    return None


# ---- telemetry proxy ----

def fetch_players() -> dict:
    """Ask the game server who is standing where. Any failure at all degrades
    to an empty list plus a soft error - the page must never break just
    because the game box is off having a lie down."""
    url = TELEMETRY_URL.rstrip("/") + "/players"
    if TELEMETRY_KEY:
        url += "?" + urllib.parse.urlencode({"key": TELEMETRY_KEY})
    try:
        with urllib.request.urlopen(url, timeout=2) as resp:
            raw = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        return {"players": [], "error": "game server not answering"}
    return {"players": normalise_players(raw)}


def normalise_players(raw) -> list:
    """The telemetry envelope may vary; accept a bare list, {players:[...]},
    or {data:{players:[...]}} and squeeze each row into a fixed shape."""
    rows = []
    if isinstance(raw, list):
        rows = raw
    elif isinstance(raw, dict):
        for key in ("players", "list"):
            if isinstance(raw.get(key), list):
                rows = raw[key]
                break
        else:
            inner = raw.get("data")
            if isinstance(inner, list):
                rows = inner
            elif isinstance(inner, dict) and isinstance(inner.get("players"), list):
                rows = inner["players"]

    players = []
    for row in rows:
        if not isinstance(row, dict):
            continue
        heading = row.get("heading", row.get("h", row.get("hdg", 0)))
        players.append({
            "name": clean(str(row.get("name", "")), MAX_NAME) or "?",
            "x": num(row.get("x"), 0.0),
            "y": num(row.get("y"), 0.0),
            "z": num(row.get("z"), 0.0),
            "heading": num(heading, 0.0),
            "street": clean(str(row.get("street") or ""), 80),
            "area": clean(str(row.get("area") or ""), 80),
        })
    return players


def fetch_modes() -> dict:
    """Ask the game server which modes exist and which one is running now.
    Same never-break-the-page contract as fetch_players(): any failure at
    all degrades to an empty list plus a soft error."""
    url = TELEMETRY_URL.rstrip("/") + "/modes"
    if TELEMETRY_MODE_KEY:
        url += "?" + urllib.parse.urlencode({"key": TELEMETRY_MODE_KEY})
    try:
        with urllib.request.urlopen(url, timeout=2) as resp:
            raw = json.loads(resp.read().decode("utf-8", "replace"))
    except Exception:
        return {"modes": [], "error": "game server not answering"}
    return {"modes": normalise_modes(raw)}


def normalise_modes(raw) -> list:
    """telemetry's /modes route already returns a clean [{id,label,running}]
    array, but the values are still someone else's JSON - clean and cap them
    the same as everything else that crosses this boundary."""
    modes = []
    if not isinstance(raw, list):
        return modes
    for row in raw:
        if not isinstance(row, dict):
            continue
        modes.append({
            "id": clean(str(row.get("id", "")), 30),
            "label": clean(str(row.get("label") or row.get("id") or ""), 60),
            "running": bool(row.get("running")),
        })
    return modes


def switch_mode(name: str, action: str):
    """POST telemetry's /mode route. Returns (ok, payload) - payload is
    whatever telemetry replied with, ok is whether it was a 2xx - or None if
    the game server didn't answer at all. Unlike the read-only proxies this
    can't just degrade quietly: the caller needs to know whether the switch
    actually landed.

    The key rides the query string, same as every other telemetry route -
    telemetry's keyed() helper only ever looks at the URL, never the body."""
    url = TELEMETRY_URL.rstrip("/") + "/mode"
    if TELEMETRY_MODE_KEY:
        url += "?" + urllib.parse.urlencode({"key": TELEMETRY_MODE_KEY})
    body = json.dumps({"name": name, "action": action}).encode("utf-8")
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return True, json.loads(resp.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        try:
            payload = json.loads(e.read().decode("utf-8", "replace"))
        except Exception:
            payload = {"ok": False, "error": f"telemetry returned {e.code}"}
        return False, payload
    except Exception:
        return None


# ---- AI briefing injection ----

AI_CONTEXT_MARKER = b"<!--AI_CONTEXT-->"
SCRIPT_CLOSE_RE = re.compile(rb"</script", re.IGNORECASE)


def inject_ai_context(html: bytes) -> bytes:
    """scope.html carries a literal AI_CONTEXT_MARKER inside a text/markdown
    script tag; swap in the briefing doc fresh on every request, so a
    chatbot fetching the raw form URL gets the full project context.
    scope-context.md is the single source of truth - read fresh each time
    since it is tiny and rarely changes."""
    if AI_CONTEXT_MARKER not in html:
        return html
    try:
        md = (PUBLIC / "scope-context.md").read_bytes()
    except OSError:
        return html
    md = SCRIPT_CLOSE_RE.sub(lambda m: b"<\\/script", md)  # never let it close our tag early
    return html.replace(AI_CONTEXT_MARKER, md)


class Handler(BaseHTTPRequestHandler):
    server_version = "sbm-scope/1.0"

    def log_message(self, fmt, *args):  # quieter default logging
        print(f"[scope] {self.address_string()} {fmt % args}")

    def _send(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, payload, code=200):
        self._send(code, json.dumps(payload, ensure_ascii=False).encode("utf-8"),
                   "application/json")

    def _reject(self, message, code=400):
        self._json({"ok": False, "error": message}, code)

    def client_ip(self) -> str:
        # Behind Cloudflare the real client is in this header; fall back to
        # the socket for direct LAN access.
        return self.headers.get("CF-Connecting-IP") or self.client_address[0]

    # ---- auth: the token IS the identity ----

    def _auth(self, key):
        """Return the token's entry ({owner, fivem}) or None after replying.
        Only INVALID attempts are rate limited - a valid token autosaving all
        evening must never trip a bucket."""
        tokens = load_tokens()
        if tokens is None:
            self._reject("not configured", 503)
            return None
        entry = tokens.get(key) if key else None
        owner = entry.get("owner") if isinstance(entry, dict) else None
        if not owner or not SLUG_RE.match(str(owner)):
            if not rate_ok(self.client_ip()):
                self._reject("steady on - that key still isn't going to work", 429)
                return None
            self._reject("that key isn't on the list", 403)
            return None
        # A saved profile's fivem name wins over tokens.json's from here on.
        return {**entry, "fivem": profile_fivem(owner, entry.get("fivem"))}

    def _read_body(self, cap):
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > cap:
            self._reject("body is the wrong size")
            return None
        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            self._reject("could not read that")
            return None
        if not isinstance(payload, dict):
            self._reject("expected a JSON object")
            return None
        return payload

    # ---- GET ----

    def do_GET(self):
        route, _, query = self.path.partition("?")
        params = urllib.parse.parse_qs(query)
        key = (params.get("key") or [""])[0]

        if route == "/api/health":
            return self._json({"ok": True})

        if route == "/api/players":
            if self._auth(key) is None:
                return
            return self._json(fetch_players())

        if route == "/api/modes":
            if self._auth(key) is None:
                return
            return self._json(fetch_modes())

        if route == "/api/gametypes":
            entry = self._auth(key)
            if entry is None:
                return
            # 'viewer' lets the tag page preselect the caller's own gametype
            # instead of silently defaulting to General (first in the list).
            return self._json({"gametypes": self.list_gametypes(),
                               "viewer": entry["owner"]})

        if route == "/api/tags":
            if self._auth(key) is None:
                return
            gametype = (params.get("gametype") or [""])[0]
            return self.get_tags(gametype)

        if route == "/api/scope":
            entry = self._auth(key)
            if entry is None:
                return
            slug = (params.get("slug") or [""])[0]
            owner = entry["owner"]
            if slug:
                # Reading a specific doc: any valid token may read any
                # owner's - the write routes stay locked to the caller.
                owner_param = (params.get("owner") or [""])[0]
                if owner_param:
                    if not SLUG_RE.match(owner_param):
                        return self._reject("that owner looks wrong")
                    owner = owner_param
            return self.get_scope(owner, slug)

        if route == "/api/scopes":
            if self._auth(key) is None:
                return
            return self._json({"scopes": self.list_all_scopes()})

        if route == "/api/profile":
            entry = self._auth(key)
            if entry is None:
                return
            return self._json(profile_view(entry["owner"], entry))

        if route == "/scope/context":
            return self.serve_scope_context()

        return self.serve_static(route)

    def serve_static(self, route):
        # "/tag" is an alias for "/" so links work both direct (LAN) and
        # path-routed behind sbm.dazrave.uk, where "/" is the idea box.
        if route in ("/", "", "/tag"):
            route = "/tag.html"
        elif route == "/scope":
            route = "/scope.html"
        elif route == "/hub":
            route = "/hub.html"

        target = (PUBLIC / route.lstrip("/")).resolve()

        # No escaping the public directory.
        if not str(target).startswith(str(PUBLIC) + os.sep) or not target.is_file():
            return self._send(404, b"not found")

        ctype = {
            ".html": "text/html; charset=utf-8",
            ".css": "text/css; charset=utf-8",
            ".js": "text/javascript; charset=utf-8",
            ".svg": "image/svg+xml",
            ".png": "image/png",
            ".ico": "image/x-icon",
        }.get(target.suffix, "application/octet-stream")

        body = target.read_bytes()
        if route == "/scope.html":
            body = inject_ai_context(body)
        self._send(200, body, ctype)

    def serve_scope_context(self):
        """The AI briefing doc, raw - no token needed, so pasting the link
        into a chatbot just works. Same file scope.html injects into
        itself, so there is exactly one place the briefing text lives."""
        path = PUBLIC / "scope-context.md"
        try:
            body = path.read_bytes()
        except OSError:
            return self._send(404, b"not found")
        self._send(200, body, "text/markdown; charset=utf-8")

    def list_gametypes(self) -> list:
        """Every scope doc plus the fixed catch-all. Tags with nowhere better
        to live go under 'general'."""
        entries = [{"owner": "sbm", "name": "General", "slug": "general",
                    "status": "fixed"}]
        for path in sorted(SCOPES.glob("*.json")):
            doc = read_json_file(path, None)
            if not isinstance(doc, dict):
                continue
            slug = doc.get("slug", "")
            if not SLUG_RE.match(str(slug)):
                continue
            entries.append({
                "owner": clean(str(doc.get("owner", "")), 30),
                "name": clean(str(doc.get("name") or slug), 80),
                "slug": slug,
                "status": clean(str(doc.get("status", "draft")), 20),
            })
        return entries

    def get_tags(self, gametype):
        if gametype:
            if not SLUG_RE.match(gametype):
                return self._reject("that gametype slug looks wrong")
            tags = read_json_file(TAGS / f"{gametype}.json", [])
            tags = tags if isinstance(tags, list) else []
            return self._json({"tags": list(reversed(tags))})

        # No gametype: everything, newest first, capped. Lets the tag page
        # show one combined 'recent tags' list.
        merged = []
        for path in TAGS.glob("*.json"):
            tags = read_json_file(path, [])
            if isinstance(tags, list):
                merged.extend(t for t in tags if isinstance(t, dict))
        merged.sort(key=lambda t: t.get("ts", 0), reverse=True)
        return self._json({"tags": merged[:200]})

    def list_all_scopes(self) -> list:
        """Every owner's scope doc for the read-only 'everyone's scopes'
        list: live drafts plus submitted snapshots, deduped by (owner,
        slug) with the most recently updated entry winning. Read-only -
        the write routes never touch anyone but the caller."""
        entries: dict[tuple, dict] = {}

        def consider(doc):
            if not isinstance(doc, dict):
                return
            owner = clean(str(doc.get("owner", "")), 30)
            slug = str(doc.get("slug", ""))
            if not owner or not SLUG_RE.match(owner) or not SLUG_RE.match(slug):
                return
            key = (owner, slug)
            updated = doc.get("updated", 0) or 0
            prev = entries.get(key)
            if prev is None or updated >= prev["updated"]:
                entries[key] = {
                    "owner": owner,
                    "name": clean(str(doc.get("name") or slug), 80),
                    "slug": slug,
                    "status": clean(str(doc.get("status", "draft")), 20),
                    "updated": updated,
                }

        for path in sorted(SCOPES.glob("*.json")):
            consider(read_json_file(path, None))
        for path in sorted(SUBMITTED.glob("*.json")):
            consider(read_json_file(path, None))

        return sorted(entries.values(), key=lambda d: d["updated"], reverse=True)

    def get_scope(self, owner, slug):
        if slug:
            if not SLUG_RE.match(slug):
                return self._reject("that slug looks wrong")
            doc = read_json_file(SCOPES / f"{owner}--{slug}.json", None)
            if not isinstance(doc, dict):
                return self._reject("no such draft", 404)
            return self._json(doc)

        drafts = []
        for path in sorted(SCOPES.glob(f"{owner}--*.json")):
            doc = read_json_file(path, None)
            if not isinstance(doc, dict):
                continue
            drafts.append({
                "slug": doc.get("slug", ""),
                "name": doc.get("name", ""),
                "status": doc.get("status", "draft"),
                "updated": doc.get("updated", 0),
            })
        drafts.sort(key=lambda d: d.get("updated", 0), reverse=True)
        return self._json({"drafts": drafts})

    # ---- POST / PUT ----

    def do_POST(self):
        route = self.path.partition("?")[0]

        if route == "/api/tag":
            return self.post_tag()
        if route == "/api/scope/submit":
            return self.post_submit()
        if route == "/api/mode":
            return self.post_mode()
        return self._send(404, b"not found")

    def do_PUT(self):
        route = self.path.partition("?")[0]

        if route == "/api/scope":
            return self.put_scope()
        if route == "/api/profile":
            return self.put_profile()
        return self._send(404, b"not found")

    def _body_and_entry(self, cap):
        """Shared preamble for the write routes: read the JSON body, then
        authenticate on its 'key' field (query-string key as a fallback)."""
        body = self._read_body(cap)
        if body is None:
            return None, None
        query = urllib.parse.parse_qs(self.path.partition("?")[2])
        key = str(body.get("key") or (query.get("key") or [""])[0])
        entry = self._auth(key)
        if entry is None:
            return None, None
        return body, entry

    def post_tag(self):
        body, entry = self._body_and_entry(MAX_BODY)
        if body is None:
            return

        gametype = str(body.get("gametype", ""))
        if not SLUG_RE.match(gametype):
            return self._reject("pick a gametype for the tag to live under")

        role = str(body.get("role", ""))
        if role not in TAG_ROLES:
            return self._reject("that role isn't on the list")

        note = clean(body.get("note", ""), MAX_NOTE)

        player = body.get("player")
        if not isinstance(player, dict):
            return self._reject("no player position attached")
        name = clean(str(player.get("name", "")), MAX_NAME)
        x, y, z = (num(player.get(k)) for k in ("x", "y", "z"))
        heading = num(player.get("heading"), 0.0)
        if not name or None in (x, y, z):
            return self._reject("that position doesn't look like coordinates")

        record = {
            "id": secrets.token_hex(4),
            "ts": int(time.time()),
            "gametype": gametype,
            "role": role,
            "note": note,
            "player": name,
            "x": x, "y": y, "z": z,
            "heading": heading,
            "street": clean(str(player.get("street") or ""), 80),
            "taggedBy": entry["owner"],
        }

        path = TAGS / f"{gametype}.json"
        with _lock:
            tags = read_json_file(path, [])
            tags = tags if isinstance(tags, list) else []
            write_json_atomic(path, tags + [record])

        print(f"[scope] tag by {entry['owner']} ({gametype}/{role}) at "
              f"{x},{y},{z}: {note[:60]}")
        return self._json({"ok": True, "tag": record})

    def post_mode(self):
        """Token-gated proxy onto telemetry's POST /mode: switch which
        gametype is running. Any valid token may do this - a mode switch
        affects the whole server, not one owner's stuff, same as a tag."""
        body, entry = self._body_and_entry(MAX_BODY)
        if body is None:
            return

        name = str(body.get("name", ""))
        if not SLUG_RE.match(name):
            return self._reject("that mode id looks wrong")

        action = str(body.get("action") or "start")
        if action not in ("start", "stop"):
            return self._reject("action must be start or stop")

        result = switch_mode(name, action)
        if result is None:
            return self._reject("game server not answering", 502)

        ok, payload = result
        print(f"[scope] {entry['owner']} switched mode -> {name} ({action}): {payload}")
        return self._json(payload, 200 if ok else 400)

    def put_scope(self):
        body, entry = self._body_and_entry(MAX_SCOPE_BODY)
        if body is None:
            return
        owner = entry["owner"]

        slug = str(body.get("slug", ""))
        if not SLUG_RE.match(slug):
            return self._reject("slug must be 1-30 of a-z, 0-9 and dashes")
        form = body.get("form")
        if not isinstance(form, dict):
            return self._reject("no form in that")
        form = sanitise(form)

        now = int(time.time())
        path = SCOPES / f"{owner}--{slug}.json"
        with _lock:
            existing = read_json_file(path, {})
            existing = existing if isinstance(existing, dict) else {}
            doc = {
                "owner": owner,
                "slug": slug,
                "name": clean(str(form.get("name") or ""), 80) or slug,
                "status": existing.get("status", "draft"),
                "created": existing.get("created", now),
                "updated": now,
                "form": form,
            }
            write_json_atomic(path, doc)

        return self._json({"ok": True, "updated": now, "status": doc["status"]})

    def post_submit(self):
        body, entry = self._body_and_entry(MAX_BODY)
        if body is None:
            return
        owner = entry["owner"]

        slug = str(body.get("slug", ""))
        if not SLUG_RE.match(slug):
            return self._reject("that slug looks wrong")

        path = SCOPES / f"{owner}--{slug}.json"
        now = int(time.time())
        stamp = time.strftime("%Y%m%d-%H%M%S", time.gmtime(now))
        snapshot = SUBMITTED / f"{stamp}-{owner}--{slug}.json"
        with _lock:
            doc = read_json_file(path, None)
            if not isinstance(doc, dict):
                return self._reject("no such draft", 404)
            doc = {**doc, "status": "submitted", "updated": now, "submitted": now}
            write_json_atomic(path, doc)
            # A fresh snapshot every submit; resubmitting is allowed and each
            # one is kept, so the pipeline never loses an earlier cut.
            write_json_atomic(snapshot, doc)

        print(f"[scope] {owner} submitted {slug} -> {snapshot.name}")
        return self._json({"ok": True, "snapshot": snapshot.name})

    def put_profile(self):
        """Fields absent from the body are left as they were - this is what
        lets the tag board's 'this is me' button send just {key, fivem}
        without clobbering a saved discord name or colour. The normal
        profile-card Save always sends all three, so that flow is
        unaffected: a full body still fully replaces the saved profile."""
        body, entry = self._body_and_entry(MAX_BODY)
        if body is None:
            return
        owner = entry["owner"]
        existing = load_profiles().get(owner)
        existing = existing if isinstance(existing, dict) else {}

        if "fivem" in body:
            fivem = clean(body.get("fivem", ""), MAX_PROFILE_FIELD)
        else:
            fivem = existing.get("fivem", "")

        if "discord" in body:
            discord = clean(body.get("discord", ""), MAX_PROFILE_FIELD)
        else:
            discord = existing.get("discord", "")

        if "colour" in body:
            colour = str(body.get("colour") or "").strip()
            if colour and not COLOUR_RE.match(colour):
                return self._reject("colour must look like #rrggbb")
        else:
            colour = existing.get("colour", "")

        now = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        saved = {"fivem": fivem, "discord": discord, "colour": colour, "updated": now}
        with _lock:
            profiles = load_profiles()
            write_json_atomic(PROFILES, {**profiles, owner: saved})

        print(f"[scope] {owner} updated their profile")
        return self._json({"ok": True, "profile": {"owner": owner, **saved}})


def main():
    print(f"[scope] serving {PUBLIC} on {HOST}:{PORT}, data in {DATA}")
    if not TOKENS.is_file():
        print(f"[scope] NOTE: {TOKENS} missing - API is 503 until it exists")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n[scope] stopped")
