#!/usr/bin/env python3
"""把 city-final.json 的城市译名写回 docs/电台目录翻译.json。
只修改 translations.<lang>.<id>.city，其余字段与字节格式（indent=2、
ensure_ascii=False、字段顺序）保持不变。源数据只读。"""
import json, hashlib, sys
from pathlib import Path

H = Path(__file__).parent
DOCS = H.parent / "docs"
OUT = DOCS / "电台目录翻译.json"
SRC = DOCS / "电台目录翻译源数据.json"
LANGS = ["en", "ja", "ko", "th", "es", "ar"]

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

src_sha_before = sha(SRC)
doc_sha_before = sha(OUT)

final = json.load(open(H / "city-final.json", encoding="utf-8"))
stations = json.load(open(SRC, encoding="utf-8"))
doc = json.load(open(OUT, encoding="utf-8"))

# 源：city 非空的 station id 集
src_city = {}          # id -> city
if isinstance(stations, list):
    it = stations
else:
    it = stations.get("stations") or stations.get("data")
for st in it:
    src_city[st["id"]] = (st.get("city") or "").strip()

# 回写
changed = 0
filled = 0
emptied = 0
for lang in LANGS:
    block = doc["translations"][lang]
    for sid, entry in block.items():
        city = src_city.get(sid, None)
        if city is None:
            raise SystemExit(f"station id 不在源数据: {sid}")
        if city:
            new = final[city][lang]
            if entry["city"] != new:
                entry["city"] = new
                changed += 1
            filled += 1
        else:
            if entry["city"] != "":
                entry["city"] = ""
                emptied += 1

# 写回（与原格式一致）
OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

print("changed cells:", changed, "| filled non-empty:", filled, "| cleared:", emptied)
print("src sha:", src_sha_before[:16], "unchanged" if sha(SRC) == src_sha_before else "CHANGED!!")
print("doc sha:", doc_sha_before[:16], "->", sha(OUT)[:16])
