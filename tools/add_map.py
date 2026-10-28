"""Add a Gmod Workshop map to waffles mod.

  python tools/add_map.py <workshop link or id> [options]

Steps (the same order as ROADMAP step 7.7):
  subscribe in Steam -> find .gma -> gmad extract -> bsp_to_json -> alpha audit ->
  texture review page (50/page, click to reject) -> upload approved textures ->
  MapCatalog + MapLighting + docs/ASSETS.md -> Add Place prompt -> Studio import command on the clipboard.

The map geometry itself still has to be imported into Studio by the command the script copies; the script
starts the local HTTP server and copies MapImport.luau next to the JSON so that command works immediately.
"""
import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import urllib.request
import webbrowser
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
sys.path.insert(0, str(TOOLS))

import bsp_to_json  # noqa: E402
import alpha_audit  # noqa: E402
import texture_review  # noqa: E402

MAPS_OUT = Path(os.environ.get("TEMP") or tempfile.gettempdir()) / "kilo" / "maps_out"
PNG_DIR = MAPS_OUT / "png"
IDS_JSON = MAPS_OUT / "texture_ids.json"
ALPHA_JSON = MAPS_OUT / "alpha_fix.json"
GARRY = Path(os.environ.get("GMOD_DIR", r"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"))
ADDONS = Path(os.environ.get("GMOD_ADDONS", str(GARRY / "garrysmod" / "addons")))
WORKSHOP = Path(os.environ.get("GMOD_WORKSHOP", r"C:\Program Files (x86)\Steam\steamapps\workshop\content\4000"))
GMAD = GARRY / "bin" / "gmad.exe"
DASHBOARD = "https://create.roblox.com/dashboard/creations"
WORKSHOP_URL = "https://steamcommunity.com/sharedfiles/filedetails/?id=%s"

