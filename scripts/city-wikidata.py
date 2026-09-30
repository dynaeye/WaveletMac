#!/usr/bin/env python3
"""Fetch Wikidata labels (en/ja/ko/th/es/ar) for all city entries, incremental."""
import json, subprocess, time, random, os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "city-wdlabels.json")
SRC = os.path.join(os.path.dirname(HERE), "docs", "电台目录翻译源数据.json")
PROG = os.path.join(HERE, "city-langlinks.json")

CAND = {
    "思茅": ["思茅区", "思茅县"],
    "襄樊": ["襄樊市"],
    "达拉斯 / 沃思堡": [],
    "重庆": ["重庆市"],
    "金华": ["金华市"],
    "钦州": ["钦州市"],
    "铜仁地区": ["铜仁地区", "铜仁市"],
    "铜陵": ["铜陵市"],
    "银川": ["银川市"],
    "锦州": ["锦州市"],
    "黄冈": ["黄冈市"],
    "黄山": ["黄山市"],
    "宝鸡": ["宝鸡市"],
    "聊城": ["聊城市"],
    "毕节地区": ["毕节地区", "毕节市"],
    "宁波": ["宁波市"],
    "苏州": ["苏州市"],
    "德州": ["德州市"],
    "四平": ["四平市"],
    "抚州": ["抚州市"],
    "吉林": ["吉林市"],
    "台北": ["臺北市"],
    "松原": ["松原市"],
    "白山": ["白山市"],
    "德州": ["德州市"],
    "荷泽": ["菏泽市"],
    "安康": ["安康市"],
    "黄石": ["黄石市"],
    "三明": ["三明市"],
    "九江": ["九江市"],
    "信阳": ["信阳市"],
    "南充": ["南充市"],
    "南宁": ["南宁市"],
    "娄底": ["娄底市"],
    "宜昌": ["宜昌市"],
    "宣城": ["宣城市"],
    "岳阳": ["岳阳市"],
    "巴中": ["巴中市"],
    "常德": ["常德市"],
    "怀化": ["怀化市"],
    "朝阳": ["朝阳市"],
    "柳州": ["柳州市"],
    "桂林": ["桂林市"],
    "汕头": ["汕头市"],
    "洛阳": ["洛阳市"],
    "淮北": ["淮北市"],
    "滨州": ["滨州市"],
    "石河子": ["石河子市"],
    "荆州": ["荆州市"],
    "贺州": ["贺州市"],
    "资阳": ["资阳市"],
    "赣州": ["赣州市"],
    "通化": ["通化市"],
    "邵阳": ["邵阳市"],
    "达拉斯 / 沃思堡": ["达拉斯", "沃思堡"],
}

src = json.load(open(SRC))
prog = json.load(open(PROG))
cities = sorted({s["city"] for s in src["stations"] if s["city"]})
state = json.load(open(OUT)) if os.path.exists(OUT) else {"title": {}, "labels": {}}
t2lab = state["labels"]
city2title = state["title"]

city_titles = {}
for c in cities:
    if c in CAND:
        city_titles[c] = CAND[c]
    elif c in prog:
        city_titles[c] = [prog[c]["zh_title"]]
    else:
        city_titles[c] = [c + "市", c]

todo_titles = sorted({t for c in cities if c not in city2title for t in city_titles[c]})
print("todo titles:", len(todo_titles), flush=True)


def wd(params, tries=5):
    args = ["curl", "-sS", "--fail", "--max-time", "25", "-X", "POST",
            "https://www.wikidata.org/w/api.php"]
    for k, v in params.items():
        args += ["--data-urlencode", f"{k}={v}"]
    p = None
    for a in range(tries):
        p = subprocess.run(args, capture_output=True, timeout=35)
        if p.returncode == 0:
            try:
                return json.loads(p.stdout.decode())
            except Exception:
                pass
        time.sleep(2 * (a + 1) + random.random() * 2)
    raise RuntimeError((p.stderr.decode() if p else "")[:150])


def save():
    json.dump({"title": city2title, "labels": t2lab}, open(OUT, "w"),
              ensure_ascii=False, indent=1)


B = 15
for i in range(0, len(todo_titles), B):
    batch = todo_titles[i:i + B]
    try:
        d = wd({"action": "wbgetentities", "sites": "zhwiki", "titles": "|".join(batch),
                "props": "labels|sitelinks", "sitefilter": "zhwiki",
                "languages": "en|ja|ko|th|es|ar", "format": "json"})
    except Exception as e:
        print("batch fail:", e, flush=True)
        continue
    for q, e in d.get("entities", {}).items():
        if "missing" in e or q == "-1":
            continue
        zt = e.get("sitelinks", {}).get("zhwiki", {}).get("title")
        if not zt:
            continue
        t2lab[zt] = {l: e["labels"][l]["value"] for l in e.get("labels", {})}
    # 反查 city
    for c in cities:
        if c in city2title:
            continue
        for t in city_titles[c]:
            if t in t2lab and t2lab[t]:
                city2title[c] = t
                break
    save()
    print(f"[{min(i+B, len(todo_titles))}/{len(todo_titles)}] cities mapped={len(city2title)}/{len(cities)}", flush=True)
    time.sleep(0.4)

unmapped = [c for c in cities if c not in city2title]
print("unmapped cities:", unmapped, flush=True)
# 多语言覆盖统计
cov = {L: 0 for L in ["en", "ja", "ko", "th", "es", "ar"]}
for c in cities:
    if c in city2title:
        lab = t2lab.get(city2title[c], {})
        for L in cov:
            if L in lab:
                cov[L] += 1
print("label coverage:", cov, flush=True)
