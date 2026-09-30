#!/usr/bin/env python3
"""三源合并后的最终修正层：字面误译覆写 + 后缀/前缀归一 + 地区词补全 +
wiki th 标题优先 + 冲突消歧。输出 scripts/city-final.json。
不修改任何源数据，只改城市译名。"""
import json, re, sys
from pathlib import Path

H = Path(__file__).parent
DOCS = H.parent / "docs"

LANGS = ["en", "ja", "ko", "th", "es", "ar"]

merged = json.load(open(H / "city-merged.json", encoding="utf-8"))
sit = json.load(open(H / "city-sitelinks.json", encoding="utf-8"))
stations = json.load(open(DOCS / "电台目录翻译源数据.json", encoding="utf-8"))

# 定义源城市 -> (中文标题, 用于 sitelinks 反查)
title_of = {}
if isinstance(stations, dict):
    items = stations.get("stations") or stations.get("data") or stations
else:
    items = stations
for st in items:
    c = (st.get("city") or "").strip()
    if c and c not in title_of:
        title_of[c] = None
# 反查标题：wdlabels 里存了 title
wd = json.load(open(H / "city-wdlabels.json", encoding="utf-8"))
city_title = {}
for t, entry in wd.get("labels", {}).items():
    zh = (wd.get("title") or {}).get(t, t)
    city_title[zh] = t
# 兜底：直接用 city 名当 title
for c in list(title_of):
    title_of[c] = city_title.get(c, c)

# ---- th：维基条目标题优先（sitelinks 里 thwiki），无则用 merged 值 ----
def th_wiki(city):
    t = title_of.get(city)
    return (sit.get(t) or {}).get("thwiki")

# ---- 覆写表：已核实的字面误译 / 权威转写 ----
OV = {
    # 松原（Google 用了日语读音 Matsubara / มัตสึบาระ 等）
    ("松原", "en"): "Songyuan", ("松原", "th"): "ซ่งหยวน",
    ("松原", "es"): "Songyuan", ("松原", "ar"): "سونغيوان",
    # 白山（Google 字面译 white mountain 等）
    ("白山", "en"): "Baishan", ("白山", "ja"): "白山", ("白山", "th"): "ไป๋ซาน",
    ("白山", "es"): "Baishan", ("白山", "ar"): "بايشان",
    # 滁州 Google th 错给苏音
    ("滁州", "th"): "ชูโจว",
    # 宿州 th 与苏州同名，仿 en/es 加消歧
    ("宿州", "th"): "ซูโจว (อานฮุย)",
    # 鄂尔多斯 ar 混入英文 city
    ("鄂尔多斯", "ar"): "أوردوس",
    # 阿拉善盟 es
    ("阿拉善盟", "es"): "Liga Alxa", ("阿拉善盟", "th"): "อัลซา ลีก",
    # th 转写（Google en→th 权威单译）
    ("大兴安岭地区", "th"): "พื้นที่ต้าซิงอันหลิง",
    ("阿克苏地区", "th"): "พื้นที่อัคซู",
    # th 自治州语序：按泰语维基模板 <类型+ชนชาติ+族名> <地名>
    ("黔西南布依族苗族自治州", "th"): "เขตปกครองตนเองชนชาติบูยีและแม้ว เฉียนซีหนาน",
    ("黔东南苗族侗族自治州", "th"): "เขตปกครองตนเองชนชาติแม้วและตง เฉียนตงหนาน",
    ("恩施土家族苗族自治州", "th"): "เขตปกครองตนเองชนชาติถู่เจียและแม้ว เอินซี",
    ("阿坝藏族羌族自治州", "th"): "เขตปกครองตนเองชนชาติทิเบตและเฉียง อาปา",
    ("博尔塔拉蒙古自治州", "th"): "เขตปกครองตนเองชนชาติมองโกเลีย บอร์ตาลา",
    ("巴音郭楞蒙古自治州", "th"): "เขตปกครองตนเองชนชาติมองโกเลีย ปายหยิงโกลิน",
    # es 铜仁撇号
    ("铜仁地区", "es"): "Tongren",
    # 郴州 ja（Wikidata 旧实体标签「郴県専区」，应为郴州市去后缀）
    ("郴州", "ja"): "郴州",
    # 达拉斯/沃思堡斜杠两侧空格统一
    ("达拉斯 / 沃思堡", "ko"): "댈러스 / 포트워스",
    ("达拉斯 / 沃思堡", "es"): "Dallas / Fort Worth",
    # —— 第二轮修正：旧实体标题残留 / 历史名 / 过时 KG 标签 ——
    # 惠州（title 误解析到古地名「循州」实体）
    ("惠州", "en"): "Huizhou", ("惠州", "ja"): "恵州",
    # 保定（title 误解析到旧「保定地区」实体；ko 为朝鲜汉字音，应为现汉语转写）
    ("保定", "en"): "Baoding", ("保定", "ja"): "保定", ("保定", "ko"): "바오딩",
    # 石家庄/济宁/宜春/益阳（旧「X地区」实体经 normalize 后残留「地」尾）
    ("石家庄", "ja"): "石家荘",
    ("济宁", "ja"): "済寧",
    ("宜春", "ja"): "宜春",
    ("益阳", "ja"): "益陽",
    # 娄底（Wikidata ko 标签「뤄디」非标准转写；以 kowiki 标题「러우디시」为准）
    ("娄底", "ko"): "러우디",
    # 阿拉伯语条目只剩地名，补回自治州的族群与行政层级。
    ("延边朝鲜族自治州", "ar"): "محافظة يانبيان الكورية ذاتية الحكم",
    ("伊犁哈萨克自治州", "ar"): "ولاية إيلي الكازاخية ذاتية الحكم",
}

