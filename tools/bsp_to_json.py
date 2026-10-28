"""Source .bsp -> Roblox ingestion JSON.

Parses a Source map (VBSP 20/21) and emits world geometry as tile-chunked triangle soup with per-face
normals, brush doors with pivots, prop-door stand-ins and the player spawn. The output is consumed by
`ServerStorage.MapImport` inside Studio, which builds real MeshParts; nothing here writes into git.

Coords: Source (x, y, z), Z up -> Roblox (x, z, -y) * SCALE + offset. One scale for every map, so props and
door sizes stay consistent between maps.

Layers:
  visual   drawn with the material's texture (tools/source_textures.py), average colour as fallback
  collide  TOOLS/TOOLSNODRAW: invisible but solid (gm_bigcity's street plate is NODRAW)
"""
import argparse, base64, json, math, os, re, struct
from collections import Counter

import source_textures

SCALE = 0.09
CHUNK_TRIS = 8000
TILE = 1200  # MeshParts max out at 2048 studs per axis, so triangles are binned into tiles too
FIT_LIMIT = 1900

LUMP_ENTITIES = 0
LUMP_PLANES = 1
LUMP_TEXDATA = 2
LUMP_VERTEXES = 3
LUMP_TEXINFO = 6
LUMP_FACES = 7
LUMP_EDGES = 12
LUMP_SURFEDGES = 13
LUMP_MODELS = 14
LUMP_TEXDATA_STRING_DATA = 43
LUMP_TEXDATA_STRING_TABLE = 44

SKIP = (
    "TOOLS/TOOLSSKYBOX", "TOOLS/TOOLSTRIGGER", "TOOLS/TOOLSHINT",
    "TOOLS/TOOLSCLIP", "TOOLS/TOOLSPLAYERCLIP", "TOOLS/TOOLSINVISIBLE", "TOOLS/TOOLSBLOCKLIGHT",
    "TOOLS/TOOLSSKYBOX2D", "TOOLS/TOOLSDOTTED", "TOOLS/TOOLSSKY",
)
COLLIDE_ONLY = ("TOOLS/TOOLSNODRAW",)
DOOR_CLASSES = ("func_door", "func_door_rotating", "func_door_rotating_noportal")
PROP_DOOR_CLASSES = ("prop_door_rotating", "prop_door_rotating_custom", "prop_door")
SPAWN_CLASSES = (
    "info_player_start", "info_player_terrorist", "info_player_counterterrorist",
    "info_player_rebel", "info_player_combine",
)


def cstr(buf, off):
    end = buf.index(b"\x00", off)
    return buf[off:end].decode("utf-8", "replace")


def parse_entities(text):
    ents = []
    for block in re.findall(r"\{([^{}]*)\}", text):
        kv = dict(re.findall(r'"([^"]+)"\s+"([^"]*)"', block))
        if kv:
            ents.append(kv)
    return ents


