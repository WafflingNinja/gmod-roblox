"""Resolve Source materials to real textures: BSP pakfile, extracted addon folders, then Gmod's VPKs.

For every material name a map uses this finds the .vmt, follows it to its $basetexture .vtf, decodes one mip
level (<= MAX_SIZE) with Pillow and returns the average colour plus a PNG. Used by bsp_to_json.py; needs Pillow.
"""
import io, os, re, struct, zipfile
from PIL import Image

GMOD = r"C:\Program Files (x86)\Steam\steamapps\common\GarrysMod"
VPKS = (
    r"garrysmod\garrysmod_dir.vpk",
    r"sourceengine\hl2_textures_dir.vpk",
    r"sourceengine\hl2_misc_dir.vpk",
    r"sourceengine\content_cstrike_dir.vpk",
)
MAX_SIZE = 256

# VTF image format -> (Pillow decoder, args, bits per pixel)
FORMATS = {
    0: ("raw", "RGBA", 32), 1: ("raw", "ABGR", 32), 2: ("raw", "RGB", 24), 3: ("raw", "BGR", 24),
    11: ("raw", "ARGB", 32), 12: ("raw", "BGRA", 32), 16: ("raw", "BGRX", 32),
    13: ("bcn", 1, 4), 20: ("bcn", 1, 4), 14: ("bcn", 2, 8), 15: ("bcn", 3, 8),
}


class Vpk:
    """Valve pak, v1/v2 directory file. Only the file index is read up front."""

    def __init__(self, dir_path):
        self.dir_path = dir_path
        self.files = {}
        data = open(dir_path, "rb").read()
        sig, version, tree_size = struct.unpack_from("<III", data, 0)
        assert sig == 0x55AA1234, dir_path
        header = 12 if version == 1 else 28
        self.data_start = header + tree_size
        pos = header

        def read_str():
            nonlocal pos
            end = data.index(b"\0", pos)
            s = data[pos:end].decode("latin-1")
            pos = end + 1
            return s

        while True:
            ext = read_str()
            if not ext:
                break
            while True:
                path = read_str()
                if not path:
                    break
                while True:
                    name = read_str()
                    if not name:
                        break
                    _crc, preload, archive, offset, length, _term = struct.unpack_from("<IHHIIH", data, pos)
                    pos += 18
                    pre = data[pos:pos + preload]
                    pos += preload
                    full = ("%s/%s.%s" % (path, name, ext) if path.strip() else "%s.%s" % (name, ext)).lower()
                    self.files[full] = (archive, offset, length, pre)
        self.dir_data = data

    def read(self, path):
        entry = self.files.get(path)
        if not entry:
            return None
        archive, offset, length, pre = entry
        if archive == 0x7FFF:
            return pre + self.dir_data[self.data_start + offset:self.data_start + offset + length]
        if length == 0:
            return pre
        archive_path = self.dir_path.replace("_dir.vpk", "_%03d.vpk" % archive)
        with open(archive_path, "rb") as fh:
            fh.seek(offset)
            return pre + fh.read(length)


class Library:
    def __init__(self, pak_bytes, addon_dirs):
        self.pak = {}
        if pak_bytes:
            z = zipfile.ZipFile(io.BytesIO(pak_bytes))
            self.pak = {n.lower().replace("\\", "/"): (z, n) for n in z.namelist()}
        self.addon_dirs = addon_dirs
        self.vpks = [Vpk(os.path.join(GMOD, p)) for p in VPKS if os.path.exists(os.path.join(GMOD, p))]

    def read(self, path):
        path = path.lower().replace("\\", "/")
        hit = self.pak.get(path)
        if hit:
            return hit[0].read(hit[1])
        for d in self.addon_dirs:
            full = os.path.join(d, path)
            if os.path.exists(full):
                return open(full, "rb").read()
        for v in self.vpks:
            data = v.read(path)
            if data is not None:
                return data
        return None