MOODS = {
    "day": {
        "Brightness": 2.8, "Ambient": [0.36, 0.38, 0.42], "OutdoorAmbient": [0.46, 0.48, 0.52],
        "ClockTime": 13.5, "FogEnd": 6500, "Exposure": 0.18, "Diffuse": 0.95, "Specular": 0.9,
        "ShadowSoftness": 0.25, "Atmosphere": [0.74, 0.84, 0.96], "Decay": [0.9, 0.86, 0.78],
        "Density": 0.28, "Haze": 1.0, "Glare": 0.12, "Bloom": 0.45, "Threshold": 1.0,
        "Contrast": 0.08, "Saturation": 0.08, "Tint": [1, 0.99, 0.96], "SunRays": 0.2,
    },
    "sunny": {
        "Brightness": 3.0, "Ambient": [0.3, 0.32, 0.36], "OutdoorAmbient": [0.42, 0.44, 0.48],
        "ClockTime": 14.5, "FogEnd": 8000, "Exposure": 0.22, "Diffuse": 1.0, "Specular": 1.0,
        "ShadowSoftness": 0.18, "Atmosphere": [0.78, 0.86, 0.95], "Decay": [0.92, 0.85, 0.7],
        "Density": 0.22, "Haze": 0.8, "Glare": 0.3, "Bloom": 0.4, "Threshold": 1.1,
        "Contrast": 0.08, "Saturation": 0.16, "Tint": [1, 0.98, 0.94], "SunRays": 0.35,
    },
    "bright": {
        "Brightness": 3.4, "Ambient": [0.32, 0.32, 0.34], "OutdoorAmbient": [0.4, 0.4, 0.42],
        "ClockTime": 13, "FogEnd": 4500, "Exposure": 0.3, "Diffuse": 1.0, "Specular": 1.0,
        "ShadowSoftness": 0.15, "Atmosphere": [0.8, 0.88, 0.97], "Decay": [0.95, 0.9, 0.78],
        "Density": 0.2, "Haze": 0.8, "Glare": 0.55, "Bloom": 0.5, "Threshold": 1.0,
        "Contrast": 0.1, "Saturation": 0.18, "Tint": [1, 0.99, 0.95], "SunRays": 0.5,
    },
    "overcast": {
        "Brightness": 1.2, "Ambient": [0.34, 0.34, 0.37], "OutdoorAmbient": [0.4, 0.41, 0.45],
        "ClockTime": 12, "FogEnd": 2600, "Exposure": 0.4, "Diffuse": 0.8, "Specular": 0.7,
        "ShadowSoftness": 0.45, "Atmosphere": [0.62, 0.67, 0.75], "Decay": [0.5, 0.55, 0.64],
        "Density": 0.46, "Haze": 2.6, "Glare": 0, "Bloom": 0.7, "Threshold": 0.85,
        "Contrast": 0.1, "Saturation": -0.15, "Tint": [0.93, 0.96, 1], "SunRays": 0,
    },
    "backrooms": {
        "Brightness": 1.4, "Ambient": [0.4, 0.36, 0.24], "OutdoorAmbient": [0.42, 0.38, 0.26],
        "ClockTime": 12, "FogEnd": 420, "FogStart": 30, "FogColor": [0.35, 0.32, 0.2],
        "Exposure": 0.4, "Diffuse": 0.8, "Specular": 0.4, "ShadowSoftness": 0.5,
        "Atmosphere": [0.86, 0.76, 0.4], "Decay": [0.7, 0.6, 0.25], "Density": 0.5,
        "Haze": 3, "Glare": 0, "Bloom": 0.65, "Threshold": 0.9,
        "Contrast": 0.06, "Saturation": -0.05, "Tint": [1, 0.95, 0.72], "SunRays": 0,
    },
    "evening": {
        "Brightness": 2.0, "Ambient": [0.3, 0.29, 0.26], "OutdoorAmbient": [0.34, 0.33, 0.3],
        "ClockTime": 17.7, "FogEnd": 900, "FogStart": 60, "FogColor": [0.2, 0.2, 0.18],
        "Exposure": 0.2, "Diffuse": 1.0, "Specular": 1.0, "ShadowSoftness": 0.2,
        "Atmosphere": [0.93, 0.7, 0.5], "Decay": [0.9, 0.45, 0.25], "Density": 0.36,
        "Haze": 1.6, "Glare": 0.85, "Bloom": 0.7, "Threshold": 1.0,
        "Contrast": 0.12, "Saturation": 0.1, "Tint": [1, 0.9, 0.8], "SunRays": 0.25,
    },
}


def fail(message):
    print("error: " + message, file=sys.stderr)
    raise SystemExit(1)


def workshop_id(value):
    match = re.search(r"[?&]id=(\d+)", value)
    if match:
        return match.group(1)
    if value.strip().isdigit():
        return value.strip()
    fail("expected a Steam Workshop link or a numeric id, got %r" % value)


def find_gma(wid, interactive=True):
    folder = WORKSHOP / wid
    for attempt in range(3):
        candidates = sorted(folder.rglob("*.gma")) if folder.exists() else []
        if candidates:
            return max(candidates, key=lambda p: p.stat().st_size)
        legacy = sorted(ADDONS.rglob("*.gma")) if ADDONS.exists() else []
        named = [p for p in legacy if wid in p.name]
        if named:
            return max(named, key=lambda p: p.stat().st_size)
        if not interactive:
            return None
        print("No .gma found for Workshop item %s." % wid)
        print("Subscribe to it in Steam first: %s" % (WORKSHOP_URL % wid))
        webbrowser.open(WORKSHOP_URL % wid)
        try:
            input("Press Enter after Steam has downloaded the item (or Ctrl+C to stop): ")
        except EOFError:
            return None
    return None


def extract(gma, out_dir):
    if not GMAD.exists():
        fail("gmad.exe not found at %s; set GMOD_DIR to the Garry's Mod install" % GMAD)
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    print("Extracting %s" % gma)
    subprocess.run([str(GMAD), "extract", "-file", str(gma), "-out", str(out_dir)], check=True)
    bsp = sorted((out_dir / "maps").glob("*.bsp"))
    if not bsp:
        bsp = sorted(out_dir.rglob("*.bsp"))
    if not bsp:
        fail("no .bsp inside the extracted addon")
    return bsp[0]


