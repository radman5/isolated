#!/usr/bin/env python3
"""Repacks the Quaternius Stylized Nature MegaKit GLBs from art_src/ into assets/.

    python3 tools/repack_quaternius.py

Every Poly Pizza GLB embeds its own copy of the same bark and leaf textures, so
38 models came to 62 MB for 14 unique images. This writes each model as a
geometry-only GLB whose materials point at one shared PNG per texture, and drops
the normal maps: the painted-ramp shader doesn't use them.

Source: https://poly.pizza/bundle/Stylized-Nature-MegaKit-T34GZFA0fm (CC0).
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src" / "quaternius"
OUT = ROOT / "assets" / "quaternius_nature"

# The models the route uses. Everything else in art_src stays out of the repo.
KEEP = [
    "Tree_1", "Tree_2", "Tree_3", "Tree_4", "Tree_5",
    "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5",
    "Dead_Tree_1", "Dead_Tree_2", "Dead_Tree_3",
    "Twisted_Tree_1", "Twisted_Tree_2",
    "Bush_1", "Bush_with_Flowers_1", "Fern_1",
    "Grass_1", "Grass_Wispy_1", "Grass_Wispy_2", "Tall_Grass_1",
    "Clover_1", "Clover_2", "Flower_Group_1", "Flower_Group_2",
    "Plant_Big_1", "Plant_Big_2",
    "Rock_Medium_1", "Rock_Medium_2", "Rock_Medium_3",
    "Mushroom_1", "Mushroom_Laetiporus_1",
]


def read_glb(path):
    b = path.read_bytes()
    jlen = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jlen])
    bin_start = 20 + jlen + 8
    blen = struct.unpack("<I", b[20 + jlen:24 + jlen])[0]
    return j, b[bin_start:bin_start + blen]


def pad4(data, fill=b"\0"):
    return data + fill * (-len(data) % 4)


def repack(name):
    j, blob = read_glb(SRC / f"{name}.glb")
    views = j["bufferViews"]

    # 1. Write each used colour image once, and map image index -> file name.
    normal_images = set()
    for m in j.get("materials", []):
        nt = m.get("normalTexture")
        if nt is not None:
            normal_images.add(j["textures"][nt["index"]]["source"])
    image_uri = {}
    for i, im in enumerate(j.get("images", [])):
        if i in normal_images:
            continue
        fname = im.get("name") or f"{name}_{i}.png"
        if not fname.endswith(".png"):
            fname += ".png"
        target = OUT / "textures" / fname
        if not target.exists():
            v = views[im["bufferView"]]
            off = v.get("byteOffset", 0)
            target.write_bytes(blob[off:off + v["byteLength"]])
        image_uri[i] = fname

    # 2. New image list with external URIs; remap textures, drop normal maps.
    old_to_new_img = {}
    j["images"] = []
    for old, fname in image_uri.items():
        old_to_new_img[old] = len(j["images"])
        j["images"].append({"uri": f"../textures/{fname}", "name": fname})
    new_textures, old_to_new_tex = [], {}
    for ti, t in enumerate(j.get("textures", [])):
        if t["source"] in old_to_new_img:
            old_to_new_tex[ti] = len(new_textures)
            new_textures.append({**t, "source": old_to_new_img[t["source"]]})
    j["textures"] = new_textures
    for m in j.get("materials", []):
        m.pop("normalTexture", None)
        pbr = m.get("pbrMetallicRoughness", {})
        for key in ("baseColorTexture", "metallicRoughnessTexture"):
            if key in pbr:
                if pbr[key]["index"] in old_to_new_tex:
                    pbr[key]["index"] = old_to_new_tex[pbr[key]["index"]]
                else:
                    pbr.pop(key)
        for key in ("emissiveTexture", "occlusionTexture"):
            if key in m:
                if m[key]["index"] in old_to_new_tex:
                    m[key]["index"] = old_to_new_tex[m[key]["index"]]
                else:
                    m.pop(key)

    # 3. Rebuild the binary buffer from the views that aren't images.
    image_views = {im["bufferView"] for im in read_glb(SRC / f"{name}.glb")[0].get("images", [])}
    new_views, old_to_new_view, new_blob = [], {}, bytearray()
    for vi, v in enumerate(views):
        if vi in image_views:
            continue
        off = v.get("byteOffset", 0)
        chunk = blob[off:off + v["byteLength"]]
        new_blob += b"\0" * (-len(new_blob) % 4)
        nv = {**v, "byteOffset": len(new_blob)}
        new_blob += chunk
        old_to_new_view[vi] = len(new_views)
        new_views.append(nv)
    j["bufferViews"] = new_views
    for a in j.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = old_to_new_view[a["bufferView"]]
    j["buffers"] = [{"byteLength": len(new_blob)}]

    js = pad4(json.dumps(j, separators=(",", ":")).encode(), b" ")
    bs = pad4(bytes(new_blob))
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(bs))
    out += struct.pack("<I4s", len(js), b"JSON") + js
    out += struct.pack("<I4s", len(bs), b"BIN\0") + bs
    (OUT / "models" / f"{name}.glb").write_bytes(out)
    return len(out)


def main():
    (OUT / "models").mkdir(parents=True, exist_ok=True)
    (OUT / "textures").mkdir(parents=True, exist_ok=True)
    total = sum(repack(n) for n in KEEP)
    tex = sum(p.stat().st_size for p in (OUT / "textures").glob("*.png"))
    print(f"{len(KEEP)} models, {total / 1e6:.1f} MB geometry, "
          f"{len(list((OUT / 'textures').glob('*.png')))} textures, {tex / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
