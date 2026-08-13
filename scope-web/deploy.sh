#!/usr/bin/env bash
#
# Push the scope app to its container and (re)start it.
#
#   CT=<id> scope-web/deploy.sh
#
# Installs to /opt/sbm-scope on the given CT via the prox1 hop, sets up the
# systemd service the first time, and restarts it. The data dir
# (/opt/sbm-scope/data - tokens.json, scopes, tags) is left untouched.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:?set CT to the scope container id}"
DEST="${DEST:-/opt/sbm-scope}"

cd "$(dirname "$0")"

echo "==> copying scope app to CT${CT}:${DEST}"
ssh "$PROX" "pct exec $CT -- mkdir -p $DEST/data"
tar czf - server.py public sbm-scope.service \
  | ssh "$PROX" "pct exec $CT -- tar xzf - -C $DEST"

echo "==> installing / refreshing the service"
ssh "$PROX" "pct exec $CT -- bash -c '
  cp $DEST/sbm-scope.service /etc/systemd/system/sbm-scope.service
  systemctl daemon-reload
  systemctl enable sbm-scope >/dev/null 2>&1 || true
  systemctl restart sbm-scope
  sleep 1
  systemctl --no-pager --lines=0 status sbm-scope | head -3
'"

echo "==> local check"
ssh "$PROX" "pct exec $CT -- bash -c 'curl -s -o /dev/null -w \"health: %{http_code}\n\" http://127.0.0.1:8099/api/health'"

echo "==> done. Remember: tokens.json lives at $DEST/data/tokens.json (hand-made, never deployed)."
