#!/usr/bin/env python3
"""第二轮翻译修正（定向修补，不重新生成整个文件）。

修正 docs/电台目录翻译.json 与 docs/电台目录翻译源数据.json 中的问题项：
  A. 电视伴音台名：品牌与本地化描述之间补空格（38 台 × 6 语言）；CETV-1..4 恢复连字符；es sonido→audio
  B. 电视伴音别名：CCTV-13 新闻(伴音) / CCTV-少儿伴音 / CCTV农业节目伴音 / CCTV-6 电影频道伴音 全量本地化
  C. HLS 线路别名：GOXUAN / MELODY / MY FM 的 (HLS 线路) 按目标语言翻译
  D. REPLAY NEWS 台名残留「每5分钟播报一次新闻的电台」本地化
  E. 阿拉伯语：language 字段 المندارينية→الماندارينية；Fred Film Radio 名称拼写
  F. 空格：211a49f3d6e0（双空格→单空格）、8f42c95b82cb（去尾空格），源数据与六语名称同步

约束：schemaVersion 不变；ID 集合不变；字段结构不变；aliases 数量与顺序不变；
UTF-8、indent=2、结尾换行。每个替换先校验旧值符合预期，任何不符即中止（防误改）。
"""
import json
import sys
from pathlib import Path

H = Path(__file__).parent
DOCS = H.parent / "docs"
OUT = DOCS / "电台目录翻译.json"
SRC = DOCS / "电台目录翻译源数据.json"
LANGS = ["en", "ja", "ko", "th", "es", "ar"]

doc = json.load(open(OUT, encoding="utf-8"))
src = json.load(open(SRC, encoding="utf-8"))

failures = []


def setname(sid, lang, old, new):
    cur = doc["translations"][lang][sid]["name"]
    if cur == new:
        return False  # 已修正，跳过（幂等）
    if cur != old:
        failures.append(f"NAME {lang} {sid}: expected {old!r}, found {cur!r}")
        return False
    doc["translations"][lang][sid]["name"] = new
    return True


def setalias(sid, lang, idx, old, new):
    cur = doc["translations"][lang][sid]["aliases"][idx]
    if cur == new:
        return False  # 已修正，跳过（幂等）
    if cur != old:
        failures.append(f"ALIAS {lang} {sid}[{idx}]: expected {old!r}, found {cur!r}")
        return False
    doc["translations"][lang][sid]["aliases"][idx] = new
    return True


# ---------- A. 电视伴音台名：品牌 + 空格 + 本地化描述 ----------
OLD_DESC = {"en": "audio", "ja": "音声", "ko": "오디오", "th": "เสียง", "es": "sonido", "ar": "الصوت"}
NEW_DESC = {"en": "audio", "ja": "音声", "ko": "오디오", "th": "เสียง", "es": "audio", "ar": "الصوت"}

SIMPLE = {
    "847b7506f3d7": "东方卫视",
    "c4172a248bfa": "云南卫视",
    "815cab6c569c": "内蒙古卫视",
    "b2c7200f6bed": "BTV文艺",
    "c9ca59df11e0": "BTV生活",
    "d592e9139bd8": "北京卫视",
    "6a55f38269af": "吉林卫视",
    "9a4b72e024c3": "四川卫视",
    "203537aa6d7d": "天津卫视",
    "2dfaa5fb5e98": "CCTV奥林匹克",
    "0f5e929e043b": "宁夏卫视",
    "33bc373b830d": "安徽卫视",
    "f120c6eeb38a": "山东卫视",
    "e7a89dd2fc8d": "山西卫视",
    "654589018677": "广东卫视",
    "0e3567e60921": "广西卫视",
    "b6b2bf8ecd06": "新疆卫视",
    "a0640d569c10": "江西卫视",
    "1f08e60399b1": "河北卫视",
    "1ff6995a78e7": "河南卫视",
    "85d5fda7ee21": "海南卫视",
    "52c11d53cf60": "湖北卫视",
    "ec18c86c24c5": "甘肃卫视",
    "4d848b6062dd": "福建东南卫视",
    "2242e3494aca": "西藏卫视",
    "1ffb1a5e4cca": "贵州卫视",
    "53fe7b0b706a": "辽宁卫视",
    "b27dceb08d88": "重庆卫视",
    "b164c10a98b2": "陕西卫视",
    "19853bf6fa32": "青海卫视",
    "58679c104512": "黑龙江卫视",
}

