#!/usr/bin/env python3
"""Invite someone to the BLML TestFlight beta by email.

    ./invite-tester.py someone@example.com
    ./invite-tester.py someone@example.com --group "Family & Friends"
    ./invite-tester.py --list

Apple emails the invitation itself. What it does NOT mention is that BLML
registration is invite-only, so the person also needs the code from
REGISTRATION_CODE — see the guide this script prints at the end.

The group matters more than it looks: a tester only sees builds that their
group carries. Adding someone to a group still holding an old build gives
them that old build, with no hint that a newer one exists. This checks and
says so rather than leaving you to find out from the tester.
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "asc"))
import asc  # noqa: E402

APP_ID = "6799954229"
DEFAULT_GROUP = "Family & Friends"
GUIDE = "https://claude.ai/code/artifact/b220ff1c-4fef-4959-97ef-9d799a0172cb"


def groups() -> list:
    return asc.call("GET", f"/v1/apps/{APP_ID}/betaGroups?limit=20")["data"]


def group_builds(gid: str) -> list:
    rows = asc.call("GET", f"/v1/betaGroups/{gid}/builds?limit=200").get("data", [])
    return sorted((int(b["attributes"]["version"]) for b in rows), reverse=True)


def group_testers(gid: str) -> list:
    return asc.call("GET", f"/v1/betaGroups/{gid}/betaTesters?limit=200").get("data", [])


def newest_build() -> int:
    rows = asc.call("GET", f"/v1/builds?filter[app]={APP_ID}&limit=5&sort=-version")["data"]
    return max(int(b["attributes"]["version"]) for b in rows)


def show_groups() -> None:
    latest = newest_build()
    print(f"newest build uploaded: {latest}\n")
    for g in groups():
        gid, at = g["id"], g["attributes"]
        kind = "internal" if at.get("isInternalGroup") else "external"
        builds = group_builds(gid)
        stale = "" if builds and builds[0] == latest else "   <-- not on the newest build"
        print(f"  {at['name']:<22} {kind:<9} builds={builds[:3]} "
              f"testers={len(group_testers(gid))}{stale}")


def invite(email: str, group_name: str) -> int:
    match = [g for g in groups() if g["attributes"]["name"] == group_name]
    if not match:
        print(f"No group named {group_name!r}. Known groups:", file=sys.stderr)
        for g in groups():
            print("   ", g["attributes"]["name"], file=sys.stderr)
        return 1
    gid = match[0]["id"]

    existing = {(t["attributes"].get("email") or "").lower()
                for t in group_testers(gid)}
    if email.lower() in existing:
        print(f"{email} is already in {group_name!r}. Nothing to do.")
        return 0

    asc.call("POST", "/v1/betaTesters", {"data": {
        "type": "betaTesters",
        "attributes": {"email": email},
        "relationships": {"betaGroups": {"data": [{"type": "betaGroups", "id": gid}]}}}})

    # Read back from the group rather than trusting the POST: a call that
    # returns cleanly is not evidence the person can see a build.
    after = {(t["attributes"].get("email") or "").lower(): t["attributes"].get("state")
             for t in group_testers(gid)}
    if email.lower() not in after:
        print(f"FAILED: {email} is not in {group_name!r} after the call",
              file=sys.stderr)
        return 1
    print(f"invited {email} -> {group_name!r} (state: {after[email.lower()]})")

    builds, latest = group_builds(gid), newest_build()
    if not builds:
        print(f"\nWARNING: {group_name!r} carries no build at all — they will "
              f"have nothing to install.")
    elif builds[0] != latest:
        print(f"\nWARNING: {group_name!r} is on build {builds[0]}, but {latest} "
              f"is the newest uploaded.\n  They will get {builds[0]}. Add the "
              f"newer build to this group in App Store Connect if that is wrong.")

    print(f"""
Apple has emailed them the TestFlight invitation. It does not mention that
BLML registration needs an invite code, so send that separately along with:

  {GUIDE}

(The guide is private until you share it from the page's share menu.)""")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("email", nargs="?", help="the person's email address")
    ap.add_argument("--group", default=DEFAULT_GROUP)
    ap.add_argument("--list", action="store_true",
                    help="show groups, their builds and tester counts")
    args = ap.parse_args()

    if args.list:
        show_groups()
        return 0
    if not args.email:
        ap.error("give an email address, or --list")
    if "@" not in args.email:
        ap.error(f"{args.email!r} does not look like an email address")
    return invite(args.email, args.group)


if __name__ == "__main__":
    sys.exit(main())