def default_id(bsp):
    stem = re.sub(r"^(gm|rp|bgn|ttt|ph|zm)_", "", bsp.stem.lower())
    words = [w for w in re.split(r"[^a-z0-9]+", stem) if w]
    return "".join(w[:1].upper() + w[1:] for w in words) or "Map"


def title_for(map_id):
    return re.sub(r"(?<!^)(?=[A-Z])", " ", map_id)


def used_pngs(data):
    names = set()
    for chunk in data.get("chunks", []):
        if chunk.get("tex"):
            names.add(chunk["tex"])
    for door in data.get("doors", []):
        for chunk in door.get("chunks", []):
            if chunk.get("tex"):
                names.add(chunk["tex"])
    return names


def load_json(path, default):
    try:
        return json.load(open(path))
    except (ValueError, OSError):
        return default


def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    json.dump(value, open(path, "w"), indent=0 if path.name == "alpha_fix.json" else 2)


def merge_alpha(new_fix):
    old = load_json(ALPHA_JSON, {})
    old.update(new_fix)
    save_json(ALPHA_JSON, old)


def upload(png_dir, ids_json, skip_json, limit=0):
    cmd = [sys.executable, str(TOOLS / "upload_textures.py"), str(png_dir), str(ids_json),
           "--skip-json", str(skip_json)]
    if limit:
        cmd += ["--limit", str(limit)]
    subprocess.run(cmd, check=False)


def find_close(text, open_index):
    depth, in_string, escaped = 0, False, False
    for i in range(open_index, len(text)):
        ch = text[i]
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
    raise ValueError("unbalanced braces")


def lua_string(value):
    return '"' + str(value).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ") + '"'


def catalog_entry(map_id, title, blurb, spawn, orbit, source):
    center = orbit["center"]
    return (
        "\t{\n"
        f"\t\tid = {lua_string(map_id)},\n"
        f"\t\tname = {lua_string(title)},\n"
        f"\t\tblurb = {lua_string(blurb)},\n"
        f"\t\tmodel = {lua_string(map_id)},\n"
        f"\t\tspawn = {{ {spawn[0]:.2f}, {spawn[1]:.2f}, {spawn[2]:.2f} }},\n"
        f"\t\torbit = {{ center = {{ {center[0]:.0f}, {center[1]:.0f}, {center[2]:.0f} }}, "
        f"radius = {orbit['radius']:.0f}, height = {orbit['height']:.0f} }},\n"
        f"\t\t-- source: {source}\n"
        "\t},\n"
    )


def insert_catalog(map_id, title, blurb, spawn, orbit, source):
    path = ROOT / "src" / "ReplicatedStorage" / "Shared" / "MapCatalog.luau"
    text = path.read_text(encoding="utf-8")
    if re.search(r'\bid\s*=\s*"%s"' % re.escape(map_id), text):
        fail("MapCatalog already has %s (edit it by hand if you meant to re-import)" % map_id)
    marker = "local list: { MapDef } = {"
    start = text.index(marker) + len(marker)
    end = find_close(text, text.index("{", start - 1))
    block = catalog_entry(map_id, title, blurb, spawn, orbit, source)
    path.write_text(text[:end] + block + text[end:], encoding="utf-8")
    return path


def set_place_id(map_id, place_id):
    path = ROOT / "src" / "ReplicatedStorage" / "Shared" / "MapCatalog.luau"
    text = path.read_text(encoding="utf-8")
    block_start = re.search(r'\n\t\{\n\t\tid = "%s",' % re.escape(map_id), text)
    if not block_start:
        print("Could not find the new MapCatalog entry to write the place id into.")
        return
    start = block_start.start()
    end = text.index("\n\t},", start)
    block = text[start:end]
    block = re.sub(r"\n\t\tplaceId = \d+,", "", block)
    block += "\n\t\tplaceId = %d," % place_id
    path.write_text(text[:start] + block + text[end:], encoding="utf-8")