# CETV 台：当前值连字符已丢失（'CETV1audio'），修复为 'CETV-1 audio'
CETV = {
    "7f81d130839e": "1",
    "e730c41af132": "2",
    "03a53b91b11e": "3",
    "9ee1b4f9feb2": "4",
}

# 描述已翻译但缺分隔符的 3 台（品牌, {lang: (旧描述, 新描述)}）
CUSTOM = {
    "7326d62a17d3": (
        "BTV",
        {
            "en": ("science education audio", "science education audio"),
            "ja": ("科学教育音声", "科学教育音声"),
            "ko": ("과학교육 오디오", "과학교육 오디오"),
            "th": ("เสียงการศึกษาวิทยาศาสตร์", "เสียงการศึกษาวิทยาศาสตร์"),
            "es": ("audio de educación científica", "audio de educación científica"),
            "ar": ("صوت التعليم العلمي", "صوت التعليم العلمي"),
        },
    ),
    "ca8abb276ab2": (
        "BTV",
        {
            "en": ("finance audio", "finance audio"),
            "ja": ("財経音声", "財経音声"),
            "ko": ("금융 오디오", "금융 오디오"),
            "th": ("เสียงการเงิน", "เสียงการเงิน"),
            "es": ("audio de finanzas", "audio de finanzas"),
            "ar": ("صوت المالية", "صوت المالية"),
        },
    ),
    "f4a03ea4f001": (
        "北京BTV",
        {
            "en": ("news audio", "news audio"),
            "ja": ("ニュース音声", "ニュース音声"),
            "ko": ("뉴스 오디오", "뉴스 오디오"),
            "th": ("เสียงข่าว", "เสียงข่าว"),
            "es": ("news sonido", "news audio"),
            "ar": ("صوت الأخبار", "صوت الأخبار"),
        },
    ),
}

nA = 0
for sid, brand in SIMPLE.items():
    for lang in LANGS:
        if setname(sid, lang, brand + OLD_DESC[lang], brand + " " + NEW_DESC[lang]):
            nA += 1
for sid, num in CETV.items():
    for lang in LANGS:
        if setname(sid, lang, "CETV" + num + OLD_DESC[lang], "CETV-" + num + " " + NEW_DESC[lang]):
            nA += 1
for sid, (brand, descs) in CUSTOM.items():
    for lang in LANGS:
        old_desc, new_desc = descs[lang]
        if setname(sid, lang, brand + old_desc, brand + " " + new_desc):
            nA += 1