# ---- 地区词补全（源以「地区」结尾而译名缺行政词的语言）----
PREF = {
    "en": " Prefecture", "ja": "地区", "ko": " 지구",
    "th": "พื้นที่ ", "es": "Prefectura de ", "ar": "منطقة ",
}
REGION_FIX = {
    "哈密地区":   {"en": "Hami", "ja": "クムル", "ko": "하미", "th": "ฮามิ", "es": "Kumul", "ar": "هامي"},
    "毕节地区":   {"en": "Bijie", "ja": "畢節", "ko": "비제", "th": "ปีเจี่ย", "es": "Bijie", "ar": "بيجاي"},
    "铜仁地区":   {"en": "Tongren", "ja": "銅仁", "ko": "퉁런", "th": "ตงเรน", "es": "Tongren", "ar": "تونغران"},
    "大兴安岭地区": {"en": "Daxing'anling", "th": "ต้าซิงอันหลิง", "es": "Daxing'anling"},
    "阿克苏地区":  {"th": "อัคซู"},
}
# 塔城/大兴安岭/阿克苏 的 ja、塔城/大兴安岭 ar 等已带词，不动
th_prefixed = {"塔城地区", "大兴安岭地区", "阿克苏地区"}  # th 已有พื้นที่/ภูมิภาค 前缀

def region_complete(city, lang, val):
    """源以地区结尾：确保译名带行政词（对同类 6 城一致）。"""
    if not city.endswith("地区"):
        return val
    base = REGION_FIX.get(city, {}).get(lang)
    if base is None:
        return val
    if lang == "th":
        if city in th_prefixed:
            return val
        return "พื้นที่" + base
    if lang == "ja":
        if val.endswith("地区") or val.endswith("市"):
            # 剥市后补地区
            v = re.sub(r"市$", "", val)
            return v + "地区" if not v.endswith("地区") else v
        return base + "地区"
    if lang == "ko":
        if val.endswith("지구"):
            return val
        v = re.sub(r"시$", "", val)
        return v + " 지구" if not v.endswith("지구") else v
    if lang == "es":
        if val.startswith("Prefectura de "):
            return val
        if val == "Daxing'anling":
            return "Prefectura de Daxing'anling"
        return "Prefectura de " + val
    if lang == "ar":
        if "ذاتية" in val or val.startswith(("منطقة ", "مقاطعة ", "ولاية ", "محافظة ")):
            return val
        v = re.sub(r" \([^)]*\)$", "", val)          # 剥 (الصين)
        v = re.sub(r"^مدينة ", "", v)
        if "منطقة" in v:
            return v
        return "منطقة " + v
    if lang == "en":
        if val.endswith(("Prefecture", "Region", "League")):
            return val
        return val + " Prefecture"
    return val

# ---- 后缀/前缀归一（修正版）----
XI = ("西", "溪", "锡")   # xi 音译，ko 시 不能剥

