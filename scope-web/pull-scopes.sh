#!/usr/bin/env bash
#
# Copy submitted scopes and tags off the scope box for triage.
#
#   CT=<id> scope-web/pull-scopes.sh
#
# Pulls data/scopes/submitted/ and data/tags/ into the local (gitignored)
# ./submissions/ directory. The box is the source of truth; this is a
# read-only pull.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:?set CT to the scope container id}"
REMOTE="${REMOTE:-/opt/sbm-scope/data}"

cd "$(dirname "$0")"
mkdir -p submissions

ssh "$PROX" "pct exec $CT -- bash -c 'cd $REMOTE && tar czf - scopes/submitted tags 2>/dev/null'" \
  | tar xzf - -C submissions 2>/dev/null || {
    echo "nothing submitted yet"; exit 0;
  }

scopes=$(find submissions/scopes/submitted -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
tags=$(find submissions/tags -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
echo "pulled $scopes submitted scope(s) and $tags tag file(s) into submissions/"
echo "next: scope-web/promote-scope.sh submissions/scopes/submitted/<file>.json"