def lighting_folder(map_id, mood):
    m = MOODS.get(mood) or MOODS["day"]
    folder = {
        "Brightness": ("NumberValue", m["Brightness"]),
        "Ambient": ("Color3Value", m["Ambient"]),
        "OutdoorAmbient": ("Color3Value", m["OutdoorAmbient"]),
        "ClockTime": ("NumberValue", m["ClockTime"]),
        "GlobalShadows": ("BoolValue", True),
        "FogEnd": ("NumberValue", m["FogEnd"]),
        "ExposureCompensation": ("NumberValue", m["Exposure"]),
        "EnvironmentDiffuseScale": ("NumberValue", m["Diffuse"]),
        "EnvironmentSpecularScale": ("NumberValue", m["Specular"]),
        "ShadowSoftness": ("NumberValue", m["ShadowSoftness"]),
        "Atmosphere": ("Atmosphere", {
            "Density": m["Density"], "Offset": 0.15, "Color": m["Atmosphere"], "Decay": m["Decay"],
            "Glare": m["Glare"], "Haze": m["Haze"]}),
        "Bloom": ("BloomEffect", {"Intensity": m["Bloom"], "Size": 26, "Threshold": m["Threshold"]}),
        "ColorCorrection": ("ColorCorrectionEffect", {
            "Brightness": 0.0, "Contrast": m["Contrast"], "Saturation": m["Saturation"], "TintColor": m["Tint"]}),
        "WaterColor": ("Color3Value", [0.05, 0.32, 0.42]),
        "WaterTransparency": ("NumberValue", 0.25),
        "WaterReflectance": ("NumberValue", 0.35),
        "WaterWaveSize": ("NumberValue", 0.15),
        "WaterWaveSpeed": ("NumberValue", 12),
    }
    if m["SunRays"] > 0:
        folder["SunRays"] = ("SunRaysEffect", {"Intensity": m["SunRays"], "Spread": 0.9})
    if "FogStart" in m:
        folder["FogStart"] = ("NumberValue", m["FogStart"])
        folder["FogColor"] = ("Color3Value", m["FogColor"])
    body = {}
    for name, (class_name, value) in folder.items():
        if class_name.endswith("Value"):
            body[name] = {"$className": class_name, "$properties": {"Value": value}}
        else:
            body[name] = {"$className": class_name, "$properties": value}
    body = {"$className": "Folder", "$ignoreUnknownInstances": True, **body}
    return body


def insert_lighting(map_id, mood):
    path = ROOT / "default.project.json"
    text = path.read_text(encoding="utf-8")
    if re.search(r'"%s"\s*:\s*\{' % re.escape(map_id), text):
        print("MapLighting already has an entry for %s; leaving it alone." % map_id)
        return
    marker = '"MapLighting": {'
    open_at = text.index("{", text.index(marker))
    close_at = find_close(text, open_at)
    body = json.dumps(lighting_folder(map_id, mood), indent=2)
    body = "\n".join("        " + line for line in body.splitlines())
    block = ',\n        "%s": %s' % (map_id, body)
    path.write_text(text[:close_at] + block + "\n      " + text[close_at:], encoding="utf-8")


def append_asset_row(map_id, wid, title):
    path = ROOT / "docs" / "ASSETS.md"
    text = path.read_text(encoding="utf-8").rstrip() + "\n"
    row = (
        f"| {title} (Workshop {wid}) | Workshop uploader | Gmod Workshop map, no license stated | "
        f"{(WORKSHOP_URL % wid)} | `Workspace.Maps.{map_id}`: brush geometry, doors, lights, textures via "
        f"`tools/add_map.py`, {time.strftime('%Y-%m-%d')} on the user's call; risk accepted |\n"
    )
    path.write_text(text + row, encoding="utf-8")