class Bsp:
    def __init__(self, path):
        self.data = open(path, "rb").read()
        ident, self.version = struct.unpack_from("<4si", self.data, 0)
        assert ident == b"VBSP", ident
        self.lumps = [struct.unpack_from("<iii", self.data, 8 + i * 16) for i in range(64)]

    def lump(self, i):
        off, ln, _lv = self.lumps[i]
        return self.data[off:off + ln]

    def parse(self):
        ve = self.lump(LUMP_VERTEXES)
        self.verts = struct.unpack_from("<%df" % (len(ve) // 4), ve, 0)

        ed = self.lump(LUMP_EDGES)
        self.edges = struct.unpack_from("<%dH" % (len(ed) // 2), ed, 0)
        se = self.lump(LUMP_SURFEDGES)
        self.surfedges = struct.unpack_from("<%di" % (len(se) // 4), se, 0)

        pl = self.lump(LUMP_PLANES)
        self.planes = [
            struct.unpack_from("<3f", pl, i) + struct.unpack_from("<f", pl, i + 12)
            for i in range(0, len(pl), 20)
        ]

        td = self.lump(LUMP_TEXDATA)
        texdata = [struct.unpack_from("<iii", td, i + 12) for i in range(0, len(td), 32)]
        nameids = [t[0] for t in texdata]
        self.texsizes = [(max(1, t[1]), max(1, t[2])) for t in texdata]
        sd = self.lump(LUMP_TEXDATA_STRING_DATA)
        st = self.lump(LUMP_TEXDATA_STRING_TABLE)
        names = [cstr(sd, struct.unpack_from("<i", st, i)[0]) for i in range(0, len(st), 4)]
        self.texnames = [names[n] if 0 <= n < len(names) else "?" for n in nameids]

        ti = self.lump(LUMP_TEXINFO)
        self.texinfos = [
            (struct.unpack_from("<i", ti, i + 68)[0], struct.unpack_from("<i", ti, i + 64)[0],
             struct.unpack_from("<4f", ti, i), struct.unpack_from("<4f", ti, i + 16))
            for i in range(0, len(ti), 72)
        ]

        fa = self.lump(LUMP_FACES)
        self.faces = []
        for i in range(0, len(fa), 56):
            planenum, side, _onnode = struct.unpack_from("<HBB", fa, i)
            firstedge = struct.unpack_from("<i", fa, i + 4)[0]
            numedges, texinfo, dispinfo = struct.unpack_from("<hhh", fa, i + 8)
            self.faces.append((planenum, side, firstedge, numedges, texinfo, dispinfo))

        mo = self.lump(LUMP_MODELS)
        self.models = []
        for i in range(0, len(mo), 48):
            mins = struct.unpack_from("<3f", mo, i)
            maxs = struct.unpack_from("<3f", mo, i + 12)
            origin = struct.unpack_from("<3f", mo, i + 24)
            _headnode, firstface, numfaces = struct.unpack_from("<iii", mo, i + 36)
            self.models.append((mins, maxs, origin, firstface, numfaces))

        self.entities = parse_entities(self.lump(LUMP_ENTITIES).decode("utf-8", "replace"))

    def face_polygon(self, f):
        _p, _s, firstedge, numedges, _ti, _d = f
        pts = []
        for i in range(numedges):
            se = self.surfedges[firstedge + i]
            idx = se if se >= 0 else -se
            v = self.edges[idx * 2 + (1 if se < 0 else 0)]
            pts.append((self.verts[v * 3], self.verts[v * 3 + 1], self.verts[v * 3 + 2]))
        return pts

    def face_material(self, f):
        texinfo = f[4]
        if texinfo < 0 or texinfo >= len(self.texinfos):
            return "?"
        texdata = self.texinfos[texinfo][0]
        if texdata < 0 or texdata >= len(self.texnames):
            return "?"
        return self.texnames[texdata]

    def face_uvs(self, f, pts):
        """Source texture coords, in texture repeats (1.0 = one full texture)."""
        texinfo = f[4]
        if texinfo < 0 or texinfo >= len(self.texinfos):
            return [(0.0, 0.0)] * len(pts)
        texdata, _flags, sv, tv = self.texinfos[texinfo]
        w, h = self.texsizes[texdata] if 0 <= texdata < len(self.texsizes) else (1, 1)
        return [((sv[0] * p[0] + sv[1] * p[1] + sv[2] * p[2] + sv[3]) / w,
                 (tv[0] * p[0] + tv[1] * p[1] + tv[2] * p[2] + tv[3]) / h) for p in pts]

    def face_normal(self, f):
        # vbsp keeps the odd (already flipped) plane for back-facing faces and sets side = planenum & 1, so the
        # plane is the face's own normal; negating it again turns ~1/3 of all walls inside out.
        planenum = f[0]
        if planenum >= len(self.planes):
            return (0.0, 1.0, 0.0)
        nx, ny, nz, _dist = self.planes[planenum]
        return (nx, nz, -ny)


def is_skipped(name):
    n = name.upper()
    if n.startswith(COLLIDE_ONLY):
        return False
    return n.startswith(SKIP)


def is_collide_only(name):
    return name.upper().startswith(COLLIDE_ONLY)


def h(name):
    x = 2166136261
    for ch in name:
        x = ((x ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return x


def colour_for(name):
    """A flat colour per material family. Replaced by real textures in a later pass."""
    n = name.upper()
    jitter = ((h(n) % 100) - 50) / 500.0

    def c(r, g, b):
        f = 1.0 + jitter
        return [max(0.0, min(1.0, v * f)) for v in (r, g, b)]

    if "SKY" in n:
        return None
    if any(k in n for k in ("WALLPAPER", "PLASTER", "CEILING", "TILE", "TILES", "WHITEWALL")):
        return c(0.74, 0.71, 0.62)
    if any(k in n for k in ("CARPET", "RUG")):
        return c(0.42, 0.36, 0.28)
    if any(k in n for k in ("GRASS", "NATURE", "DIRT", "MOSS", "LEAF")):
        return c(0.29, 0.41, 0.20)
    if "BRICK" in n:
        return c(0.45, 0.29, 0.24)
    if any(k in n for k in ("WOOD", "PLANK", "TARP")):
        return c(0.38, 0.30, 0.22)
    if any(k in n for k in ("METAL", "STEEL", "HULL", "PIPE", "PANEL", "VENT", "GRATE", "RUST", "DOOR")):
        return c(0.42, 0.44, 0.46)
    if any(k in n for k in ("CONCRETE", "CEMENT", "PAVEMENT", "SIDEWALK", "ROAD", "ASPHALT",
                            "FLOOR", "WAREHOUSE", "STONE", "ROCK")):
        return c(0.47, 0.47, 0.45)
    if any(k in n for k in ("WATER", "POOL")):
        return c(0.20, 0.45, 0.58)
    if any(k in n for k in ("GLASS", "WINDOW")):
        return c(0.55, 0.65, 0.70)
    if any(k in n for k in ("LIGHT", "LAMP", "FLUOR", "NEON")):
        return c(0.92, 0.88, 0.72)
    if any(k in n for k in ("TRIM", "DOOR")):
        return c(0.40, 0.33, 0.26)
    return c(0.46, 0.46, 0.47)


def to_roblox(p, off):
    x, y, z = p
    return (x * SCALE + off[0], z * SCALE + off[1], -y * SCALE + off[2])


def triangulate(bsp, face_indices, off):
    """(material, triangle, normal, uvs) in Roblox space. The normal is per face so walls stay crisp."""
    out = []
    for fi in face_indices:
        f = bsp.faces[fi]
        name = bsp.face_material(f)
        if is_skipped(name) or f[5] != -1:
            continue
        src = bsp.face_polygon(f)
        poly = [to_roblox(p, off) for p in src]
        if len(poly) < 3:
            continue
        uvs = bsp.face_uvs(f, src)
        nrm = bsp.face_normal(f)
        length = math.sqrt(nrm[0] ** 2 + nrm[1] ** 2 + nrm[2] ** 2)
        if length < 1e-6:
            continue
        nrm = (nrm[0] / length, nrm[1] / length, nrm[2] / length)
        for i in range(1, len(poly) - 1):
            a, b, c = poly[0], poly[i], poly[i + 1]
            ua, ub, uc = uvs[0], uvs[i], uvs[i + 1]
            u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            cx = u[1] * v[2] - u[2] * v[1]
            cy = u[2] * v[0] - u[0] * v[2]
            cz = u[0] * v[1] - u[1] * v[0]
            if cx * nrm[0] + cy * nrm[1] + cz * nrm[2] < 0:
                b, c = c, b
                ub, uc = uc, ub
            out.append((name, (a, b, c), nrm, (ua, ub, uc)))
    return out


def _tri_bbox(t):
    xs = [p[0] for p in t]
    ys = [p[1] for p in t]
    zs = [p[2] for p in t]
    return max(max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs))


def _mid(a, b):
    return tuple((x + y) / 2.0 for x, y in zip(a, b))


def subdivide(tris, limit=FIT_LIMIT):
    """A single huge triangle cannot be split by binning, so cut it into four at the edge midpoints."""
    out = []
    stack = list(tris)
    while stack:
        item = stack.pop()
        if _tri_bbox(item[1]) <= limit:
            out.append(item)
            continue
        name, t, nrm, uv = item
        a, b, c = t
        ab, bc, ca = _mid(a, b), _mid(b, c), _mid(c, a)
        ua, ub, uc = uv
        uab, ubc, uca = _mid(ua, ub), _mid(ub, uc), _mid(uc, ua)
        stack.append((name, (a, ab, ca), nrm, (ua, uab, uca)))
        stack.append((name, (ab, b, bc), nrm, (uab, ub, ubc)))
        stack.append((name, (ca, bc, c), nrm, (uca, ubc, uc)))
        stack.append((name, (ab, bc, ca), nrm, (uab, ubc, uca)))
    return out


def bbox(tris):
    xs = [p[0] for t in tris for p in t[1]]
    ys = [p[1] for t in tris for p in t[1]]
    zs = [p[2] for t in tris for p in t[1]]
    return (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs))


def fit(tris, limit=FIT_LIMIT):
    x0, y0, z0, x1, y1, z1 = bbox(tris)
    extents = (x1 - x0, y1 - y0, z1 - z0)
    if max(extents) <= limit or len(tris) <= 1:
        return [tris]
    axis = extents.index(max(extents))
    mid = (bbox(tris)[axis] + bbox(tris)[axis + 3]) / 2.0
    lo, hi = [], []
    for t in tris:
        c = sum(p[axis] for p in t[1]) / 3.0
        (lo if c < mid else hi).append(t)
    if not lo or not hi:
        return [tris]
    return fit(lo, limit) + fit(hi, limit)


def chunk_triangles(tris):
    return [tris[i:i + CHUNK_TRIS] for i in range(0, len(tris), CHUNK_TRIS)]


def encode_chunk(tris):
    lookup = {}
    flat = []
    packed = []
    uvs = []
    normals = []
    normal_ids = {}
    nidx = []
    for item in tris:
        tri_verts = item[1]
        nrm = item[2]
        key = (round(nrm[0], 3), round(nrm[1], 3), round(nrm[2], 3))
        n = normal_ids.get(key)
        if n is None:
            n = len(normals)
            normal_ids[key] = n
            normals.append(key)
        for p, uv in zip(tri_verts, item[3]):
            pkey = (round(p[0], 3), round(p[1], 3), round(p[2], 3))
            ukey = (round(uv[0], 4), round(uv[1], 4))
            i = lookup.get(pkey + ukey)
            if i is None:
                i = len(lookup)
                lookup[pkey + ukey] = i
                packed.append(pkey)
                uvs.append(ukey)
            flat.append(i)
        nidx.append(n)
    pos = b"".join(struct.pack("<3f", *p) for p in packed)
    ids = b"".join(struct.pack("<I", i) for i in flat)
    nrm = b"".join(struct.pack("<3f", *n) for n in normals)
    ni = b"".join(struct.pack("<H", i) for i in nidx)
    uv = b"".join(struct.pack("<2f", *u) for u in uvs)
    return {
        "pos": base64.b64encode(pos).decode(),
        "uv": base64.b64encode(uv).decode(),
        "idx": base64.b64encode(ids).decode(),
        "nrm": base64.b64encode(nrm).decode(),
        "ni": base64.b64encode(ni).decode(),
        "tris": len(tris),
    }


def extract_lights(bsp, off, bounds, cell=16.0, limit=420):
    """Source `light` / `light_spot` entities -> Roblox PointLights.

    Source lighting is baked into lightmaps we do not carry over, so interiors come out black without them.
    Duplicate lights inside the same grid cell are merged (Source maps stack several lights per fitting) and
    the brightest lights win when a map has more than `limit`.
    """
    picked = {}
    for ent in bsp.entities:
        cls = ent.get("classname")
        if cls not in ("light", "light_spot"):
            continue
        try:
            o = tuple(float(v) for v in ent.get("origin", "0 0 0").split())
        except Exception:
            continue
        if len(o) != 3:
            continue
        raw = ent.get("_light", "255 255 255 200").split()
        try:
            r, g, b = (float(raw[0]), float(raw[1]), float(raw[2]))
        except Exception:
            continue
        if len(raw) > 3:
            try:
                brightness = float(raw[3])
            except Exception:
                brightness = 200.0
        elif len(raw) > 2:
            brightness = 200.0
        else:
            brightness = 200.0
        # `_light` is 0..255 in the .bsp, but some maps write 0..1
        if max(r, g, b) <= 1.0:
            r, g, b = r * 255.0, g * 255.0, b * 255.0
        if brightness <= 1.0:
            brightness *= 200.0
        if r + g + b < 8:
            continue
        try:
            dist = float(ent.get("_distance", "0"))
        except Exception:
            dist = 0.0
        if cls == "light_spot":
            try:
                cone = float(ent.get("_cone", "45"))
            except Exception:
                cone = 45.0
        else:
            cone = 180.0
        pos = to_roblox(o, off)
        margin = 400.0
        if not (bounds["min"][0] - margin < pos[0] < bounds["max"][0] + margin
                and bounds["min"][1] - margin < pos[1] < bounds["max"][1] + margin
                and bounds["min"][2] - margin < pos[2] < bounds["max"][2] + margin):
            continue
        key = (int(pos[0] // cell), int(pos[1] // cell), int(pos[2] // cell))
        entry = {
            "pos": [round(v, 2) for v in pos],
            "color": [round(min(1.0, r / 255.0), 3), round(min(1.0, g / 255.0), 3), round(min(1.0, b / 255.0), 3)],
            "brightness": round(max(0.4, min(3.0, brightness / 200.0 * 1.15)), 3),
            "range": round(max(14.0, min(90.0, (dist if dist > 0 else 560.0) * SCALE * 0.55)), 2),
            "cone": cone,
            "score": brightness * 0.7 + (dist * SCALE if dist > 0 else 40.0),
        }
        previous = picked.get(key)
        if previous is None or entry["score"] > previous["score"]:
            picked[key] = entry
    lights = sorted(picked.values(), key=lambda e: -e["score"])[:limit]
    for light in lights:
        light.pop("score", None)
    return lights


def build(map_path, out_path, centre_x, png_dir=None, centre_z=0.0):
    bsp = Bsp(map_path)
    bsp.parse()

    # Real textures: the addon root (the folder holding maps/) is searched after the BSP's own pakfile.
    addon_root = os.path.dirname(os.path.dirname(os.path.abspath(map_path)))
    library = source_textures.Library(bsp.lump(40), [addon_root])
    textures = source_textures.resolve(library, {bsp.face_material(f) for f in bsp.faces}, png_dir)

    def look(name):
        """(group key, colour, png) for a material; materials sharing a texture share a MeshPart."""
        t = textures.get(name)
        if t:
            return t["png"], t["color"], t["png"]
        return name, colour_for(name) or [0.5, 0.5, 0.5], None

    door_models = {}
    for ent in bsp.entities:
        if ent.get("classname") in DOOR_CLASSES:
            mm = re.match(r"\*(\d+)$", ent.get("model", ""))
            if mm and int(mm.group(1)) < len(bsp.models):
                door_models[int(mm.group(1))] = ent

    wm = bsp.models[0]
    mins, maxs = wm[0], wm[1]
    corners = [
        to_roblox((x, y, z), (0.0, 0.0, 0.0))
        for x in (mins[0], maxs[0]) for y in (mins[1], maxs[1]) for z in (mins[2], maxs[2])
    ]
    minx, maxx = min(c[0] for c in corners), max(c[0] for c in corners)
    miny, maxy = min(c[1] for c in corners), max(c[1] for c in corners)
    minz, maxz = min(c[2] for c in corners), max(c[2] for c in corners)
    off = (centre_x - (minx + maxx) / 2.0, 100.0 - miny, centre_z - (minz + maxz) / 2.0)

    world_faces = list(range(wm[3], wm[3] + wm[4]))

    # Brush entities: some maps store their vertices in world space, others store them around (0,0,0) and
    # rely on the entity's `origin` to place them (Source moves the brush at spawn). Tell them apart by asking
    # whether the `origin` already sits inside the model's own bounds.
    model_entity = {}
    for ent in bsp.entities:
        mm = re.match(r"\*(\d+)$", ent.get("model", ""))
        if mm:
            model_entity.setdefault(int(mm.group(1)), ent)

    def model_shift(idx):
        model = bsp.models[idx]
        ent = model_entity.get(idx)
        if not ent or "origin" not in ent:
            return (0.0, 0.0, 0.0)
        try:
            origin = tuple(float(v) for v in ent["origin"].split())
        except Exception:
            return (0.0, 0.0, 0.0)
        if len(origin) != 3:
            return (0.0, 0.0, 0.0)
        center = tuple((model[0][i] + model[1][i]) / 2.0 for i in range(3))
        size = max(model[1][i] - model[0][i] for i in range(3))
        distance = math.sqrt(sum((origin[i] - center[i]) ** 2 for i in range(3)))
        if max(abs(origin[i]) for i in range(3)) > 1.0 and distance > size * 0.75:
            return origin
        return (0.0, 0.0, 0.0)

    shifts = {idx: model_shift(idx) for idx in range(1, len(bsp.models))}

    static_faces = []
    door_faces = {}
    for idx, model in enumerate(bsp.models):
        if idx == 0:
            continue
        first, count = model[3], model[4]
        if idx in door_models:
            door_faces[idx] = list(range(first, first + count))
        else:
            static_faces.extend(range(first, first + count))

    all_tris = triangulate(bsp, world_faces, off)
    for idx in range(1, len(bsp.models)):
        if idx in door_models:
            continue
        shift = shifts[idx]
        delta = (off[0] + shift[0] * SCALE, off[1] + shift[2] * SCALE, off[2] - shift[1] * SCALE)
        all_tris.extend(triangulate(bsp, range(bsp.models[idx][3], bsp.models[idx][3] + bsp.models[idx][4]), delta))

    # Brush entities can sit at garbage coordinates; keep only geometry near the world model.
    margin = 4096.0
    lim_x = ((mins[0] - margin) * SCALE + off[0], (maxs[0] + margin) * SCALE + off[0])
    lim_y = ((mins[2] - margin) * SCALE + off[1], (maxs[2] + margin) * SCALE + off[1])
    lim_z = (-(maxs[1] + margin) * SCALE + off[2], -(mins[1] - margin) * SCALE + off[2])

    def inside(t):
        for p in t[1]:
            if (p[0] < lim_x[0] or p[0] > lim_x[1] or p[1] < lim_y[0] or p[1] > lim_y[1]
                    or p[2] < lim_z[0] or p[2] > lim_z[1]):
                return False
        return True

    kept = [t for t in all_tris if inside(t)]
    dropped = len(all_tris) - len(kept)

    buckets = {}
    for name, tri, nrm, uv in kept:
        cx = (tri[0][0] + tri[1][0] + tri[2][0]) / 3.0
        cy = (tri[0][1] + tri[1][1] + tri[2][1]) / 3.0
        cz = (tri[0][2] + tri[1][2] + tri[2][2]) / 3.0
        layer = "collide" if is_collide_only(name) else "visual"
        key = (look(name)[0], layer, int(cx // TILE), int(cy // TILE), int(cz // TILE))
        buckets.setdefault(key, []).append((name, tri, nrm, uv))

    small = {}
    chunks = []
    for key, tris in buckets.items():
        layer = key[1]
        name = tris[0][0]
        _group, col, png = look(name)
        if png is None and len(tris) < 250:
            small.setdefault((layer,) + key[2:], []).extend(tris)
            continue
        for piece in fit(subdivide(tris)):
            for chunk in chunk_triangles(piece):
                entry = encode_chunk(chunk)
                entry.update({"mat": name, "color": col, "layer": layer, "tex": png})
                chunks.append(entry)
    for key, tris in small.items():
        for piece in fit(subdivide(tris)):
            for chunk in chunk_triangles(piece):
                entry = encode_chunk(chunk)
                entry.update({"mat": "MISC", "color": [0.46, 0.46, 0.47], "layer": key[0]})
                chunks.append(entry)

    doors = []
    for idx, ent in door_models.items():
        shift = shifts.get(idx, (0.0, 0.0, 0.0))
        door_off = (off[0] + shift[0] * SCALE, off[1] + shift[2] * SCALE, off[2] - shift[1] * SCALE)
        tris = triangulate(bsp, door_faces[idx], door_off)
        if not tris:
            continue
        counts = Counter(t[0] for t in tris)
        main_mat = counts.most_common(1)[0][0]
        col = look(main_mat)[1]
        by_texture = {}
        for t in tris:
            by_texture.setdefault(look(t[0])[0], []).append(t)
        dchunks = []
        for group in by_texture.values():
            _g, gcol, png = look(group[0][0])
            for piece in fit(subdivide(group)):
                for chunk in chunk_triangles(piece):
                    entry = encode_chunk(chunk)
                    entry.update({"color": gcol, "tex": png})
                    dchunks.append(entry)
        try:
            o = tuple(float(v) for v in ent.get("origin", "0 0 0").split())
        except Exception:
            o = bsp.models[idx][2]
        # A door's hinge is its own origin, so it needs no extra shift.
        pivot = to_roblox(o, off)
        cls = ent.get("classname", "func_door")
        model = bsp.models[idx]
        width = max(model[1][0] - model[0][0], model[1][1] - model[0][1])
        try:
            distance = float(ent.get("distance", "90"))
            speed = float(ent.get("speed", "100"))
        except Exception:
            distance, speed = 90.0, 100.0
        try:
            if "angle" in ent:
                angle = float(ent["angle"])
            elif "angles" in ent:
                angle = float(ent["angles"].split()[1])
            else:
                angle = 0.0
        except Exception:
            angle = 0.0
        doors.append({
            "name": ent.get("targetname") or ("door_%d" % idx),
            "kind": "rotate" if "rotating" in cls else "slide",
            "pivot": list(pivot),
            "angle": angle,
            "hasAngle": ("angle" in ent or "angles" in ent),
            "distance": distance,
            "speed": speed,
            "width": width,
            "color": col,
            "chunks": dchunks,
        })

    # prop doors: the model itself is a prop, so the importer stands a slab in the doorway
    for ent in bsp.entities:
        if ent.get("classname") not in PROP_DOOR_CLASSES:
            continue
        try:
            o = tuple(float(v) for v in ent.get("origin", "0 0 0").split())
        except Exception:
            continue
        try:
            ang = float(ent.get("angles", "0 0 0").split()[1])
        except Exception:
            ang = 0.0
        doors.append({
            "name": ent.get("targetname") or "propdoor",
            "kind": "prop",
            "pivot": list(to_roblox(o, off)),
            "angle": ang,
            "hasAngle": True,
            "distance": float(ent.get("distance", "90") or 90),
            "speed": 100.0,
            "width": 64.0,
            "color": [0.40, 0.33, 0.26],
            "chunks": [],
        })

    spawn = None
    for ent in bsp.entities:
        if ent.get("classname") in SPAWN_CLASSES:
            try:
                s = tuple(float(v) for v in ent.get("origin", "0 0 0").split())
            except Exception:
                continue
            spawn = list(to_roblox(s, off))
            break
    if spawn is None:
        spawn = [centre_x, off[1] + 20, off[2]]

    bounds = {"min": [minx + off[0], miny + off[1], minz + off[2]],
              "max": [maxx + off[0], maxy + off[1], maxz + off[2]]}
    data = {
        "name": map_path.replace("\\", "/").split("/")[-1].replace(".bsp", ""),
        "version": bsp.version,
        "scale": SCALE,
        "offset": list(off),
        "bounds": bounds,
        "spawn": spawn,
        "chunks": chunks,
        "doors": doors,
        "lights": extract_lights(bsp, off, bounds),
        "stats": {"tris": len(kept), "dropped": dropped, "doors": len(doors),
                  "spawns": sum(1 for e in bsp.entities if e.get("classname") == "info_player_start")},
    }
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("bsp")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("-x", "--centre-x", type=float, default=20000.0)
    ap.add_argument("-z", "--centre-z", type=float, default=0.0)
    ap.add_argument("--png-dir", help="write each resolved texture here as <path__name>.png")
    args = ap.parse_args()
    data = build(args.bsp, args.out, args.centre_x, args.png_dir, args.centre_z)
    print("%s: tris=%d dropped=%d chunks=%d doors=%d spawn=%s bounds=%s" % (
        data["name"], data["stats"]["tris"], data["stats"]["dropped"], len(data["chunks"]),
        data["stats"]["doors"], [round(v) for v in data["spawn"]],
        {k: [round(x) for x in v] for k, v in data["bounds"].items()}))


if __name__ == "__main__":
    main()