# ---------- B/C. 别名修正 ----------
ALIASES = [
    # CCTV-13 新闻(伴音)
    ("06ccacfeb6d4", 0, "en", "CCTV-13 新闻(audio)", "CCTV-13 news (audio)"),
    ("06ccacfeb6d4", 0, "ja", "CCTV-13 新闻(音声)", "CCTV-13 ニュース(音声)"),
    ("06ccacfeb6d4", 0, "ko", "CCTV-13 新闻(오디오)", "CCTV-13 뉴스(오디오)"),
    ("06ccacfeb6d4", 0, "th", "CCTV-13 新闻(เสียง)", "CCTV-13 ข่าว(เสียง)"),
    ("06ccacfeb6d4", 0, "es", "CCTV-13 新闻(audio)", "CCTV-13 noticias (audio)"),
    ("06ccacfeb6d4", 0, "ar", "CCTV-13 新闻(الصوت)", "CCTV-13 الأخبار (صوت)"),
    # CCTV-少儿伴音
    ("a8279c1f1723", 0, "en", "CCTV少儿audio", "CCTV children audio"),
    ("a8279c1f1723", 0, "ja", "CCTV少儿音声", "CCTV 子供向け音声"),
    ("a8279c1f1723", 0, "ko", "CCTV少儿오디오", "CCTV 어린이 오디오"),
    ("a8279c1f1723", 0, "th", "CCTV少儿เสียง", "CCTV เสียงเด็ก"),
    ("a8279c1f1723", 0, "es", "CCTV少儿audio", "CCTV audio infantil"),
    ("a8279c1f1723", 0, "ar", "CCTV少儿الصوت", "CCTV صوت الأطفال"),
    # CCTV农业节目伴音
    ("1b9945ae07db", 0, "en", "CCTV农业节目audio", "CCTV agriculture program audio"),
    ("1b9945ae07db", 0, "ja", "CCTV农业节目音声", "CCTV 農業番組音声"),
    ("1b9945ae07db", 0, "ko", "CCTV农业节目오디오", "CCTV 농업 프로그램 오디오"),
    ("1b9945ae07db", 0, "th", "CCTV农业节目เสียง", "CCTV เสียงรายการเกษตร"),
    ("1b9945ae07db", 0, "es", "CCTV农业节目audio", "CCTV audio de programas agrícolas"),
    ("1b9945ae07db", 0, "ar", "CCTV农业节目الصوت", "CCTV صوت البرامج الزراعية"),
    # CCTV-6 电影频道伴音
    ("95ad17c15442", 0, "en", "CCTV-6 电影频道伴音", "CCTV-6 movie channel audio"),
    ("95ad17c15442", 0, "ja", "CCTV-6 电影频道伴音", "CCTV-6 映画チャンネル音声"),
    ("95ad17c15442", 0, "ko", "CCTV-6 电影频道伴音", "CCTV-6 영화 채널 오디오"),
    ("95ad17c15442", 0, "th", "CCTV-6 电影频道伴音", "CCTV-6 เสียงช่องภาพยนตร์"),
    ("95ad17c15442", 0, "es", "CCTV-6 电影频道伴音", "CCTV-6 audio del canal de cine"),
    ("95ad17c15442", 0, "ar", "CCTV-6 电影频道伴音", "CCTV-6 صوت قناة الأفلام"),
    # GOXUAN(HLS 线路)
    ("168455c58404", 0, "en", "GOXUAN(HLS 线路)", "GOXUAN(HLS stream)"),
    ("168455c58404", 0, "ja", "GOXUAN(HLS 线路)", "GOXUAN(HLS 回線)"),
    ("168455c58404", 0, "ko", "GOXUAN(HLS 线路)", "GOXUAN(HLS 회선)"),
    ("168455c58404", 0, "th", "GOXUAN(HLS 线路)", "GOXUAN(สาย HLS)"),
    ("168455c58404", 0, "es", "GOXUAN(HLS 线路)", "GOXUAN(línea HLS)"),
    ("168455c58404", 0, "ar", "GOXUAN(HLS 线路)", "GOXUAN(خط HLS)"),
    # MELODY(HLS 线路)
    ("8cee95ff95b9", 0, "en", "MELODY(HLS 线路)", "MELODY(HLS stream)"),
    ("8cee95ff95b9", 0, "ja", "MELODY(HLS 线路)", "MELODY(HLS 回線)"),
    ("8cee95ff95b9", 0, "ko", "MELODY(HLS 线路)", "MELODY(HLS 회선)"),
    ("8cee95ff95b9", 0, "th", "MELODY(HLS 线路)", "MELODY(สาย HLS)"),
    ("8cee95ff95b9", 0, "es", "MELODY(HLS 线路)", "MELODY(línea HLS)"),
    ("8cee95ff95b9", 0, "ar", "MELODY(HLS 线路)", "MELODY(خط HLS)"),
    # MY FM(HLS 线路)
    ("ea9cede738b3", 0, "en", "MY FM(HLS 线路)", "MY FM(HLS stream)"),
    ("ea9cede738b3", 0, "ja", "MY FM(HLS 线路)", "MY FM(HLS 回線)"),
    ("ea9cede738b3", 0, "ko", "MY FM(HLS 线路)", "MY FM(HLS 회선)"),
    ("ea9cede738b3", 0, "th", "MY FM(HLS 线路)", "MY FM(สาย HLS)"),
    ("ea9cede738b3", 0, "es", "MY FM(HLS 线路)", "MY FM(línea HLS)"),
    ("ea9cede738b3", 0, "ar", "MY FM(HLS 线路)", "MY FM(خط HLS)"),
]
nBC = 0
for sid, idx, lang, old, new in ALIASES:
    if setalias(sid, lang, idx, old, new):
        nBC += 1

