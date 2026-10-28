"""List uploaded textures whose alpha is a shine mask (opaque material) rather than real transparency."""
import json
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bsp_to_json  # noqa: E402
import source_textures  # noqa: E402

try:
    from PIL import Image  # noqa: E402
except ImportError:  # the converter only needs Pillow for the alpha audit / texture PNGs
    Image = None

OUT = os.path.join(os.environ.get("TEMP") or tempfile.gettempdir(), "kilo", "maps_out")
SEE_THROUGH = re.compile(r'"?\$(translucent|alphatest|additive)"?\s+"?1', re.I)


def vmt_text(lib, material, depth=0):
    raw = lib.read("materials/%s.vmt" % material)
    if raw is None or depth > 4:
        return ""
    text = raw.decode("latin-1")
    inc = source_textures.vmt_value(text, "include")
    if inc:
        inc = inc.replace("\\", "/").lower()
        inc = re.sub(r"^materials/", "", inc)
        inc = re.sub(r"\.vmt$", "", inc)
        text += vmt_text(lib, inc, depth + 1)
    return text


def main():
    if Image is None:
        raise SystemExit("Pillow is required: pip install Pillow")
    ids = json.load(open(os.path.join(OUT, "texture_ids.json")))
    legit = set()
    used = set()
    for name in ["mallparking", "bangclaw", "bigcity", "backrooms", "brmovie"]:
        maps_dir = os.path.join(OUT, name, "maps")
        path = os.path.join(maps_dir, next(f for f in os.listdir(maps_dir) if f.endswith(".bsp")))
        bsp = bsp_to_json.Bsp(path)
        bsp.parse()
        lib = source_textures.Library(bsp.lump(40), [os.path.dirname(maps_dir)])
        for mat in {bsp.face_material(f) for f in bsp.faces}:
            text = vmt_text(lib, mat)
            tex = source_textures.vmt_value(text, "$basetexture")
            if not tex:
                continue
            png = tex.replace("\\", "/").lower().replace("/", "__") + ".png"
            used.add(png)
            if SEE_THROUGH.search(text):
                legit.add(png)

    fix = {}
    for png, asset in ids.items():
        p = os.path.join(OUT, "png", png)
        if png in legit or not os.path.exists(p):
            continue
        im = Image.open(p)
        if im.mode != "RGBA":
            continue
        h = im.getchannel("A").histogram()
        if sum(h[:250]) / sum(h) > 0.01:
            fix[asset] = png
    print("legit see-through:", len(legit & set(ids)), " shine-mask (fix):", len(fix))
    for png in sorted(legit & set(ids)):
        print("  keep", png)
    json.dump(fix, open(os.path.join(OUT, "alpha_fix.json"), "w"), indent=0)


def audit_bsp(bsp_path, png_dir, ids):
    """Shine-mask audit for one extracted map. Returns {assetId: pngName} for uploads whose alpha should be
    SurfaceAppearance Overlay instead of real transparency. ids is the shared png-name -> asset map."""
    if Image is None:
        raise RuntimeError("Pillow is required for the alpha audit: pip install Pillow")
    bsp = bsp_to_json.Bsp(bsp_path)
    bsp.parse()
    maps_dir = os.path.dirname(os.path.abspath(bsp_path))
    lib = source_textures.Library(bsp.lump(40), [os.path.dirname(maps_dir)])
    legit = set()
    for mat in {bsp.face_material(f) for f in bsp.faces}:
        text = vmt_text(lib, mat)
        tex = source_textures.vmt_value(text, "$basetexture")
        if not tex:
            continue
        png = tex.replace("\\", "/").lower().replace("/", "__") + ".png"
        if SEE_THROUGH.search(text):
            legit.add(png)
    result = {}
    for png, asset in ids.items():
        p = os.path.join(png_dir, png)
        if png in legit or not os.path.exists(p):
            continue
        im = Image.open(p)
        if im.mode != "RGBA":
            continue
        histogram = im.getchannel("A").histogram()
        if sum(histogram[:250]) / sum(histogram) > 0.01:
            result[asset] = png
    return result


if __name__ == "__main__":
    main()
