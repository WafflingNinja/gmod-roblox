"""Upload map texture PNGs as Decals through the Open Cloud Assets API and record their ids.

  set ROBLOX_API_KEY=...   (assets read + write, legacy-assets manage)
  set ROBLOX_USER_ID=...
  python tools/upload_textures.py <png dir> <texture_ids.json> [--limit N]

texture_ids.json maps "<png name>" -> "rbxassetid://<image id>" and is what tools/MapImport.luau reads. Names already
in it are skipped, so a failed run can simply be re-run.
"""
import argparse, gzip, json, os, re, time, urllib.error, urllib.request, uuid

API = "https://apis.roblox.com/assets/v1/"


def call(req, key):
    req.add_header("x-api-key", key)
    for attempt in range(6):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as err:
            if err.code == 429 or err.code >= 500:
                time.sleep(2 ** attempt)
                continue
            raise RuntimeError("%d %s" % (err.code, err.read().decode("utf-8", "replace")))
    raise RuntimeError("gave up after retries")


def image_of(decal_id, key):
    """Open Cloud creates a Decal; TextureID needs the Image it wraps. Needs legacy-assets:manage on the key."""
    loc = call(urllib.request.Request(API.replace("assets/v1/", "asset-delivery-api/v1/assetId/") + decal_id), key)
    with urllib.request.urlopen(loc["location"], timeout=60) as resp:
        raw = resp.read()
    if raw[:2] == b"\x1f\x8b":
        raw = gzip.decompress(raw)
    m = re.search(rb"asset/\?id=(\d+)", raw)
    if not m:
        raise RuntimeError("no image inside decal %s" % decal_id)
    return m.group(1).decode()


def upload(path, key, user_id):
    name = os.path.basename(path)
    request = {
        "assetType": "Decal",
        "displayName": os.path.splitext(name)[0][:50],
        "description": "map texture",
        "creationContext": {"creator": {"userId": user_id}},
    }
    boundary = uuid.uuid4().hex
    body = b"".join([
        b"--%s\r\nContent-Disposition: form-data; name=\"request\"\r\n\r\n" % boundary.encode(),
        json.dumps(request).encode(), b"\r\n",
        b"--%s\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"%s\"\r\n" % (
            boundary.encode(), name.encode()),
        b"Content-Type: image/png\r\n\r\n", open(path, "rb").read(), b"\r\n",
        b"--%s--\r\n" % boundary.encode(),
    ])
    req = urllib.request.Request(API + "assets", data=body, method="POST")
    req.add_header("Content-Type", "multipart/form-data; boundary=" + boundary)
    op = call(req, key)
    for _ in range(30):
        if op.get("done"):
            asset = op.get("response", {}).get("assetId")
            if not asset:
                raise RuntimeError("no assetId: %s" % op)
            return "rbxassetid://" + image_of(str(asset), key)
        time.sleep(1)
        op = call(urllib.request.Request(API + op["path"]), key)
    raise RuntimeError("operation never finished: %s" % op.get("path"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("png_dir")
    ap.add_argument("ids_json")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--skip-json", help="JSON list/dict of PNG names the texture review rejected")
    args = ap.parse_args()
    key, user_id = os.environ["ROBLOX_API_KEY"], int(os.environ["ROBLOX_USER_ID"])

    ids = json.load(open(args.ids_json)) if os.path.exists(args.ids_json) else {}
    skip = set()
    if args.skip_json and os.path.exists(args.skip_json):
        raw = json.load(open(args.skip_json))
        skip = set(raw.keys() if isinstance(raw, dict) else raw)
    todo = sorted(
        n for n in os.listdir(args.png_dir)
        if n.endswith(".png") and n not in ids and n not in skip
    )
    if args.limit:
        todo = todo[:args.limit]
    failed = 0
    for i, name in enumerate(todo, 1):
        try:
            ids[name] = upload(os.path.join(args.png_dir, name), key, user_id)
            print("%d/%d %s %s" % (i, len(todo), name, ids[name]))
        except RuntimeError as err:
            failed += 1
            print("%d/%d %s FAILED %s" % (i, len(todo), name, err))
        with open(args.ids_json, "w") as fh:
            json.dump(ids, fh, indent=0)
    print("done: %d uploaded, %d failed, %d total ids" % (len(todo) - failed, failed, len(ids)))


if __name__ == "__main__":
    main()
