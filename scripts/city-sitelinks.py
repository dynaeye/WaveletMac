#!/usr/bin/env python3
"""Fetch Wikidata sitelinks (en/ja/ko/th/es/ar wiki article titles) for city entities, incremental."""
import json, subprocess, time, random, os

HERE = os.path.dirname(os.path.abspath(__file__))
IN = os.path.join(HERE, "city-wdlabels.json")
OUT = os.path.join(HERE, "city-sitelinks.json")
SITES = ["zhwiki", "enwiki", "jawiki", "kowiki", "thwiki", "eswiki", "arwiki"]

wd = json.load(open(IN))
titles = sorted(wd["labels"].keys())
state = json.load(open(OUT)) if os.path.exists(OUT) else {}
todo = [t for t in titles if t not in state]
print("todo titles:", len(todo), flush=True)


def api(params, tries=5):
    args = ["curl", "-sS", "--fail", "--max-time", "25", "-x", "http://127.0.0.1:7890",
            "-X", "POST", "https://www.wikidata.org/w/api.php"]
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


B = 15
for i in range(0, len(todo), B):
    batch = todo[i:i + B]
    try:
        d = api({"action": "wbgetentities", "sites": "zhwiki", "titles": "|".join(batch),
                 "props": "sitelinks|labels", "sitefilter": "|".join(SITES),
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
        state[zt] = {s: e["sitelinks"][s]["title"] for s in e.get("sitelinks", {})
                      if s != "zhwiki"}
    json.dump(state, open(OUT, "w"), ensure_ascii=False, indent=1)
    print(f"[{min(i + B, len(todo))}/{len(todo)}] saved={len(state)}", flush=True)
    time.sleep(0.3)

cov = {s: sum(1 for v in state.values() if s in v) for s in SITES}
print("coverage:", cov, flush=True)
