# scope-web — the SBM scope board

A tiny stdlib-only web app (its own slim LXC, Debian 12, `python3`, nothing
else) with two jobs:

1. **Tag board** (`/`) — who's in the game right now, live position via the
   FiveM telemetry endpoint. Anyone with a token can tag a player's current
   spot with a role + note, filed under a gametype. Tags are **verified map
   coordinates**: the build agents are forbidden from guessing coords, so
   these tags are what makes location work automatable.
2. **Scope form** (`/scope`) — a long-form, autosaving, resumable
   scope-of-work document per owner per gametype. Submit files a snapshot for
   the pull→promote pipeline below.

No accounts, no sessions: a token in `tokens.json` IS the identity. Adding an
owner is one line in that file.

## tokens.json (hand-created on the box, NEVER in the repo)

At `/opt/sbm-scope/data/tokens.json`:

```json
{
  "K3pR9xWq2LmZ": {"owner": "darren", "fivem": "DazRave"},
  "aB7cD1eF4gH6": {"owner": "jacob",  "fivem": "Jacob"},
  "zY5xW3vU1tS9": {"owner": "rory",   "fivem": "Rory"}
}
```

One token per owner, generated like so (run once per line):

```bash
python3 -c "import secrets;print(secrets.token_urlsafe(9))"
```

Hand each owner their link: `http://<box>:8099/?key=<token>`. The file is
re-read on every request, so rotating a token needs no restart. Missing file →
the API answers 503 until it exists.

## Env vars

| var             | default                                 | what |
|-----------------|-----------------------------------------|------|
| `SCOPE_DATA`    | `./data`                                | data dir: `tokens.json`, `scopes/`, `scopes/submitted/`, `tags/` |
| `TELEMETRY_URL` | `http://192.168.0.212:30120/telemetry`  | FiveM telemetry base; `/players` is proxied from it |
| `TELEMETRY_KEY` | *(empty)*                               | sent as `?key=` to the telemetry endpoint if set |
| `PORT`          | `8099`                                  | listen port |

## Deploy

```bash
CT=<container-id> scope-web/deploy.sh
```

Tars `server.py public sbm-scope.service` to `/opt/sbm-scope` on the CT (via
the prox1 hop), installs/refreshes the systemd unit, restarts, curls
`/api/health`. The data dir is never touched.

## Pull → promote

```bash
CT=<container-id> scope-web/pull-scopes.sh
# → submissions/scopes/submitted/*.json and submissions/tags/*.json

scope-web/render_scope.py submissions/scopes/submitted/<file>.json   # eyeball it

scope-web/promote-scope.sh submissions/scopes/submitted/<file>.json
# → docs/modes/<slug>.md (the living design doc, commit it yourself)
# → gh label mode:<slug> + gh issue on dazrave/stokeback-gtai
# → JSON archived to submissions/scopes/promoted/
```

The render is verbatim — the owner's words under fixed headings, locations as
a coordinate table. Nothing is summarised; that's the house rule.

## Public URLs

The app shares `sbm.dazrave.uk` with the idea box, path-routed by
nginx-master (CT120, `/etc/nginx/snippets/sbm-scope.conf`, included from the
`sbm_dazrave_uk.conf` vhost):

- Tag board: `https://sbm.dazrave.uk/tag?key=<token>`
- Scope form: `https://sbm.dazrave.uk/scope?key=<token>`
- `/api/players|gametypes|tag|tags|scope*` → this app; everything else,
  including `/` and `/api/idea`, stays the idea box on CT212.

The LAN URL also works: `http://<ct-ip>:8099/?key=<token>` (the tag board
answers at both `/` and `/tag`).