def ensure_server():
    MAPS_OUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(TOOLS / "MapImport.luau", MAPS_OUT / "MapImport.lua")
    try:
        with socket.create_connection(("127.0.0.1", 8765), timeout=0.5):
            return
    except OSError:
        pass
    print("Starting local map server on http://127.0.0.1:8765")
    flags = 0
    if os.name == "nt":
        flags = 0x00000008 | 0x00000200  # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP
    subprocess.Popen(
        [sys.executable, "-m", "http.server", "8765", "--bind", "127.0.0.1"],
        cwd=str(MAPS_OUT), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        creationflags=flags, start_new_session=(os.name != "nt"),
    )
    time.sleep(0.8)


def copy_clipboard(value):
    try:
        if os.name == "nt":
            subprocess.run(["clip"], input=value, text=True, check=True, shell=False)
        elif sys.platform == "darwin":
            subprocess.run(["pbcopy"], input=value, text=True, check=True)
        else:
            subprocess.run(["wl-copy"], input=value, text=True, check=True)
        print("Studio import command copied to the clipboard.")
        return
    except (OSError, subprocess.CalledProcessError):
        pass
    print("Clipboard tool unavailable. Paste this into the Studio command bar:\n" + value + "\n")


def studio_command(map_id, json_name):
    return (
        'local H=game:GetService("HttpService") local S=game:GetService("ServerStorage") '
        'local o=S:FindFirstChild("MapImport") if o then o:Destroy() end '
        'local m=Instance.new("ModuleScript") m.Name="MapImport" '
        'm.Source=H:GetAsync("http://127.0.0.1:8765/MapImport.lua") m.Parent=S '
        f'print(require(S.MapImport).run("{map_id}", "{json_name}")) '
        f'print(require(S.MapImport).polish(workspace.Maps.{map_id}))'
    )


