#!/usr/bin/env python3
"""Merge city name translations: Wikidata label > Wikipedia sitelink title > Google cache.

Normalization: strip admin suffixes when source has none (市/시/' City'),
strip ar 'مدينة ' prefix and parenthetical disambiguators (except collision groups,
which keep the wiki disambiguator). Detect cross-city collisions per language.
Outputs city-merged.json and prints audit lists.
"""
import json, re, os, collections

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "docs", "电台目录翻译源数据.json")
WDL = os.path.join(HERE, "city-wdlabels.json")
SIT = os.path.join(HERE, "city-sitelinks.json")
GOOG = os.path.join(HERE, "city-cache.json")
OUT = os.path.join(HERE, "city-merged.json")

src = json.load(open(SRC))
wd = json.load(open(WDL))
sit = json.load(open(SIT))
gcache = json.load(open(GOOG))
LANGS = ["en", "ja", "ko", "th", "es", "ar"]

cities = []
for st in src["stations"]:
    c = st["city"]
    if c and c not in cities:
        cities.append(c)
print("cities:", len(cities))

# ---------- normalization helpers ----------
HAN = re.compile(r"[\u4e00-\u9fff]")

def strip_suffix(v, lang, src_c):
    """Strip trailing admin suffix for the language, only when source lacks it."""
    if lang == "ja":
        if not src_c.endswith(("市", "県", "地区", "自治州", "州", "盟")):
            v = re.sub(r"(市|縣)$", "", v)
    elif lang == "ko":
        if not src_c.endswith(("市", "地区", "自治州", "州", "盟")):
            v = re.sub(r"시$", "", v)
            v = re.sub(r"시(?=\s|\()", "", v)
    elif lang == "en":
        if not src_c.endswith(("地区", "自治州", "州", "盟")):
            v = re.sub(r"\s+City$", "", v)
    elif lang == "ar":
        v = re.sub(r"^مدينة\s+", "", v)
    # strip trailing parenthetical disambiguators only for non-collision use (handled later)
    return v.strip()

def garbage(v, lang):
    if not v:
        return True
    if lang in ("en", "es", "th", "ar") and HAN.search(v):
        return True
    if lang == "ko" and HAN.search(v):
        return True
    if lang == "ja":
        # unchanged simplified Chinese with no kana/kanji-standard? too strict; only flag empty
        return False
    # non-latin scripts sanity
    if lang == "th" and not re.search(r"[\u0e00-\u0e7f]", v):
        return True
    if lang == "ar" and not re.search(r"[\u0600-\u06ff]", v):
        return True
    if lang == "ko" and not re.search(r"[\uac00-\ud7af]", v):
        return True
    if lang in ("en", "es") and not re.search(r"[A-Za-z]", v):
        return True
    return False

# ---------- merge ----------
merged = {}
for c in cities:
    title = wd["title"].get(c)
    labels = wd["labels"].get(title, {}) if title else {}
    sites = sit.get(title, {}) if title else {}
    row = {}
    for L in LANGS:
        wiki_title = sites.get(f"{ {'en':'en','ja':'ja','ko':'ko','th':'th','es':'es','ar':'ar'}[L] }wiki")
        cand = [
            ("wd", labels.get(L)),
            ("wiki", wiki_title),
            ("google", gcache.get(f"{L}|{c}")),
        ]
        pick, src_used = None, None
        for s, v in cand:
            if v and not garbage(v, L):
                pick, src_used = v, s
                break
        if pick is None:
            # accept garbage as last resort flag
            pick = next((v for _, v in cand if v), "")
            src_used = "GARBAGE" if pick else "NONE"
        row[L] = {"v": pick, "src": src_used}
    merged[c] = row

# ---------- collisions ----------
collisions = {}
for L in LANGS:
    by_v = collections.defaultdict(list)
    for c in cities:
        v = merged[c][L]["v"]
        if v:
            by_v[v].append(c)
    for v, cs in by_v.items():
        if len(cs) > 1:
            collisions.setdefault(L, {})[v] = cs

# for collisions, prefer wiki title (has disambiguator) for all members
for L, groups in collisions.items():
    for v, cs in groups.items():
        for c in cs:
            title = wd["title"].get(c)
            sites = sit.get(title, {}) if title else {}
            wt = sites.get(f"{L}wiki")
            if wt:
                merged[c][L]["v"] = wt
                merged[c][L]["src"] = "collision:wiki"

# ---------- apply suffix normalization (skip collision rows) ----------
for c in cities:
    for L in LANGS:
        if merged[c][L]["src"].startswith("collision"):
            continue
        merged[c][L]["v"] = strip_suffix(merged[c][L]["v"], L, c)

# ---------- audits ----------
print("\n== src stats ==", collections.Counter(
    merged[c][L]["src"] for c in cities for L in LANGS))
print("\n== NONE/GARBAGE ==")
for c in cities:
    for L in LANGS:
        if merged[c][L]["src"] in ("NONE", "GARBAGE"):
            print(f"  {L} {c} -> {merged[c][L]['v']!r} {merged[c][L]['src']}")
print("\n== Han residue in en/es/th/ar/ko ==")
for c in cities:
    for L in LANGS:
        if L != "ja" and HAN.search(merged[c][L]["v"] or ""):
            print(f"  {L} {c} -> {merged[c][L]['v']!r} ({merged[c][L]['src']})")
print("\n== google-fallback cells (review list) ==")
n = 0
for c in cities:
    for L in LANGS:
        if merged[c][L]["src"] == "google":
            n += 1
            print(f"  {L}|{c} = {merged[c][L]['v']}")
print("google cells:", n)
print("\n== collisions ==")
for L, g in collisions.items():
    for v, cs in g.items():
        print(f"  {L} {v!r}: {cs} -> {[merged[c][L]['v'] for c in cs]}")

# lowercase-start en/es (fix by capitalizing)
lower = [(c, L) for c in cities for L in ("en", "es")
         if merged[c][L]["v"] and merged[c][L]["v"][0].islower()]
print("\n== lowercase-start en/es ==", lower)

# empty checks
empty = [(c, L) for c in cities for L in LANGS if not merged[c][L]["v"]]
print("== empty ==", empty)

out = {c: {L: merged[c][L]["v"] for L in LANGS} for c in cities}
json.dump(out, open(OUT, "w"), ensure_ascii=False, indent=1)
print("\nsaved", OUT, len(out), "cities")
