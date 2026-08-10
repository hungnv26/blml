#!/usr/bin/env python3
"""Upload App Store screenshots.

Apple does not take a plain file POST. Each image is reserved first, which
returns one or more upload operations (URL, method, headers, byte range); the
bytes are PUT to those; then the asset is committed with an MD5 of the source
file so Apple can verify it arrived intact.
"""
import hashlib, os, sys, urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc

LOC = "89924247-7607-4300-af42-274349e4e286"
# 1320x2868 is the 6.9" iPhone, but App Store Connect has no APP_IPHONE_69 —
# the largest iPhone class is still filed under APP_IPHONE_67, which accepts
# both 1290x2796 and 1320x2868. The app is iPhone-only, so this is the only
# display type the listing needs.
DISPLAY_TYPE = "APP_IPHONE_67"
SHOTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "brand", "appstore")


def ensure_set():
    for s in asc.call("GET", f"/v1/appStoreVersionLocalizations/{LOC}/appScreenshotSets")["data"]:
        if s["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return s["id"]
    r = asc.call("POST", "/v1/appScreenshotSets", {
        "data": {"type": "appScreenshotSets",
                 "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                 "relationships": {"appStoreVersionLocalization": {
                     "data": {"type": "appStoreVersionLocalizations", "id": LOC}}}}})
    return r["data"]["id"]


def upload(set_id, path):
    name = os.path.basename(path)
    blob = open(path, "rb").read()

    res = asc.call("POST", "/v1/appScreenshots", {
        "data": {"type": "appScreenshots",
                 "attributes": {"fileSize": len(blob), "fileName": name},
                 "relationships": {"appScreenshotSet": {
                     "data": {"type": "appScreenshotSets", "id": set_id}}}}})
    sid = res["data"]["id"]

    for op in res["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]:op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], method=op["method"], data=chunk)
        for h in op.get("requestHeaders", []):
            req.add_header(h["name"], h["value"])
        urllib.request.urlopen(req, timeout=120).read()

    asc.call("PATCH", f"/v1/appScreenshots/{sid}", {
        "data": {"type": "appScreenshots", "id": sid,
                 "attributes": {"uploaded": True,
                                "sourceFileChecksum": hashlib.md5(blob).hexdigest()}}})
    return sid


if __name__ == "__main__":
    set_id = ensure_set()
    print(f"  screenshot set: {set_id} ({DISPLAY_TYPE})")
    for f in sorted(os.listdir(SHOTS)):
        if f.endswith(".png"):
            sid = upload(set_id, os.path.join(SHOTS, f))
            print(f"  uploaded {f} -> {sid}")
