#!/usr/bin/env bash
#
# Pull profiles.json off the scope box and merge self-serve fields (fivem,
# discord, colour) into the crew roster. Only fields a profile actually set
# are overwritten; everything else on a crew entry - angle, owns, order,
# the _comment - is left alone. Profiles with no matching crew "owner" are
# skipped and reported, never invented.
#
#   scope-web/sync-roster.sh
#   CT=<id> ROSTER=<path> scope-web/sync-roster.sh
#
# This script NEVER commits. Review the printed diff, then commit roster.json
# yourself.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:?set CT to the scope container id}"
REMOTE="${REMOTE:-/opt/sbm-scope/data/profiles.json}"
ROSTER="${ROSTER:-$HOME/projects/stokeback-production/roster.json}"

HERE="$(cd "$(dirname "$0")" && pwd)"

[[ -f "$ROSTER" ]] || { echo "no such roster: $ROSTER" >&2; exit 1; }

profiles="$(mktemp)"
trap 'rm -f "$profiles"' EXIT

echo "==> pulling profiles.json from CT${CT}"
if ! ssh "$PROX" "pct exec $CT -- cat $REMOTE" > "$profiles" 2>/dev/null; then
  echo "no profiles.json on the box yet - nobody has saved details"
  exit 0
fi

if [[ ! -s "$profiles" ]]; then
  echo "profiles.json is empty - nobody has saved details"
  exit 0
fi

python3 "$HERE/sync_roster.py" "$profiles" "$ROSTER"