def vmt_value(text, key):
    m = re.search(r'"?%s"?\s+"?([^"\r\n}]+?)"?\s*[\r\n}]' % re.escape(key), text, re.I)
    return m.group(1).strip() if m else None


def base_texture(lib, material, depth=0):
    """$basetexture of a material, following `patch` includes (cubemapped map materials are patches)."""
    raw = lib.read("materials/%s.vmt" % material)
    if raw is None or depth > 4:
        return None
    text = raw.decode("latin-1")
    tex = vmt_value(text, "$basetexture")
    if tex:
        return tex.replace("\\", "/")
    include = vmt_value(text, "include")
    if include:
        inc = include.replace("\\", "/").lower()
        inc = re.sub(r"^materials/", "", inc)
        return base_texture(lib, re.sub(r"\.vmt$", "", inc), depth + 1)
    return None


def _mip_bytes(fmt, w, h):
    dec, _arg, bpp = FORMATS[fmt]
    if dec == "bcn":
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * (8 if bpp == 4 else 16)
    return w * h * bpp // 8


def decode_vtf(data):
    sig, major, minor, header_size, width, height, _flags, frames = struct.unpack_from("<4sIIIHHIH", data, 0)
    if sig != b"VTF\0":
        return None
    fmt = struct.unpack_from("<i", data, 52)[0]
    mips = data[56]
    low_fmt = struct.unpack_from("<i", data, 57)[0]
    low_w, low_h = data[61], data[62]
    if fmt not in FORMATS:
        return None
    faces = 1
    if minor >= 3:
        count = struct.unpack_from("<I", data, 68)[0]
        start = None
        for i in range(count):
            tag, offset = struct.unpack_from("<3sxI", data, 80 + i * 8)
            if tag == b"\x30\0\0":
                start = offset
        if start is None:
            return None
    else:
        start = header_size + (_mip_bytes(low_fmt, low_w, low_h) if low_fmt in FORMATS and low_w else 0)
    # Mips are stored smallest first; take the largest one that fits MAX_SIZE.
    levels = []
    pos = start
    for level in range(mips - 1, -1, -1):
        w, h = max(1, width >> level), max(1, height >> level)
        levels.append((pos, w, h))
        pos += _mip_bytes(fmt, w, h) * frames * faces
    fitting = [lv for lv in levels if max(lv[1], lv[2]) <= MAX_SIZE]
    pos, w, h = fitting[-1] if fitting else levels[-1]
    dec, arg, _bpp = FORMATS[fmt]
    blob = data[pos:pos + _mip_bytes(fmt, w, h)]
    if dec == "bcn":
        bw, bh = max(4, (w + 3) // 4 * 4), max(4, (h + 3) // 4 * 4)
        img = Image.frombytes("RGBA", (bw, bh), blob, "bcn", arg).crop((0, 0, w, h))
    else:
        mode = "RGBA" if len(arg) == 4 else "RGB"
        img = Image.frombytes(mode, (w, h), blob, "raw", arg)
    return img.convert("RGBA")


def resolve(lib, materials, png_dir=None):
    """material name -> {"color": [r,g,b], "texture": "<vtf path>", "png": file} for every one that resolved."""
    out = {}
    cache = {}
    for mat in materials:
        tex = base_texture(lib, mat.lower())
        if not tex:
            continue
        tex = tex.lower()
        if tex not in cache:
            raw = lib.read("materials/%s.vtf" % tex)
            img = None
            if raw:
                try:
                    img = decode_vtf(raw)
                except Exception:
                    img = None
            cache[tex] = img
            if img is not None and png_dir:
                path = os.path.join(png_dir, tex.replace("/", "__") + ".png")
                if not os.path.exists(path):
                    img.save(path)
        img = cache[tex]
        if img is None:
            continue
        r, g, b, _a = img.convert("RGBA").resize((1, 1), Image.Resampling.BOX).getpixel((0, 0))
        out[mat] = {"color": [round(r / 255, 3), round(g / 255, 3), round(b / 255, 3)],
                    "texture": tex, "png": tex.replace("/", "__") + ".png"}
    return out
