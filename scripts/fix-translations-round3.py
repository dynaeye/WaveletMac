#!/usr/bin/env python3
"""第三轮翻译定向修正。

修正韩文字符/语义、两条泰文朝鲜语台名，以及 CCTV-5+ 品牌格式。
城市行政区翻译由 city-fix.py + city-apply.py 负责。
脚本可重复运行；遇到未知旧值时中止，避免覆盖后续人工修订。
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "电台目录翻译.json"
SRC = ROOT / "docs" / "电台目录翻译源数据.json"

doc = json.loads(OUT.read_text(encoding="utf-8"))
source = json.loads(SRC.read_text(encoding="utf-8"))
translations = doc["translations"]
source_by_id = {station["id"]: station for station in source["stations"]}
failures = []
changed = 0


def replace(lang, station_id, field, old, new):
    global changed
    current = translations[lang][station_id][field]
    if current == new:
        return
    if current != old:
        failures.append(
            f"{lang}.{station_id}.{field}: expected {old!r}, found {current!r}"
        )
        return
    translations[lang][station_id][field] = new
    changed += 1


# 韩文：旧金山中误混入泰文字母；“戏曲”不能译成“杂技/西式歌剧”。
replace("ko", "cb9171121408", "group", "샌프란시스โก", "샌프란시스코")
replace("ko", "23964e884936", "name", "CCTV-11 곡예 오디오", "CCTV-11 전통극 오디오")
for station_id, station in source_by_id.items():
    if station["category"] == "文艺戏曲":
        replace("ko", station_id, "category", "문예·오페라", "문예·전통극")

# 泰文：“朝鲜语”在延边语境中是韩语/朝鲜语，不是“北朝鲜”。
replace(
    "th",
    "f1fccae7420e",
    "name",
    "สถานีวิทยุศิลปะและชีวิตเกาหลีเหนือเจียนเปียน (Munye Saenghwal Bangsong)",
    "สถานีวิทยุศิลปะและชีวิตภาษาเกาหลีแห่งเหยียนเปียน (Munye Saenghwal Bangsong)",
)
replace(
    "th",
    "08e6b84897b5",
    "name",
    "สถานีวิทยุข่าวสารเกาหลีเหนือเจียนเปียน (News Jonghap Bangsong)",
    "สถานีวิทยุข่าวสารภาษาเกาหลีแห่งเหยียนเปียน (News Jonghap Bangsong)",
)

# CCTV-5+ 是完整频道品牌，所有语言均保持加号紧随 5。
cctv_alias = {
    "en": ("CCTV-5 +sports event audio", "CCTV-5+ sports event audio"),
    "ja": ("CCTV-5 ＋スポーツ中継音声", "CCTV-5+ スポーツ中継音声"),
    "ko": ("CCTV-5 +스포츠 이벤트 오디오", "CCTV-5+ 스포츠 이벤트 오디오"),
    "th": ("CCTV-5 +เสียงการแข่งขันกีฬา", "CCTV-5+ เสียงการแข่งขันกีฬา"),
    "es": ("CCTV-5 audio de evento deportivo +", "CCTV-5+ audio de eventos deportivos"),
    "ar": ("CCTV-5 صوت حدث رياضي +", "CCTV-5+ صوت الفعاليات الرياضية"),
}
for lang, (old, new) in cctv_alias.items():
    aliases = translations[lang]["05fb6aa706af"]["aliases"]
    current = aliases[0]
    if current == new:
        continue
    if current != old:
        failures.append(
            f"{lang}.05fb6aa706af.aliases[0]: expected {old!r}, found {current!r}"
        )
        continue
    aliases[0] = new
    changed += 1

if failures:
    print("FAILURES:")
    for failure in failures:
        print(" ", failure)
    sys.exit(1)

OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"round3 changed cells: {changed}")
print("written:", OUT)
