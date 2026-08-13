#!/usr/bin/env python3
"""Render a submitted scope JSON to markdown, front matter and all.

    render_scope.py submissions/scopes/submitted/<file>.json > draft.md

The output is a promote.sh-style draft: YAML front matter (title, labels,
from) then the body. House rule: the owner's words appear VERBATIM under
fixed headings - this script formats, it never summarises. Locations render
as a table of the verified tag coordinates.
"""
import json
import sys
from datetime import datetime, timezone

HEADINGS = (
    ("pitch", "The pitch"),
    ("loop", "The core loop"),
    ("winlose", "Win / lose"),
    ("nightOne", "Night one minimum"),
    ("wishlist", "The wishlist"),
)

FRAMEWORK_ROWS = (
    ("teams", "Teams"),
    ("population", "Population"),
    ("police", "Police"),
    ("respawn", "Respawn policy"),
    ("clock", "Clock / weather override"),
    ("roundTimer", "Round timer"),
)

BLANK = "_(left blank)_"


def text(value) -> str:
    return str(value).strip() if value is not None else ""


def cell(value) -> str:
    """A table cell must not break the table."""
    return text(value).replace("|", "\\|").replace("\n", " ") or "-"


def stamp(epoch) -> str:
    try:
        when = datetime.fromtimestamp(int(epoch), timezone.utc)
    except (TypeError, ValueError, OSError):
        return "unknown"
    return when.strftime("%Y-%m-%d %H:%M UTC")


def render(doc: dict) -> str:
    form = doc.get("form") or {}
    owner = text(doc.get("owner")) or "unknown"
    slug = text(doc.get("slug")) or "unknown"
    name = text(form.get("name")) or text(doc.get("name")) or slug

    out = [
        "---",
        f'title: "Gametype scope: {name} ({owner})"',
        f"labels: [new-mode, mode:{slug}, needs-human]",
        f"from: {owner}",
        "---",
        "",
        f"**Basis:** {text(form.get('basis')) or 'new mode'} · "
        f"**Slug:** `{slug}` · "
        f"**Submitted:** {stamp(doc.get('submitted') or doc.get('updated'))}",
    ]

    for key, heading in HEADINGS:
        out += ["", f"## {heading}", "", text(form.get(key)) or BLANK]

    out += ["", "## Framework features", ""]
    framework = form.get("framework") or {}
    for key, label in FRAMEWORK_ROWS:
        out.append(f"- **{label}:** {text(framework.get(key)) or '-'}")
    other = text(framework.get("other"))
    if other:
        out += ["", "**Other framework asks:**", "", other]

    out += ["", "## config.lua knobs", ""]
    knobs = text(form.get("knobs"))
    out += ["```", knobs, "```"] if knobs else [BLANK]

    out += ["", "## Locations (verified tags)", ""]
    locations = form.get("locations")
    locations = locations if isinstance(locations, list) else []
    if locations:
        out += [
            "| label/note | role | x | y | z | heading | tagged by |",
            "|---|---|---|---|---|---|---|",
        ]
        for loc in locations:
            if not isinstance(loc, dict):
                continue
            out.append(
                f"| {cell(loc.get('note'))} | {cell(loc.get('role'))} "
                f"| {cell(loc.get('x'))} | {cell(loc.get('y'))} "
                f"| {cell(loc.get('z'))} | {cell(loc.get('heading'))} "
                f"| {cell(loc.get('taggedBy'))} |"
            )
    else:
        out.append("_(no verified tags attached)_")

    out += ["", "## Locations still needed", "",
            text(form.get("locationsNeeded")) or BLANK]
    out += ["", "## Acceptance criteria", "",
            text(form.get("acceptance")) or BLANK, ""]

    return "\n".join(out)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: render_scope.py <submitted-scope.json>", file=sys.stderr)
        return 2
    try:
        with open(sys.argv[1], encoding="utf-8") as handle:
            doc = json.load(handle)
    except (OSError, ValueError) as err:
        print(f"could not read {sys.argv[1]}: {err}", file=sys.stderr)
        return 1
    if not isinstance(doc, dict):
        print("that file is not a scope document", file=sys.stderr)
        return 1
    print(render(doc))
    return 0


if __name__ == "__main__":
    sys.exit(main())
