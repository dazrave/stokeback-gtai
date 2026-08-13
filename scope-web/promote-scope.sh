#!/usr/bin/env bash
#
# Turn a submitted scope into a GitHub issue + a living design doc. This is
# the triage gate: a human runs it on the scopes they've decided to build.
#
#   scope-web/promote-scope.sh submissions/scopes/submitted/<file>.json
#
# Renders the JSON via render_scope.py, writes docs/modes/<slug>.md in this
# repo, creates the mode:<slug> label and the issue, then archives the JSON
# to scopes/promoted/ next to where it came from.
set -euo pipefail

REPO="${REPO:-dazrave/stokeback-gtai}"
SCOPE="${1:?usage: promote-scope.sh <submitted-scope.json>}"

[[ -f "$SCOPE" ]] || { echo "no such scope: $SCOPE" >&2; exit 1; }

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/.." && pwd)"

# --- render to a temp draft ---
draft="$(mktemp)"
trap 'rm -f "$draft"' EXIT
python3 "$HERE/render_scope.py" "$SCOPE" > "$draft"

# --- pull the front matter out (same trick as web/promote.sh) ---
front="$(awk '/^---$/{n++; next} n==1{print} n==2{exit}' "$draft")"
body="$(awk '/^---$/{n++; next} n>=2{print}' "$draft")"

title="$(printf '%s\n' "$front" | sed -n 's/^title:[[:space:]]*//p' | sed 's/^"//; s/"$//')"
labels="$(printf '%s\n' "$front" | sed -n 's/^labels:[[:space:]]*\[\(.*\)\]/\1/p' | tr -d ' ')"
slug="$(printf '%s\n' "$labels" | tr ',' '\n' | sed -n 's/^mode://p' | head -1)"

[[ -n "$title" ]] || { echo "rendered draft has no title" >&2; exit 1; }
[[ -n "$slug" ]] || { echo "rendered draft has no mode:<slug> label" >&2; exit 1; }

# --- the living design doc: same content minus front matter ---
doc_dir="$REPO_ROOT/docs/modes"
mkdir -p "$doc_dir"
{ printf '# %s\n' "$title"; printf '%s\n' "$body"; } > "$doc_dir/$slug.md"
echo "==> wrote docs/modes/$slug.md"

# --- label (idempotent) + issue ---
gh label create "mode:$slug" --repo "$REPO" --color BFD4F2 \
  --description "Area: $slug" 2>/dev/null || true

label_args=()
IFS=',' read -ra parts <<< "$labels"
for l in "${parts[@]}"; do [[ -n "$l" ]] && label_args+=(--label "$l"); done

echo "==> creating issue: $title"
url="$(gh issue create --repo "$REPO" --title "$title" --body "$body" "${label_args[@]}")"
echo "    $url"

# --- archive the JSON so it isn't promoted twice ---
done_dir="$(dirname "$SCOPE")/../promoted"
mkdir -p "$done_dir"
mv "$SCOPE" "$done_dir/"
echo "==> archived scope to promoted/"
echo "==> REMINDER: docs/modes/$slug.md is not committed - review it and commit when happy."
