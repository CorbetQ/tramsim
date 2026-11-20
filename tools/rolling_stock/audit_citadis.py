"""Offline provenance/asset validation; optional rights-cleared photo cache refill.

python tools/rolling_stock/audit_citadis.py
python tools/rolling_stock/audit_citadis.py --write-manifest   # after local rebuild
python tools/rolling_stock/audit_citadis.py --download-references
No Meshy generation, credentials, or charges from this tool.
"""
import argparse
import hashlib
import json
import struct
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "data/rolling_stock/meshy_sources"
ASSETS = ROOT / "data/rolling_stock/meshy_citadis"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def glb_info(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from("<4sII", raw)
    assert magic == b"glTF" and version == 2 and size == len(raw), path
    chunk_size, chunk_type = struct.unpack_from("<II", raw, 12)
    assert chunk_type == 0x4E4F534A
    doc = json.loads(raw[20:20+chunk_size])
    assert not any("uri" in b for b in doc.get("buffers", [])), "External buffer"
    assert not any("uri" in i for i in doc.get("images", [])), "External image"
    triangles = 0
    for mesh in doc["meshes"]:
        for primitive in mesh["primitives"]:
            assert primitive.get("mode", 4) == 4
            triangles += doc["accessors"][primitive["indices"]]["count"] // 3
    return {"bytes":size,"sha256":sha(path),"triangles":triangles,
            "mesh_count":len(doc["meshes"]),"embedded_images":len(doc.get("images", [])),
            "max_surfaces":max(len(m["primitives"]) for m in doc["meshes"]),
            "vertex_palette":all("COLOR_0" in p["attributes"] and "TEXCOORD_0" in p["attributes"] for m in doc["meshes"] for p in m["primitives"])}


def allowed(row):
    license_ = row["license"]
    return (not row["study_only"] and row["ai_upload_allowed"] and
            (license_ == "CC0" or license_.startswith("CC BY")) and
            "NC" not in license_ and "ND" not in license_)


def download(row):
    # Only thumbnails already identified through the official Commons API.
    assert allowed(row) and isinstance(row["id"], int)
    url = row["reference_url"]
    parsed = urllib.parse.urlparse(url)
    assert parsed.scheme == "https" and parsed.hostname in {"thumb.wikimedia.org","upload.wikimedia.org"}
    cache = ROOT / ".cache/meshy_rebuild" / row["family"]
    cache.mkdir(parents=True, exist_ok=True)
    path = cache / (str(row["id"])+".jpg")
    if path.exists():
        assert sha(path) == row["sha256"], f"Changed cached reference {row['id']}"
        return
    partial = path.with_suffix(".part")
    try:
        request = urllib.request.Request(url,headers={"User-Agent":"TramSimReferenceResearch/1.0"})
        with urllib.request.urlopen(request,timeout=40) as response, partial.open("wb") as output:
            size = 0
            while block := response.read(65536):
                size += len(block)
                assert size < 12*1024*1024, "Reference size limit"
                output.write(block)
        assert sha(partial) == row["sha256"], f"Reference content changed: {row['page_url']}"
        partial.replace(path)
        time.sleep(.3)
    finally:
        partial.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write-manifest",action="store_true")
    parser.add_argument("--download-references",action="store_true")
    args = parser.parse_args()
    catalog = json.loads((SOURCES/"references.json").read_text())
    tasks = json.loads((SOURCES/"tasks.json").read_text())
    ids = set()
    refs = {}
    for family, data in catalog["families"].items():
        reviewed = [r for r in data["references"] if r["review_status"]=="subject_reviewed"]
        assert len(reviewed)>=10, family
        assert any(r["role"]=="interior" for r in reviewed), family+" missing interior references"
        for row in reviewed:
            assert row["page_url"].startswith("https://") and row["author"]
            assert len(row["sha256"])==64
            assert not row["study_only"] or not row["ai_upload_allowed"]
            if row["ai_upload_allowed"]:assert allowed(row), row["id"]
            refs[row["id"]] = row
            if args.download_references and allowed(row):download(row)
        print(f"{family}: {len(reviewed)} reviewed references, interior included")
    for task in tasks["tasks"]:
        assert task["status"]=="SUCCEEDED" and task["task_id"] not in ids
        ids.add(task["task_id"])
        for id_ in task.get("reference_ids",[]) + ([task["source_photo_id"]] if "source_photo_id" in task else []):
            assert allowed(refs[id_]), f"Unlicensed AI input {id_}"
        if "interior_seat" in task["component"]:
            path = SOURCES/"inputs"/(task["component"].split("_")[0]+".png")
            assert sha(path)==task["input_sha256"]
    assert sum(t["consumed_credits"] for t in tasks["tasks"])==tasks["actual_credits"]==90
    manifest = {p.name:glb_info(p) for p in sorted(ASSETS.glob("*.glb"))}
    assert len(manifest)==6
    for name, data in manifest.items():
        assert data["bytes"]<6*1024*1024
        assert data["triangles"]<12000 if "body" in name else data["triangles"]<1600
        if "body" in name:assert data["max_surfaces"]==1 and data["vertex_palette"]
        assert data["embedded_images"]==0, "Photographic textures must not return"
        settings = (ASSETS/(name+".import")).read_text()
        assert "meshes/generate_lods=true" in settings
        assert "gltf/embedded_image_handling=2" in settings
    path = SOURCES/"assets.json"
    if args.write_manifest:path.write_text(json.dumps(manifest,indent=2)+"\n")
    else:assert json.loads(path.read_text())==manifest, "Assets changed: rebuild and inspect before updating manifest"
    print(f"OK: {len(manifest)} GLBs, {sum(d['bytes'] for d in manifest.values()):,} bytes, 90 recorded credits")


if __name__ == "__main__":
    main()