def ask_place_id(map_id, given):
    if given:
        return given
    print("\nCreate the map's own place so Split Worlds can teleport into it:")
    print("  1. Creator Dashboard > Creations > Add Place (same universe).")
    print("  2. Open that place once so it exists, then copy its Place ID from the URL.")
    print("  " + DASHBOARD)
    try:
        webbrowser.open(DASHBOARD)
    except Exception:
        pass
    try:
        value = input("Place ID for %s (blank to skip): " % map_id).strip()
    except EOFError:
        return None
    if not value:
        return None
    if not value.isdigit():
        print("Not a numeric place id; leaving it unset. Add it to MapCatalog when you have it.")
        return None
    return int(value)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("workshop", help="Steam Workshop link or numeric id")
    ap.add_argument("--id", help="Map id / Workspace.Maps model name (default: from the .bsp name)")
    ap.add_argument("--title", help="Display name in the menu")
    ap.add_argument("--mood", choices=sorted(MOODS), default="day", help="lighting mood (default: day)")
    ap.add_argument("--centre-x", type=float, default=0.0)
    ap.add_argument("--centre-z", type=float, default=0.0)
    ap.add_argument("--place-id", type=int, help="skip the Add Place prompt")
    ap.add_argument("--no-review", action="store_true", help="accept every new texture (not recommended)")
    ap.add_argument("--no-browser", action="store_true", help="do not open the review page automatically")
    ap.add_argument("--skip-upload", action="store_true", help="convert and review but do not upload textures")
    args = ap.parse_args()

    wid = workshop_id(args.workshop)
    gma = find_gma(wid)
    if not gma:
        fail("Workshop item not downloaded; subscribe in Steam and run again")

    MAPS_OUT.mkdir(parents=True, exist_ok=True)
    PNG_DIR.mkdir(parents=True, exist_ok=True)
    out_dir = MAPS_OUT / wid
    bsp = extract(gma, out_dir)
    map_id = args.id or default_id(bsp)
    if not re.match(r"^[A-Za-z][A-Za-z0-9_]*$", map_id):
        fail("map id must be letters/numbers/underscore and start with a letter: %r" % map_id)
    title = args.title or title_for(map_id)
    json_path = MAPS_OUT / (bsp.stem.lower() + ".json")

    print("Converting %s -> %s" % (bsp, json_path))
    data = bsp_to_json.build(str(bsp), str(json_path), args.centre_x, str(PNG_DIR), args.centre_z)
    print("  tris=%d chunks=%d doors=%d lights=%d" % (
        data["stats"]["tris"], len(data["chunks"]), len(data["doors"]), len(data.get("lights", []))))

    ids = load_json(IDS_JSON, {})
    used = used_pngs(data)
    new = sorted(n for n in used if n not in ids and (PNG_DIR / n).exists())
    print("  textures: %d used, %d already uploaded, %d new" % (len(used), len(used) - len(new), len(new)))

    try:
        fix = alpha_audit.audit_bsp(str(bsp), str(PNG_DIR), {n: ids[n] for n in used if n in ids})
    except RuntimeError as err:
        fail(str(err))
    merge_alpha(fix)

    reject_path = MAPS_OUT / ("reject-%s.json" % map_id)
    rejected = set()
    if new and not args.no_review:
        rejected = texture_review.review(
            PNG_DIR, new, reject_path,
            open_browser=not args.no_browser,
        )
        print("  review: %d rejected, %d approved" % (len(rejected), len(new) - len(rejected)))
    elif new:
        print("  review skipped (--no-review)")

    if new and not args.skip_upload:
        if not os.environ.get("ROBLOX_API_KEY") or not os.environ.get("ROBLOX_USER_ID"):
            print("\nNo ROBLOX_API_KEY / ROBLOX_USER_ID set. Upload the approved textures with:")
            print("  set ROBLOX_API_KEY=...   (assets read + write, legacy-assets manage)")
            print("  set ROBLOX_USER_ID=...")
            print("  python tools/upload_textures.py \"%s\" \"%s\" --skip-json \"%s\"" % (PNG_DIR, IDS_JSON, reject_path))
        else:
            upload(PNG_DIR, IDS_JSON, reject_path)
            ids = load_json(IDS_JSON, {})
            try:
                fix = alpha_audit.audit_bsp(str(bsp), str(PNG_DIR), {n: ids[n] for n in used if n in ids})
            except RuntimeError as err:
                fail(str(err))
            merge_alpha({asset: png for asset, png in fix.items() if png not in rejected})
    elif new:
        print("  upload skipped (--skip-upload)")

    spawn = data["spawn"]
    bounds = data["bounds"]
    width = bounds["max"][0] - bounds["min"][0]
    depth = bounds["max"][2] - bounds["min"][2]
    height = bounds["max"][1] - bounds["min"][1]
    orbit = {
        "center": [(bounds["min"][0] + bounds["max"][0]) / 2, bounds["min"][1] + height * 0.35,
                   (bounds["min"][2] + bounds["max"][2]) / 2],
        "radius": max(width, depth) * 0.8,
        "height": max(height * 1.6, 120),
    }
    source = WORKSHOP_URL % wid
    insert_catalog(map_id, title, "Imported Gmod Workshop map.", spawn, orbit, source)
    insert_lighting(map_id, args.mood)
    append_asset_row(map_id, wid, title)
    print("  MapCatalog + MapLighting + docs/ASSETS.md updated")

    place_id = ask_place_id(map_id, args.place_id)
    if place_id:
        set_place_id(map_id, place_id)
        print("  MapCatalog placeId = %d" % place_id)
    else:
        print("  placeId left unset; add it to MapCatalog once the place exists")

    ensure_server()
    command = studio_command(map_id, json_path.name)
    copy_clipboard(command)

    print("\nNext in Studio:")
    print("  1. Paste the command above into the command bar (it installs MapImport and builds Workspace.Maps.%s)." % map_id)
    print("  2. Ctrl+S. The meshes live only in the place file.")
    print("  3. Test %s in the main menu%s." % (
        title, "" if place_id else " (in this place until it has its own)"))
    print("  4. If the map is in its own place, publish that place.")


if __name__ == "__main__":
    main()
