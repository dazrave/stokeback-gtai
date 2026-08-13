#!/usr/bin/env python3
"""Merge self-serve profile fields into the crew roster.

    sync_roster.py <profiles.json> <roster.json>

For each profile, find the crew entry whose "owner" matches and overwrite
only the fields the profile actually set (fivem / discord / colour).
Everything else on the entry - angle, owns, order, the _comment - is left
exactly as it was. Profiles with no matching crew entry are skipped and
reported, not invented. Prints a before/after diff and writes roster.json
in place; the caller (sync-roster.sh) is the one that tells a human to
review and commit it. This script never touches git.
"""
import difflib
import json
import sys

FIELDS = ("fivem", "discord", "colour")


def load(path: str):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def merge(roster: dict, profiles: dict):
    """Return (updated roster, list of human-readable notes)."""
    crew = roster.get("crew")
    crew = crew if isinstance(crew, list) else []
    by_owner = {c.get("owner"): i for i, c in enumerate(crew) if isinstance(c, dict)}

    notes = []
    updated_crew = list(crew)
    for owner, profile in sorted(profiles.items()):
        if not isinstance(profile, dict):
            continue
        idx = by_owner.get(owner)
        if idx is None:
            notes.append(f"no matching crew entry for owner '{owner}' - skipped")
            continue
        changes = {field: profile[field] for field in FIELDS if profile.get(field)}
        if not changes:
            notes.append(f"{owner}: profile has nothing set yet - skipped")
            continue
        updated_crew[idx] = {**updated_crew[idx], **changes}
        summary = ", ".join(f"{k}={v!r}" for k, v in changes.items())
        notes.append(f"{owner}: {summary}")

    return {**roster, "crew": updated_crew}, notes


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: sync_roster.py <profiles.json> <roster.json>", file=sys.stderr)
        return 2

    profiles_path, roster_path = sys.argv[1], sys.argv[2]
    try:
        profiles = load(profiles_path)
        roster = load(roster_path)
    except (OSError, ValueError) as err:
        print(f"could not read input: {err}", file=sys.stderr)
        return 1

    if not isinstance(profiles, dict):
        print("profiles.json is not an object", file=sys.stderr)
        return 1
    if not isinstance(roster, dict):
        print("roster.json is not an object", file=sys.stderr)
        return 1

    updated, notes = merge(roster, profiles)

    for note in notes:
        print(f"[sync-roster] {note}")

    if updated == roster:
        print("[sync-roster] no changes needed")
        return 0

    before = json.dumps(roster, indent=2, ensure_ascii=False, sort_keys=True).splitlines(keepends=True)
    after = json.dumps(updated, indent=2, ensure_ascii=False, sort_keys=True).splitlines(keepends=True)
    print("[sync-roster] --- before/after diff ---")
    sys.stdout.writelines(difflib.unified_diff(
        [line if line.endswith("\n") else line + "\n" for line in before],
        [line if line.endswith("\n") else line + "\n" for line in after],
        fromfile="roster.json (before)", tofile="roster.json (after)",
    ))

    with open(roster_path, "w", encoding="utf-8") as handle:
        handle.write(json.dumps(updated, indent=2, ensure_ascii=False) + "\n")

    print(f"[sync-roster] wrote {roster_path}")
    print("[sync-roster] REMINDER: review the diff above and commit it yourself - "
          "this script never touches git.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