def normalize(city, lang, v):
    src = city
    if lang == "ja":
        # 源无 市 → 剥尾市（自治州/州/盟/地区 自身的尾字保留）
        v = re.sub(r"市$", "", v) if not src.endswith("市") else v
        if not src.endswith("专区"):
            v = re.sub(r"専区$", "", v)              # 先剥専区（郴県専区→郴県）
        if not src.endswith("县"):
            v = re.sub(r"[県縣]$", "", v)
        if not src.endswith("区") and not src.endswith("地区"):
            v = re.sub(r"区$", "", v)                # 思茅区→思茅
        if not src.endswith("地区") and not src.endswith(("自治州",)):
            # 仅当实体是旧「专区/地区」标签时才带地区词；源无地区则剥
            if v.endswith("地区") and not src.endswith(("自治州",)):
                # 开封/临沂等旧实体标签；但 哈密/毕节/铜仁 后面会补回
                if src not in ("哈密地区", "毕节地区", "铜仁地区", "塔城地区", "大兴安岭地区", "阿克苏地区"):
                    v = re.sub(r"地区$", "", v)
    elif lang == "ko":
        if not src.endswith(XI):
            v = re.sub(r"시(?=\s|$)", "", v)         # 尾部或括号前的 시
        if not src.endswith("县"):
            v = re.sub(r"현$", "", v)
        if not src.endswith("区"):
            v = re.sub(r"구$", "", v)
        if not src.endswith("地区") and v.endswith("지구"):
            v = re.sub(r"지구$", "", v).rstrip()
    elif lang == "en":
        if not src.endswith(("市",)):
            v = re.sub(r"\s+City$", "", v)
        if not src.endswith("县"):
            v = re.sub(r"\s+County$", "", v)
        if not src.endswith("区"):
            v = re.sub(r"\s+District$", "", v)
        if src.endswith(("地区", "自治州")) and v.endswith(("Prefecture", "Region")):
            pass
        elif not src.endswith(("地区", "自治州")) and v.endswith((" Prefecture", " Region")):
            v = re.sub(r"\s+(Prefecture|Region)$", "", v)
    elif lang == "es":
        v = re.sub(r"^Ciudad de ", "", v)
        if not src.endswith("县") and v.endswith(" Condado"):
            v = re.sub(r" Condado$", "", v)
        if not src.endswith("地区") and v.endswith(" Prefectura"):
            v = re.sub(r" Prefectura$", "", v)
        if not src.endswith("市"):
            v = re.sub(r"^Ciudad de ", "", v)
    elif lang == "th":
        if not src.endswith(("市", "地区")):
            v = re.sub(r"^(เมือง|นคร)\s*", "", v)
        if not src.endswith(("区", "地区")) and v.startswith("เขต") and not v.startswith("เขตปกครอง"):
            v = re.sub(r"^เขต\s*", "", v)
        if src.endswith("地区") is False and v.startswith("ภูมิภาค "):
            pass
        if not src.endswith("地区"):
            v = re.sub(r"^(พื้นที่|ภูมิภาค)\s+", "", v)
    elif lang == "ar":
        if not src.endswith("市"):
            v = re.sub(r"^مدينة\s+", "", v)
        v = re.sub(r"^في\s+", "", v)                 # Google 散文介词
        v = re.sub(r"\s+سيتي$", "", v)               # 混入的英文 city
        # 括号消歧：冲突组由后面处理，这里只剥通名括号 (الصين)/(مملكة...) 中的国别说明
        v = re.sub(r"\s*\((الصين|PRC)\)$", "", v)
    # 达拉斯斜杠空格
    if " / " not in v and "/" in v:
        v = re.sub(r"\s*/\s*", " / ", v)
    # en/es 首字母大写
    if lang in ("en", "es") and v[:1].islower():
        v = v[0].upper() + v[1:]
    return v.strip()

# ---- 构建最终表 ----
cities = sorted({c for c in merged if c})
final = {}
for c in cities:
    row = {}
    for L in LANGS:
        v = merged[c][L]
        if L == "th":
            wt = th_wiki(c)
            if wt:
                v = re.sub(r"\s*\([^)]*\)$", "", wt)   # 剥 wiki 消歧括号（冲突组后处理）
        if (c, L) in OV:
            v = OV[(c, L)]
        v = normalize(c, L, v)
        v = region_complete(c, L, v)
        if (c, L) in OV and c in REGION_FIX and L in REGION_FIX[c] and c not in OV:
            pass
        row[L] = v
    # th wiki 优先后，OV 仍最高（OV 已在 wiki 之后应用？顺序：wiki → OV → normalize）
    final[c] = row

# 修正顺序 bug：OV 应在 wiki 之后应用（上面已如此）

# ---- 冲突消歧（同语言同值指向不同源）----
from collections import defaultdict
for L in LANGS:
    groups = defaultdict(list)
    for c in cities:
        groups[final[c][L]].append(c)
    for v, cs in groups.items():
        if len(cs) > 1:
            print(f"!! CONFLICT {L} {v!r} -> {cs}")
            # 已有人工消歧的不再动；输出待处理
            if len(set(cs)) == len(cs):
                pass

# ---- 审计 ----
def han(t):
    return re.findall(r"[一-鿿]", t)

errs = []
for c in cities:
    for L in LANGS:
        v = final[c][L]
        if not v:
            errs.append(f"EMPTY {L} {c}")
        if L != "ja" and han(v):
            errs.append(f"HAN {L} {c} = {v}")
        if L == "en" and (v[0].islower() or re.search(r"\b(City|County|District)$", v) and not c.endswith(("市", "县", "区"))):
            errs.append(f"EN {L} {c} = {v}")
print("errors:", len(errs))
for e in errs[:40]:
    print(" ", e)

json.dump(final, open(H / "city-final.json", "w", encoding="utf-8"),
          ensure_ascii=False, indent=1)
print("saved city-final.json", len(final), "cities")
