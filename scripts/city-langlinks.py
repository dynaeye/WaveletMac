#!/usr/bin/env python3
"""Resolve canonical city names in 6 languages via zh.wikipedia langlinks.

Fallback chain: Wikipedia langlink title -> Google MT cache -> manual override.
Writes progress incrementally to scripts/city-langlinks.json.
"""
import json, subprocess, urllib.parse, time, os, random, sys

PX = "http://127.0.0.1:7890"
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "docs", "电台目录翻译源数据.json")
PROG = os.path.join(HERE, "city-langlinks.json")
TARGETS = ["en", "ja", "ko", "th", "es", "ar"]
LANGMAP = {"en": "en", "ja": "ja", "ko": "ko", "th": "th", "es": "es", "ar": "ar"}

ALIAS = {"荷泽": ["菏泽市"], "达拉斯 / 沃思堡": [], "思茅": [], "襄樊": []}
SUFFIXES = ["地区", "市", "县", "区", "盟"]

src = json.load(open(SRC))
cities = sorted({s["city"] for s in src["stations"] if s["city"]})


def cands_for(c):
    if c in ALIAS:
        return ALIAS[c]
    if "自治州" in c or c.endswith("地区") or c.endswith("盟") or c.endswith("州") and "自治州" in c:
        return [c]
    if c.endswith("自治州"):
        return [c]
    return [c + s for s in SUFFIXES] + [c]


def api(params, tries=3):
    args = ["curl", "-sS", "--fail", "--max-time", "20", "-x", PX, "-X", "POST",
            "https://zh.wikipedia.org/w/api.php"]
    for k, v in params.items():
        args += ["--data-urlencode", f"{k}={v}"]
    p = None
    for a in range(tries):
        p = subprocess.run(args, capture_output=True, timeout=30)
        if p.returncode == 0:
            try:
                return json.loads(p.stdout.decode())
            except Exception:
                pass
        time.sleep(0.8 * (a + 1) + random.random() * 0.5)
    err = p.stderr.decode() if p else "no run"
    raise RuntimeError("api failed: " + err[:120])


prog = json.load(open(PROG)) if os.path.exists(PROG) else {}
todo = [c for c in cities if c not in prog and cands_for(c)]

# --- step 1: resolve titles -> Q/pageid ---
groups, cur, n = [], [], 0
for c in todo:
    cur.append(c)
    n += len(cands_for(c))
    if n >= 8:
        groups.append(cur)
        cur, n = [], 0
if cur:
    groups.append(cur)

print(f"resolve groups: {len(groups)}", flush=True)
for gi, group in enumerate(groups):
    titles = []
    for c in group:
        titles.extend(cands_for(c))
    seen = set()
    t2 = [t for t in titles if not (t in seen or seen.add(t))]
    try:
        d = api({"action": "query", "titles": "|".join(t2), "prop": "pageids",
                 "redirects": "", "format": "json"})
    except Exception as e:
        print("group fail", group, e, flush=True)
        continue
    pages = d.get("query", {}).get("pages", {})
    title2id = {}
    for pid, pg in pages.items():
        if pid == "-1" or "missing" in pg:
            continue
        title2id[pg["title"]] = pid
    norm = {}
    for key in ("normalized", "redirects"):
        for n in d.get("query", {}).get(key, []):
            norm[n["from"]] = n["to"]
    for c in group:
        hit = None
        for t in cands_for(c):
            cur_t, hops = t, 0
            while cur_t in norm and hops < 5:
                cur_t = norm[cur_t]
                hops += 1
            if cur_t in title2id:
                hit = {"zh_title": cur_t, "pageid": title2id[cur_t]}
                break
        if hit:
            prog[c] = hit
    json.dump(prog, open(PROG, "w"), ensure_ascii=False, indent=1)
    print(f"[{gi+1}/{len(groups)}] resolved={len(prog)}/{len(cities)}", flush=True)

# --- step 2: langlinks for resolved ---
with_ll = [c for c in prog if "ll" not in prog[c]]
print(f"langlink fetch: {len(with_ll)}", flush=True)
B = 20
for i in range(0, len(with_ll), B):
    batch = with_ll[i:i+B]
    ids = "|".join(str(prog[c]["pageid"]) for c in batch)
    try:
        d = api({"action": "query", "pageids": ids, "prop": "langlinks",
                 "lllimit": "500", "format": "json"})
    except Exception as e:
        print("ll fail", e, flush=True)
        continue
    pages = d.get("query", {}).get("pages", {})
    id2ll = {}
    for pid, pg in pages.items():
        id2ll[pid] = {ll["lang"]: ll["*"] for ll in pg.get("langlinks", [])}
    for c in batch:
        ll = id2ll.get(str(prog[c]["pageid"]), {})
        prog[c]["ll"] = {L: ll.get(l, "") for L, l in LANGMAP.items()}
    json.dump(prog, open(PROG, "w"), ensure_ascii=False, indent=1)
    print(f"[ll {i+B}/{len(with_ll)}]", flush=True)

# --- step 3: fetch article titles in target langs for missing langlinks ---
# (langlink title already IS the article title in that language)
have = sum(1 for c in prog if "ll" in prog[c])
print(f"done: {len(prog)}/{len(cities)} resolved, {have} with ll", flush=True)
for L in TARGETS:
    n = sum(1 for c in prog if prog[c].get("ll", {}).get(L))
    print(f"  {L}: {n}/{len(prog)}", flush=True)