# ---------- D. REPLAY NEWS ----------
REPLAY = {
    "en": "REPLAY NEWS - Chinese news every 5 minutes",
    "ja": "REPLAY NEWS - 中国語 5分ごとにニュースを放送",
    "ko": "REPLAY NEWS - 중국어 5분마다 뉴스 방송",
    "th": "REPLAY NEWS - ภาษาจีน ข่าวทุก 5 นาที",
    "es": "REPLAY NEWS - Chino noticias cada 5 minutos",
    "ar": "REPLAY NEWS - صينية أخبار كل 5 دقائق",
}
REPLAY_LANG_WORD = {"en": "Chinese", "ja": "中国語", "ko": "중국어", "th": "ภาษาจีน", "es": "Chino", "ar": "صينية"}
nD = 0
for lang in LANGS:
    old = f"REPLAY NEWS - {REPLAY_LANG_WORD[lang]} 每5分钟播报一次新闻的电台"
    if setname("51676f9733c7", lang, old, REPLAY[lang]):
        nD += 1

# ---------- E. 阿拉伯语一致性 ----------
nE = 0
for sid, entry in doc["translations"]["ar"].items():
    if entry["language"] == "الصينية المندارينية":
        entry["language"] = "الصينية الماندارينية"
        nE += 1
    elif "المندارينية" in entry["language"] or "مندارين" in entry["language"]:
        failures.append(f"AR-LANG {sid}: unexpected {entry['language']!r}")
if setname("2c2764b99bbc", "ar", "Fred Film Radio - صينية مندارينية", "Fred Film Radio - صينية ماندارينية"):
    nE += 1
# 确认其余字段无残留旧拼写
for sid, entry in doc["translations"]["ar"].items():
    for fld, vals in (("name", [entry["name"]]), ("aliases", entry["aliases"]), ("group", [entry["group"]]),
                      ("category", [entry["category"]]), ("city", [entry["city"]])):
        for v in vals:
            if "مندارين" in v:
                failures.append(f"AR-RESIDUE {sid} {fld}: {v!r}")

# ---------- F. 空格修正（源数据 + 六语名称） ----------
nF = 0
for lang in LANGS:
    if setname("211a49f3d6e0", lang, "淄博私家车广播  FM106.7", "淄博私家车广播 FM106.7"):
        nF += 1
    if setname("8f42c95b82cb", lang, "台州新闻综合 ", "台州新闻综合"):
        nF += 1
for st in src["stations"]:
    if st["id"] == "211a49f3d6e0":
        if st["name"] == "淄博私家车广播 FM106.7":
            pass  # 已修正（幂等）
        elif st["name"] != "淄博私家车广播  FM106.7":
            failures.append(f"SRC 211a49f3d6e0: {st['name']!r}")
        else:
            st["name"] = "淄博私家车广播 FM106.7"
            nF += 1
    if st["id"] == "8f42c95b82cb":
        if st["name"] == "台州新闻综合":
            pass  # 已修正（幂等）
        elif st["name"] != "台州新闻综合 ":
            failures.append(f"SRC 8f42c95b82cb: {st['name']!r}")
        else:
            st["name"] = "台州新闻综合"
            nF += 1

if failures:
    print("FAILURES:")
    for f in failures:
        print("  ", f)
    sys.exit(1)

OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
SRC.write_text(json.dumps(src, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"names(A): {nA} | aliases(B+C): {nBC} | replay(D): {nD} | arabic(E): {nE} | spaces(F): {nF}")
print("written:", OUT.name, "|", SRC.name)
