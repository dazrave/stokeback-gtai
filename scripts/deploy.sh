#!/usr/bin/env bash
#
# Push the local resources to the live FiveM server and hot-reload them.
#
#   scripts/deploy.sh                  # copy files, syntax-check, reload nothing
#   scripts/deploy.sh infected pint    # ...and restart those resources
#
# The server runs in a tmux session inside an LXC container on the Proxmox box,
# so everything goes over an ssh hop. Override the host/container with env vars
# if yours lives somewhere else.
set -euo pipefail

PROX="${PROX:-root@192.168.0.23}"
CT="${CT:-212}"
DEST="${DEST:-/opt/fivem/server-data}"
TMUX_SESSION="${TMUX_SESSION:-fivem}"

cd "$(dirname "$0")/.."

echo "==> copying resources to CT${CT}"
tar czf - 'resources/[local]' server.cfg \
  | ssh "$PROX" "pct exec $CT -- tar xzf - -C $DEST"

ssh "$PROX" "pct exec $CT -- chown -R fivem:fivem $DEST/resources"

# A syntax error only shows up as a dead resource at runtime, so check first.
echo "==> syntax check"
ssh "$PROX" "pct exec $CT -- bash -c '
  cd $DEST/resources
  fail=0
  find . -path \"*local*\" -name \"*.lua\" | while read -r f; do
    luac -p \"\$f\" || { echo \"SYNTAX FAIL: \$f\"; fail=1; }
  done
  exit \$fail
'"

# `restart` reuses the manifest the server cached at scan time, so a changed
# fxmanifest.lua (new script files) is silently ignored without this.
if [ "$#" -gt 0 ]; then
  echo "==> refreshing resource manifests"
  ssh "$PROX" "pct exec $CT -- runuser -u fivem -- \
    tmux send-keys -t $TMUX_SESSION 'refresh' Enter"
  sleep 2
fi

for resource in "$@"; do
  echo "==> restarting $resource"
  ssh "$PROX" "pct exec $CT -- runuser -u fivem -- \
    tmux send-keys -t $TMUX_SESSION 'restart $resource' Enter"
  sleep 1
done

echo "==> done"
