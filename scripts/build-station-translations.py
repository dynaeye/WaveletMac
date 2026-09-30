#!/usr/bin/env python3
"""Build docs/电台目录翻译.json (en/ja/ko/th/es/ar) from docs/电台目录翻译源数据.json.

Strict v2 rules:
- id / region preserved as-is.
- name / aliases: keep brand/network/callsign/station names unchanged. Only translate
  pure descriptive fragments listed in TRANSLATE_SEGMENTS.
- Single-token (no whitespace): try INST_ENDINGS sub-string as station-name boundary
  (e.g. "广西卫视伴音" -> keep "广西卫视", translate "伴音"). Otherwise try trailing
  TRANSLATE_SEGMENTS suffix (e.g. "-英语", "高清").
- Multi-token: split on whitespace; for "name(token)" form, the entire parenthesized
  segment is one token, matched against TRANSLATE_SEGMENTS with or without brackets.
- language / group / category: human-curated full coverage.
- Translation via translate.googleapis.com (curl); cache + resume.
"""
import json
import os
import random
import re
import subprocess
import threading
import time
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(BASE, "docs", "电台目录翻译源数据.json")
OUT = os.path.join(BASE, "docs", "电台目录翻译.json")
CACHE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mt-cache.json")

TARGETS = ["en", "ja", "ko", "th", "es", "ar"]

CURATED = {"language": {}, "group": {}, "category": {}}

CURATED["language"] = {
    "华语": ("Mandarin", "中国語（華語）", "중국어", "ภาษาจีนกลาง", "Chino mandarín", "الصينية الماندارينية"),
    "普通话": ("Mandarin", "普通話", "중국어 표준어", "ภาษาจีนกลาง (ผูทงหัว)", "Mandarín", "الصينية المندارينية"),
    "中文/华语": ("Chinese / Mandarin", "中国語・華語", "중국어", "ภาษาจีน/ภาษาจีนกลาง", "Chino / Mandarín", "الصينية"),
    "英语": ("English", "英語", "영어", "ภาษาอังกฤษ", "Inglés", "الإنجليزية"),
    "蒙古语": ("Mongolian", "モンゴル語", "몽골어", "ภาษามองโกเลีย", "Mongol", "المنغولية"),
    "维吾尔语": ("Uyghur", "ウイグル語", "위구르어", "ภาษาอุยกูร์", "Uigur", "الأويغورية"),
    "粤语": ("Cantonese", "広東語", "광둥어", "ภาษากวางตุ้ง", "Cantonés", "الكانتونية"),
    "藏语": ("Tibetan", "チベット語", "티베트어", "ภาษาทิเบต", "Tibetano", "التبتية"),
    "哈萨克语": ("Kazakh", "カザフ語", "카자흐어", "ภาษาคาซัค", "Kazajo", "الكازاخية"),
    "多语种（依节目时段）": (
        "Multilingual (varies by timeslot)",
        "多言語（番組時間帯による）",
        "다언어(편성 시간대에 따라)",
        "หลายภาษา (ตามช่วงรายการ)",
        "Multilingüe (según la franja horaria)",
        "متعدد اللغات (حسب فترة البث)",
    ),
    "华语（社区收录）": (
        "Mandarin (community submission)",
        "中国語（コミュニティ提供）",
        "중국어(커뮤니티 수집)",
        "ภาษาจีนกลาง (รายการจากชุมชน)",
        "Mandarín (aportado por la comunidad)",
        "الصينية الماندارينية (إضافة مجتمعية)",
    ),
}

CURATED["category"] = {
    "综合": ("General", "総合", "종합", "ทั่วไป", "General", "عام"),
    "新闻资讯": ("News & Information", "ニュース・情報", "뉴스·정보", "ข่าวและสาระ", "Noticias e información", "أخبار ومعلومات"),
    "交通": ("Traffic", "交通", "교통", "จราจร", "Tráfico", "مرور"),
    "音乐": ("Music", "音楽", "음악", "เพลง", "Música", "موسيقى"),
    "财经": ("Finance", "金融・経済", "경제·금융", "การเงิน", "Finanzas y economía", "مالية واقتصاد"),
    "流行音乐": ("Pop Music", "ポップス", "팝음악", "ดนตรีป๊อป", "Música pop", "موسيقى البوب"),
    "地方电视伴音": ("Local TV Audio", "地上波テレビ音声", "지방 TV 오디오", "เสียงโทรทัศน์ท้องถิ่น", "Audio de TV local", "صوت التلفزيون المحلي"),
    "文艺戏曲": ("Arts & Opera", "文芸・演劇", "문예·전통극", "ศิลปะและงิ้ว", "Arte y ópera", "فنون وأوبرا"),
    "生活": ("Lifestyle", "ライフスタイル", "라이프스타일", "ไลฟ์สไตล์", "Estilo de vida", "نمط الحياة"),
    "央视伴音": ("CCTV Audio", "CCTV音声", "CCTV 오디오", "เสียง CCTV", "Audio de CCTV", "صوت CCTV"),
    "古典音乐": ("Classical Music", "クラシック音楽", "클래식 음악", "ดนตรีคลาสสิก", "Música clásica", "موسيقى كلاسيكية"),
    "宗教": ("Religion", "宗教", "종교", "ศาสนา", "Religión", "دين"),
    "教育少儿": ("Education & Children", "教育・子ども", "교육·어린이", "การศึกษาและเด็ก", "Educación e infantil", "تعليم وأطفال"),
    "乡村音乐": ("Country Music", "カントリーミュージック", "컨트리 음악", "ดนตรีคันทรี", "Música country", "موسيقى الريف"),
    "教育电视": ("Education TV", "教育テレビ", "교육 TV", "โทรทัศน์การศึกษา", "Televisión educativa", "التلفزيون التعليمي"),
    "体育": ("Sports", "スポーツ", "스포츠", "กีฬา", "Deportes", "رياضة"),
}

CURATED["group"] = {
    "上海": ("Shanghai", "上海", "상하이", "เซี่ยงไฮ้", "Shanghái", "شنغهاي"),
    "云南": ("Yunnan", "雲南", "윈난", "ยูนนาน", "Yunnán", "يونان"),
    "全台联播": ("Taiwan-wide Simulcast", "台湾全土ネット", "대만 전역 동시 방송", "เครือข่ายทั่วไต้หวัน", "Simulcast en toda Taiwán", "بث متزامن في جميع أنحاء تايوان"),
    "全国": ("Nationwide", "全国", "전국", "ทั่วประเทศ", "Nacional", "على مستوى البلاد"),
    "其他城市": ("Other Cities", "その他の都市", "기타 도시", "เมืองอื่นๆ", "Otras ciudades", "مدن أخرى"),
    "其他电台": ("Other Radio Stations", "その他のラジオ局", "기타 라디오", "สถานีวิทยุอื่น", "Otras emisoras", "محطات أخرى"),
    "其他电视": ("Other TV", "その他のテレビ", "기타 TV", "ทีวีอื่น", "Otras televisiones", "قنوات أخرى"),
    "内蒙古": ("Inner Mongolia", "内モンゴル", "네이멍구", "มองโกเลียภายใน", "Mongolia Interior", "منغوليا الداخلية"),
    "加拿大": ("Canada", "カナダ", "캐나다", "แคนาดา", "Canadá", "كندا"),
    "北京": ("Beijing", "北京", "베이징", "ปักกิ่ง", "Pekín", "بكين"),
    "华盛顿": ("Washington", "ワシントン", "워싱턴", "วอชิงตัน", "Washington", "واشنطن"),
    "南投": ("Nantou", "南投", "난투", "นันทู", "Nantou", "نانتو"),
    "台北": ("Taipei", "台北", "타이베이", "ไทเป", "Taipé", "تايبه"),
    "吉林": ("Jilin", "吉林", "지린", "จีหลิน", "Jilin", "جيلين"),
    "商业电台": ("Commercial Radio", "商業電台", "상업방송", "วิทยุพาณิชย์", "Radio comercial", "راديو تجاري"),
    "四川": ("Sichuan", "四川", "쓰촨", "เสฉวน", "Sichuán", "سيتشوان"),
    "基隆": ("Keelung", "基隆", "기룽", "คีหลง", "Keelung", "كيلونغ"),
    "夏洛特": ("Charlotte", "シャーロット", "샬럿", "ชาร์ลอตต์", "Charlotte", "شارلوت"),
    "天津": ("Tianjin", "天津", "톈진", "เทียนจิน", "Tianjin", "تيانجين"),
    "央视": ("CCTV", "CCTV", "CCTV", "CCTV", "CCTV", "CCTV"),
    "宁夏": ("Ningxia", "寧夏", "닝샤", "หนิงเซี่ย", "Ningxia", "نينغشيا"),
    "安徽": ("Anhui", "安徽", "안후이", "อานฮุย", "Anhui", "آنهاوي"),
    "山东": ("Shandong", "山東", "산둥", "ซานตง", "Shandong", "شاندونغ"),
    "山西": ("Shanxi", "山西", "산서", "ซานซี", "Shanxi", "شانشي"),
    "广东": ("Guangdong", "広東", "광둥", "กวางตุ้ง", "Guangdong", "قوانغدونغ"),
    "广西": ("Guangxi", "広西", "광시", "กว่างซี", "Guangxi", "قوانغشي"),
    "新加坡": ("Singapore", "シンガポール", "싱가포르", "สิงคโปร์", "Singapur", "سنغافورة"),
    "新城电台": ("Metro Broadcast", "新城電台", "메트로 방송", "เมโทรบรอดแคสต์", "Metro Broadcast", "ميترو برودكاست"),
    "新疆": ("Xinjiang", "新疆", "신장", "ซินเจียง", "Xinjiang", "شينجيانغ"),
    "新竹": ("Hsinchu", "新竹", "신주", "ซินจู", "Hsinchu", "هسينتشو"),
    "新西兰": ("New Zealand", "ニュージーランド", "뉴질랜드", "นิวซีแลนด์", "Nueva Zelanda", "نيوزيلندا"),
    "日本": ("Japan", "日本", "일본", "ญี่ปุ่น", "Japón", "اليابان"),
    "旧金山": ("San Francisco", "サンフランシスコ", "샌프란시스코", "ซานฟรานซิสโก", "San Francisco", "سان فرانسيسكو"),
    "未标注地区": ("Region Not Specified", "地域未設定", "지역 미표시", "ไม่ระบุภูมิภาค", "Región sin especificar", "منطقة غير محددة"),
    "未标注省市": ("Province/City Not Specified", "省市未設定", "성·시 미표시", "ไม่ระบุจังหวัด/เมือง", "Provincia/ciudad sin especificar", "محافظة/مدينة غير محددة"),
    "桃园": ("Taoyuan", "桃園", "타오위안", "เถาหยวน", "Taoyuan", "تاويوان"),
    "江苏": ("Jiangsu", "江蘇", "장쑤", "เจียงซู", "Jiangsu", "جيانغسو"),
    "江西": ("Jiangxi", "江西", "장시", "เจียงซี", "Jiangxi", "جيانغشي"),
    "河北": ("Hebei", "河北", "허베이", "เหอเป่ย์", "Hebei", "خبي"),
    "河南": ("Henan", "河南", "허난", "เหอนาน", "Henan", "خينان"),
    "法国": ("France", "フランス", "프랑스", "ฝรั่งเศส", "Francia", "فرنسا"),
    "波士顿": ("Boston", "ボストン", "보스턴", "บอสตัน", "Boston", "بوسطن"),
    "洛杉矶": ("Los Angeles", "ロサンゼルス", "로스앤젤레스", "ลอสแอนเจลิส", "Los Ángeles", "لوس أنجلوس"),
    "浙江": ("Zhejiang", "浙江", "저장", "เจ้อเจียง", "Zhejiang", "جيجيانغ"),
    "海南": ("Hainan", "海南", "하이난", "ไห่หนาน", "Hainan", "هاينان"),
    "湖北": ("Hubei", "湖北", "후베이", "หูเป่ย์", "Hubei", "خوبي"),
    "湖南": ("Hunan", "湖南", "후난", "หูหนาน", "Hunan", "خونان"),
    "澳大利亚": ("Australia", "オーストラリア", "오스트레일리아", "ออสเตรเลีย", "Australia", "أستراليا"),
    "澳门": ("Macau", "マカオ", "마카오", "มาเก๊า", "Macao", "ماكاو"),
    "甘肃": ("Gansu", "甘肅", "간쑤", "กานซู", "Gansu", "غانسو"),
    "福建": ("Fujian", "福建", "푸젠", "ฝูเจี้ยน", "Fujian", "فوجيان"),
    "纳什维尔": ("Nashville", "ナッシュビル", "내슈빌", "แนชวิลล์", "Nashville", "ناشفيل"),
    "纽约": ("New York", "ニューヨーク", "뉴욕", "นิวยอร์ก", "Nueva York", "نيويورك"),
    "芝加哥": ("Chicago", "シカゴ", "시카고", "ชิคาโก", "Chicago", "شيكاغو"),
    "苗栗": ("Miaoli", "苗栗", "머오리", "เหมียวหลี", "Miaoli", "ميالي"),
    "萨拉索塔": ("Sarasota", "サラソータ", "새러소타", "ซาราโซตา", "Sarasota", "ساراسوتا"),
    "西藏": ("Tibet", "チベット", "티베트", "ทิเบต", "Tíbet", "التبت"),
    "西雅图": ("Seattle", "シアトル", "시애틀", "ซีแอตเทิล", "Seattle", "سياتل"),
    "贵州": ("Guizhou", "貴州", "구이저우", "กุ้ยโจว", "Guizhou", "غويتشو"),
    "费城": ("Philadelphia", "フィラデルフィア", "필라델피아", "ฟิลาเดลเฟีย", "Filadelfia", "فيلادلفيا"),
    "辽宁": ("Liaoning", "遼寧", "랴오닝", "เหลียวหนิง", "Liaoning", "لياونينغ"),
    "达拉斯 / 沃思堡": ("Dallas / Fort Worth", "ダラス／フォートワース", "댈러스·포트워스", "ดัลลัส/ฟอร์ตเวิร์ธ", "Dallas / Fort Worth", "دالاس/فورت وورث"),
    "重庆": ("Chongqing", "重慶", "충칭", "ฉงชิง", "Chongqing", "تشونغتشينغ"),
    "陕西": ("Shaanxi", "陝西", "섬서", "ฉ่านซี", "Shaanxi", "شنشي"),
    "青海": ("Qinghai", "青海", "칭하이", "ชิงไห่", "Qinghai", "تشينغهاي"),
    "韩国": ("South Korea", "韓国", "한국", "เกาหลีใต้", "Corea del Sur", "كوريا الجنوبية"),
    "香港": ("Hong Kong", "香港", "홍콩", "ฮ่องกง", "Hong Kong", "هونغ كونغ"),
    "香港电台": ("RTHK", "RTHK", "RTHK", "RTHK", "RTHK", "RTHK"),
    "马来西亚": ("Malaysia", "マレーシア", "말레이시아", "มาเลเซีย", "Malasia", "ماليزيا"),
    "高雄": ("Kaohsiung", "高雄", "가오슝", "เกาสง", "Kaohsiung", "كاوسيونغ"),
    "黑龙江": ("Heilongjiang", "黒竜江", "헤이룽장", "เฮหลงเจียง", "Heilongjiang", "هيلونغجيانغ"),
}

INST_ENDINGS = (
    "广播电视台", "广播电台", "广播网", "广播电视",
    "電視台", "电视台", "衛視", "卫视",
    "之聲", "之声",
    "頻道", "频道",
    "電台", "电台",
    "廣播電台", "廣播電視台", "廣播網",
)

TRANSLATE_SEGMENTS = {
    "伴音": ("audio", "音声", "오디오", "เสียง", "audio", "الصوت"),
    "新闻伴音": ("news audio", "ニュース音声", "뉴스 오디오", "เสียงข่าว", "audio de noticias", "صوت الأخبار"),
    "新聞伴音": ("news audio", "ニュース音声", "뉴스 오디오", "เสียงข่าว", "audio de noticias", "صوت الأخبار"),
    "新闻(伴音)": ("news (audio)", "ニュース(音声)", "뉴스(오디오)", "(เสียง)ข่าว", "noticias (audio)", "الأخبار (صوت)"),
    "新聞(伴音)": ("news (audio)", "ニュース(音声)", "뉴스(오디오)", "(เสียง)ข่าว", "noticias (audio)", "الأخبار (صوت)"),
    "伴音)": ("audio)", "音声)", "오디오)", "เสียง)", "audio)", "الصوت)"),
    "(伴音)": ("(audio)", "(音声)", "(오디오)", "(เสียง)", "(audio)", "(الصوت)"),
    "(新闻伴音)": ("(news audio)", "(ニュース音声)", "(뉴스 오디오)", "(เสียงข่าว)", "(audio de noticias)", "(صوت الأخبار)"),
    "综合伴音": ("general audio", "総合音声", "종합 오디오", "เสียงทั่วไป", "audio general", "صوت عام"),
    "綜合伴音": ("general audio", "総合音声", "종합 오디오", "เสียงทั่วไป", "audio general", "صوت عام"),
    "体育伴音": ("sports audio", "スポーツ音声", "스포츠 오디오", "เสียงกีฬา", "audio de deportes", "صوت الرياضة"),
    "體育伴音": ("sports audio", "スポーツ音声", "스포츠 오디오", "เสียงกีฬา", "audio de deportes", "صوت الرياضة"),
    "电影伴音": ("movie audio", "映画音声", "영화 오디오", "เสียงภาพยนตร์", "audio de película", "صوت الفيلم"),
    "電影伴音": ("movie audio", "映画音声", "영화 오디오", "เสียงภาพยนตร์", "audio de película", "صوت الفيلم"),
    "纪录伴音": ("documentary audio", "ドキュメンタリー音声", "다큐 오디오", "เสียงสารคดี", "audio de documental", "صوت وثائقي"),
    "紀錄伴音": ("documentary audio", "ドキュメンタリー音声", "다큐 오디오", "เสียงสารคดี", "audio de documental", "صوت وثائقي"),
    "电视剧伴音": ("TV drama audio", "テレビドラマ音声", "TV 드라마 오디오", "เสียงละครโทรทัศน์", "audio de drama", "صوت المسلسل"),
    "電視劇伴音": ("TV drama audio", "テレビドラマ音声", "TV 드라마 오디오", "เสียงละครโทรทัศน์", "audio de drama", "صوت المسلسل"),
    "综艺伴音": ("variety audio", "バラエティ音声", "버라이어티 오디오", "เสียงรายการวาไรตี้", "audio de variedades", "صوت البرامج المتنوعة"),
    "綜藝伴音": ("variety audio", "バラエティ音声", "버라이어티 오디오", "เสียงรายการวาไรตี้", "audio de variedades", "صوت البرامج المتنوعة"),
    "音乐伴音": ("music audio", "音楽音声", "음악 오디오", "เสียงเพลง", "audio de música", "صوت الموسيقى"),
    "音樂伴音": ("music audio", "音楽音声", "음악 오디오", "เสียงเพลง", "audio de música", "صوت الموسيقى"),
    "科教伴音": ("science education audio", "科学教育音声", "과학교육 오디오", "เสียงการศึกษาวิทยาศาสตร์", "audio de educación científica", "صوت التعليم العلمي"),
    "财经伴音": ("finance audio", "財経音声", "금융 오디오", "เสียงการเงิน", "audio de finanzas", "صوت المالية"),
    "財經伴音": ("finance audio", "財経音声", "금융 오디오", "เสียงการเงิน", "audio de finanzas", "صوت المالية"),
    "戏曲伴音": ("opera audio", "戯曲音声", "전통극 오디오", "เสียงงิ้ว", "audio de ópera", "صوت الأوبرا"),
    "戲曲伴音": ("opera audio", "戯曲音声", "전통극 오디오", "เสียงงิ้ว", "audio de ópera", "صوت الأوبرا"),
    "少儿伴音": ("children audio", "子供向け音声", "어린이 오디오", "เสียงเด็ก", "audio infantil", "صوت الأطفال"),
    "少兒伴音": ("children audio", "子供向け音声", "어린이 오디오", "เสียงเด็ก", "audio infantil", "صوت الأطفال"),
    "社会与法伴音": ("society & law audio", "社会と法音声", "사회·법률 오디오", "เสียงสังคมและกฎหมาย", "audio de sociedad y derecho", "صوت المجتمع والقانون"),
    "社會與法伴音": ("society & law audio", "社会と法音声", "사회·법률 오디오", "เสียงสังคมและกฎหมาย", "audio de sociedad y derecho", "صوت المجتمع والقانون"),
    "国防军事伴音": ("defense & military audio", "国防軍事音声", "국방·군사 오디오", "เสียงกลาโหมและทหาร", "audio de defensa y militar", "صوت الدفاع والعسكري"),
    "國防軍事伴音": ("defense & military audio", "国防軍事音声", "국방·군사 오디오", "เสียงกลาโหมและทหาร", "audio de defensa y militar", "صوت الدفاع والعسكري"),
    "农业农村伴音": ("agriculture audio", "農業農村音声", "농업·농촌 오디오", "เสียงเกษตรและชนบท", "audio de agricultura", "صوت الزراعة"),
    "農業農村伴音": ("agriculture audio", "農業農村音声", "농업·농촌 오디오", "เสียงเกษตรและชนบท", "audio de agricultura", "صوت الزراعة"),
    "中文国际伴音": ("Chinese international audio", "中国語国際音声", "중국어 국제 오디오", "เสียงจีนนานาชาติ", "audio internacional chino", "صوت دولي بالصينية"),
    "中文國際伴音": ("Chinese international audio", "中国語国際音声", "중국어 국제 오디오", "เสียงจีนนานาชาติ", "audio internacional chino", "صوت دولي بالصينية"),
    "中文国际欧洲伴音": ("Chinese international Europe audio", "中国語国際欧州音声", "중국어 국제 유럽 오디오", "เสียงจีนยุโรป", "audio chino internacional Europa", "صوت دولي بالصينية أوروبا"),
    "中文國際歐洲伴音": ("Chinese international Europe audio", "中国語国際欧州音声", "중국어 국제 유럽 오디오", "เสียงจีนยุโรป", "audio chino internacional Europa", "صوت دولي بالصينية أوروبا"),
    "中文国际美洲伴音": ("Chinese international America audio", "中国語国際米州音声", "중국어 국제 아메리카 오디오", "เสียงจีนอเมริกา", "audio chino internacional América", "صوت دولي بالصينية أمريكا"),
    "中文國際美洲伴音": ("Chinese international America audio", "中国語国際米州音声", "중국어 국제 아메리카 오디오", "เสียงจีนอเมริกา", "audio chino internacional América", "صوت دولي بالصينية أمريكا"),
    "电影频道伴音": ("movie channel audio", "映画チャンネル音声", "영화 채널 오디오", "เสียงช่องภาพยนตร์", "audio del canal de cine", "صوت قناة الأفلام"),
    "電影頻道伴音": ("movie channel audio", "映画チャンネル音声", "영화 채널 오디오", "เสียงช่องภาพยนตร์", "audio del canal de cine", "صوت قناة الأفلام"),
    "+体育赛事伴音": ("+ sports event audio", "+ スポーツ中継音声", "+ 스포츠 이벤트 오디오", "+ เสียงการแข่งขันกีฬา", "+ audio de eventos deportivos", "+ صوت الفعاليات الرياضية"),
    "+體育赛事伴音": ("+ sports event audio", "+ スポーツ中継音声", "+ 스포츠 이벤트 오디오", "+ เสียงการแข่งขันกีฬา", "+ audio de eventos deportivos", "+ صوت الفعاليات الرياضية"),
    "高清": ("HD", "HD", "HD", "HD", "HD", "HD"),
    "標清": ("SD", "SD", "SD", "SD", "SD", "SD"),
    "标清": ("SD", "SD", "SD", "SD", "SD", "SD"),
    "粤语金曲": ("Cantonese hits", "広東語ヒット曲", "광둥어 히트곡", "เพลงฮิตกวางตุ้ง", "Éxitos cantoneses", "ضربات كانتونية"),
    "粵語金曲": ("Cantonese hits", "広東語ヒット曲", "광둥어 히트곡", "เพลงฮิตกวางตุ้ง", "Éxitos cantoneses", "ضربات كانتونية"),
    "中文": ("Chinese", "中国語", "중국어", "ภาษาจีน", "Chino", "صينية"),
    "华语": ("Mandarin", "中国語", "중국어", "ภาษาจีนกลาง", "Mandarín", "صينية"),
    "華語": ("Mandarin", "中国語", "중국어", "ภาษาจีนกลาง", "Mandarín", "صينية"),
    "粤语": ("Cantonese", "広東語", "광둥어", "ภาษากวางตุ้ง", "Cantonés", "كانتونية"),
    "粵語": ("Cantonese", "広東語", "광둥어", "ภาษากวางตุ้ง", "Cantonés", "كانتونية"),
    "普通话": ("Mandarin", "普通話", "중국어 표준어", "ภาษาจีนกลาง", "Mandarín", "صينية مندارينية"),
    "普通話": ("Mandarin", "普通話", "중국어 표준어", "ภาษาจีนกลาง", "Mandarín", "صينية مندارينية"),
    "朝鲜语": ("Korean", "朝鮮語", "조선어", "เกาหลี", "Coreano", "كورية"),
    "朝鮮語": ("Korean", "朝鮮語", "조선어", "เกาหลี", "Coreano", "كورية"),
    "（賀州廣播電視台綜合廣播）": ("(Hezhou R&TV integrated)", "(賀州ラジオテレビ総合放送)", "(허저우 라디오TV 종합)", "(สถานีวิทยุโทรทัศน์ Hezhou ครอบคลุม)", "(R&TV integral de Hezhou)", "(بث شامل Hezhou R&TV)"),
    "（贺州广播电视台综合广播）": ("(Hezhou R&TV integrated)", "(賀州ラジオテレビ総合放送)", "(허저우 라디오TV 종합)", "(สถานีวิทยุโทรทัศน์ Hezhou ครอบคลุม)", "(R&TV integral de Hezhou)", "(بث شامل Hezhou R&TV)"),
    "（宣化区融媒体中心综合广播）": ("(Xuanhua District converged-media center integrated)", "(宣化区融合メディアセンター総合放送)", "(선화화구 융합미디어센터 종합)", "(ศูนย์สื่อบูรณาการเขตซวนหวา ครอบคลุม)", "(centro de medios integrados Xuanhua)", "(مركز Xuanhua الإعلامي المتكامل)"),
    "（界首新闻综合广播）": ("(Jieshou news integrated)", "(界首ニュース総合放送)", "(제이저우 뉴스 종합)", "(ข่าวเจียซัว ครอบคลุม)", "(noticias Jieshou integral)", "(بث شامل لأخبار جيشو)"),
    "（股市广播）": ("(stock-market broadcast)", "(株式市場放送)", "(증권시장 방송)", "(ตลาดหุ้น)", "(difusión de bolsa)", "(بث سوق الأسهم)"),
    "（成功992）": ("(Success 992)", "(成功992)", "(성공 992)", "(สำเร็จ 992)", "(Éxito 992)", "(نجاح 992)"),
    "(故事广播)": ("(story broadcast)", "(ストーリー放送)", "(스토리 방송)", "(กระจายเสียงเรื่องราว)", "(difusión de historias)", "(بث القصص)"),
    "(一财官网线路)": ("(Yicai official-site stream)", "(第一財経公式サイト回線)", "(이차이 공식 사이트 회선)", "(สายเว็บทางการ Yicai)", "(línea sitio oficial Yicai)", "(خط الموقع الرسمي Yicai)"),
    "（一财官网线路）": ("(Yicai official-site stream)", "(第一財経公式サイト回線)", "(이차이 공식 사이트 회선)", "(สายเว็บทางการ Yicai)", "(línea sitio oficial Yicai)", "(خط الموقع الرسمي Yicai)"),
    "(官网直播)": ("(official-site live)", "(公式サイト生中継)", "(공식 사이트 생방송)", "(ถ่ายทอดสดเว็บทางการ)", "(transmisión oficial en vivo)", "(البث المباشر للموقع الرسمي)"),
    "（官网直播）": ("(official-site live)", "(公式サイト生中継)", "(공식 사이트 생방송)", "(ถ่ายทอดสดเว็บทางการ)", "(transmisión oficial en vivo)", "(البث المباشر للموقع الرسمي)"),
    "(微赞视频慢直播线路)": ("(Weizan slow-video live stream)", "(微賛映像スロー生中継回線)", "(웨이잔 영상 느린 생방송 회선)", "(สายถ่ายทอดสดแบบช้าของ Weizan)", "(línea video lento Weizan)", "(خط البث البطيء Weizan)"),
    "（微赞视频慢直播线路）": ("(Weizan slow-video live stream)", "(微賛映像スロー生中継回線)", "(웨이잔 영상 느린 생방송 회선)", "(สายถ่ายทอดสดแบบช้าของ Weizan)", "(línea video lento Weizan)", "(خط البث البطيء Weizan)"),
    "(备用线路)": ("(backup stream)", "(予備回線)", "(예비 회선)", "(สายสำรอง)", "(línea de respaldo)", "(خط احتياطي)"),
    "（备用线路）": ("(backup stream)", "(予備回線)", "(예비 회선)", "(สายสำรอง)", "(línea de respaldo)", "(خط احتياطي)"),
    "(视频)": ("(video)", "(映像)", "(영상)", "(วิดีโอ)", "(vídeo)", "(فيديو)"),
    "（视频）": ("(video)", "(映像)", "(영상)", "(วิดีโอ)", "(vídeo)", "(فيديو)"),
    "(周一至周五23:11)": ("(Mon–Fri 23:11)", "(月〜金 23:11)", "(월~금 23:11)", "(จันทร์-ศุกร์ 23:11)", "(Lun–Vie 23:11)", "(الإثنين-الجمعة 23:11)"),
    "（周一至周五23:11）": ("(Mon–Fri 23:11)", "(月〜金 23:11)", "(월~금 23:11)", "(จันทร์-ศุกร์ 23:11)", "(Lun–Vie 23:11)", "(الإثنين-الجمعة 23:11)"),
    "(广州)": ("(Guangzhou)", "(広州)", "(광저우)", "(กวางโจว)", "(Guangzhou)", "(قوانغتشو)"),
    "（广州）": ("(Guangzhou)", "(広州)", "(광저우)", "(กวางโจว)", "(Guangzhou)", "(قوانغتشو)"),
    "(中文)": ("(Chinese)", "(中国語)", "(중국어)", "(ภาษาจีน)", "(Chino)", "(صينية)"),
    "（中文）": ("(Chinese)", "(中国語)", "(중국어)", "(ภาษาจีน)", "(Chino)", "(صينية)"),
    "(粵語)": ("(Cantonese)", "(広東語)", "(광둥어)", "(กวางตุ้ง)", "(Cantonés)", "(كانتونية)"),
    "（粵語）": ("(Cantonese)", "(広東語)", "(광둥어)", "(กวางตุ้ง)", "(Cantonés)", "(كانتونية)"),
    "(朝鲜语)": ("(Korean)", "(朝鮮語)", "(조선어)", "(เกาหลี)", "(Coreano)", "(كورية)"),
    "（朝鲜语）": ("(Korean)", "(朝鮮語)", "(조선어)", "(เกาหลี)", "(Coreano)", "(كورية)"),
    "（朝鮮語）": ("(Korean)", "(朝鮮語)", "(조선어)", "(เกาหลี)", "(Coreano)", "(كورية)"),
    "老年频率": ("senior channel", "シニア周波数", "시니어 채널", "ช่องผู้สูงอายุ", "frecuencia senior", "تردد كبار السن"),
    "老年頻率": ("senior channel", "シニア周波数", "시니어 채널", "ช่องผู้สูงอายุ", "frecuencia senior", "تردد كبار السن"),
    "老歌听不够,经典永流传": ("Old songs never tire, classics echo forever", "古い歌は聞き飽きない、古典は永遠に語り継がれる", "옛 노래는 듣기에 부족하고, 명곡은 영원히 흐른다", "เพลงเก่าฟังไม่เบื่อ คลาสสิกก้องกังวาลตลอดกาล", "Las canciones antiguas no bastan, los clásicos perduran", "الأغاني القديمة لا تكفي، الكلاسيكيات أبدية"),
    "读本书吧《百岁人生》": ("Let's Read: 'The 100-Year Life'", "本を読もう『百歳の人生』", "책 읽자 '백세 인생'", "มาอ่านหนังสือกันเถอะ 'ชีวิตร้อยปี'", "Leamos: 'La vida de 100 años'", "لنقرأ «حياة المئة عام»"),
    "讀本書吧《百歲人生》": ("Let's Read: 'The 100-Year Life'", "本を読もう『百歳の人生』", "책 읽자 '백세 인생'", "มาอ่านหนังสือกันเถอะ 'ชีวิตร้อยปี'", "Leamos: 'La vida de 100 años'", "لنقرأ «حياة المئة عام»"),
    "每5分钟播报一次新闻的电台": ("news every 5 minutes", "5分ごとにニュースを放送", "5분마다 뉴스 방송", "ข่าวทุก 5 นาที", "noticias cada 5 minutos", "أخبار كل 5 دقائق"),
    "每5分鐘播報一次新聞的電台": ("news every 5 minutes", "5分ごとにニュースを放送", "5분마다 뉴스 방송", "ข่าวทุก 5 นาที", "noticias cada 5 minutos", "أخبار كل 5 دقائق"),
    "-英语": ("(English)", "(英語)", "(영어)", "(ภาษาอังกฤษ)", "(inglés)", "(إنجليزي)"),
    "-English": ("(English)", "(英語)", "(영어)", "(ภาษาอังกฤษ)", "(inglés)", "(إنجليزي)"),
    "城市": ("city", "都市", "도시", "เมือง", "ciudad", "مدينة"),
}

# 字符串清理用符号 (避免字符串中smart quote与ASCII quote混淆)
CLOSERS = ")" + chr(0xFF09) + chr(0x3011) + chr(0x300D) + chr(0x300F) + chr(0x3009) + chr(34) + chr(39) + chr(0x2019)
PAREN_OPEN = ("(", chr(0xFF08))

# 后缀可译片段 (用于单 token 切分): 仅当 token 以这些片段结尾才把尾部切出
TRAIL_SEGMENTS = sorted(
    [s for s in TRANSLATE_SEGMENTS.keys() if not (s.startswith("(") or s.startswith(chr(0xFF08)))],
    key=len, reverse=True,
)

# 分隔符: 空白 / 左括号
_SEP = re.compile(r"\s|[\(（]")


def is_institution(chunk):
    t = chunk.strip().rstrip(CLOSERS)
    if not t:
        return False
    return any(e in t for e in INST_ENDINGS)


def _lookup_translate(token):
    """返回 token 的翻译值, 不命中返回 None."""
    if token in TRANSLATE_SEGMENTS:
        return TRANSLATE_SEGMENTS[token]
    return None


def is_describable(text):
    raw = text.strip()
    if not raw:
        return False
    if is_institution(raw):
        return False
    # 1) 整段命中
    if _lookup_translate(raw):
        return True
    # 2) 剥尾收尾标点
    s = raw.rstrip(CLOSERS)
    if s and _lookup_translate(s):
        return True
    # 3) 括号包裹整段: 剥首括号, 整段可能带尾括号
    if len(raw) >= 2 and raw[0] in PAREN_OPEN:
        inner = raw[1:]
        if _lookup_translate(inner):
            return True
        if inner.endswith(")") or inner.endswith(chr(0xFF09)):
            inner2 = inner.rstrip(")" + chr(0xFF09))
            if _lookup_translate(inner2):
                return True
    return False


def _split_single_token(token):
    """单 token 切分: 先按 INST_ENDINGS, 再按 '-' / 等连接符切, 再按 TRAIL_SEGMENTS 后缀."""
    best_pos, best_len = -1, 0
    for e in INST_ENDINGS:
        idx = token.rfind(e)
        if idx >= 0 and (idx > best_pos or (idx == best_pos and len(e) > best_len)):
            best_pos, best_len = idx, len(e)
    if best_pos >= 0:
        head = token[: best_pos + best_len]
        tail = token[best_pos + best_len:]
        out = [(head, "keep")]
        if tail:
            out.append((tail, "describe" if is_describable(tail) else "keep"))
        return out
    # 在 token 内部的 '-' / '·' / ' ' 处尝试切 (e.g. "CCTV-少儿伴音")
    for sep in ("-", chr(0x00B7), " "):
        if sep in token:
            sub = _split_single_token(token[token.rfind(sep)+1:])
            if sub:
                head = token[:token.rfind(sep)]
                return [(head, "describe" if is_describable(head) else "keep")] + sub
    for seg in TRAIL_SEGMENTS:
        if token.endswith(seg) and len(token) > len(seg):
            head = token[: -len(seg)]
            return [(head, "describe" if is_describable(head) else "keep"),
                    (seg, "describe" if is_describable(seg) else "keep")]
    return None


def _flush(out, cur):
    if cur:
        out.append((cur, "describe" if is_describable(cur) else "keep"))
        cur = ""
    return cur


def split_by_delim(value):
    """切分为 [(text, kind)]: 单 token → _split_single_token; 多 token → 按空白切, 括号整段作为单 token."""
    if not value:
        return []
    if not _SEP.search(value):
        s = value.strip()
        sub = _split_single_token(s)
        if sub:
            return sub
        return [(value, "describe" if is_describable(value) else "keep")]
    out = []
    cur = ""
    i = 0
    while i < len(value):
        ch = value[i]
        if ch in (" ", "\t", "\n", chr(0x3000)):
            cur = _flush(out, cur)
            out.append((ch, "keep"))
            i += 1
        elif ch in PAREN_OPEN:
            cur = _flush(out, cur)
            target = ")" if ch == "(" else chr(0xFF09)
            j = i + 1
            while j < len(value) and value[j] != target:
                j += 1
            if j >= len(value):
                tok = value[i:]
                i = len(value)
            else:
                tok = value[i:j+1]
                i = j + 1
            out.append((tok, "describe" if is_describable(tok) else "keep"))
        else:
            cur += ch
            i += 1
    cur = _flush(out, cur)
    return [(t, k) for t, k in out if t]


_cache = {}
_cache_lock = threading.Lock()
_dirty = {"n": 0}


def load_cache():
    global _cache
    if os.path.exists(CACHE):
        with open(CACHE, encoding="utf-8") as f:
            _cache = json.load(f)


def save_cache(force=False):
    with _cache_lock:
        _dirty["n"] += 1
        if force or _dirty["n"] >= 30:
            tmp = CACHE + ".tmp"
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(_cache, f, ensure_ascii=False)
            os.replace(tmp, CACHE)
            _dirty["n"] = 0


class TranslateError(Exception):
    def __init__(self, msg, code=None):
        super().__init__(msg)
        self.code = code


def _gtranslate(text, sl, tl, timeout=25):
    url = (
        "https://translate.googleapis.com/translate_a/single?client=gtx"
        "&sl=%s&tl=%s&dt=t&q=%s" % (sl, tl, urllib.parse.quote(text, safe=""))
    )
    try:
        proc = subprocess.run(
            ["curl", "-sS", "--fail", "--max-time", str(timeout), url],
            capture_output=True, timeout=timeout + 10,
        )
    except subprocess.TimeoutExpired as exc:
        raise TranslateError("curl timeout") from exc
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace")[:200]
        m = re.search(r"returned error: (\d{3})", err)
        code = int(m.group(1)) if m else None
        raise TranslateError(f"curl exit {proc.returncode}: {err}", code)
    data = json.loads(proc.stdout.decode("utf-8"))
    return "".join(seg[0] for seg in data[0] if seg and seg[0])


def translate_many(texts, sl, tl, workers=4):
    todo = [t for t in texts if f"{tl}|{sl}|{t}" not in _cache]
    if not todo:
        return
    batches, buf, size = [], [], 0
    for t in sorted(todo, key=len, reverse=True):
        if size + len(t) + 1 > 700 or len(buf) >= 40:
            if buf:
                batches.append(buf)
            buf, size = [], 0
        buf.append(t)
        size += len(t) + 1
    if buf:
        batches.append(buf)
    failures = []
    lock = threading.Lock()

    def work(batch):
        joined = "\n".join(batch)
        for attempt in range(6):
            try:
                out = _gtranslate(joined, sl, tl)
                lines = out.split("\n")
                if len(lines) == len(batch):
                    with lock:
                        for src, dst in zip(batch, lines):
                            _cache[f"{tl}|{sl}|{src}"] = dst.strip()
                        save_cache()
                    return
                raise ValueError("line mismatch")
            except TranslateError as e:
                if e.code in (429, 403) or e.code is None or e.code >= 500:
                    time.sleep(min(30, 2 ** attempt) + random.random() * 2)
                    continue
                break
            except Exception:
                time.sleep(1 + attempt)
                continue
        with lock:
            failures.extend(batch)

    with ThreadPoolExecutor(max_workers=workers) as ex:
        list(ex.map(work, batches))

    for t in list(failures):
        for attempt in range(4):
            try:
                out = _gtranslate(t, sl, tl, timeout=15).strip()
                with _cache_lock:
                    _cache[f"{tl}|{sl}|{t}"] = out
                save_cache()
                break
            except Exception:
                time.sleep(2 + attempt * 2)
        else:
            with _cache_lock:
                _cache[f"{tl}|{sl}|{t}"] = t
            save_cache()
    save_cache(force=True)


def repair_echoed():
    fixed = 0
    for key in list(_cache.keys()):
        tl, sl, text = key.split("|", 2)
        if _cache[key] != text:
            continue
        if text not in TRANSLATE_SEGMENTS:
            continue
        candidates = ["auto"] if sl != "auto" else []
        done = False
        for alt in candidates:
            try:
                out = _gtranslate(text, alt, tl, timeout=15).strip()
            except Exception:
                out = ""
            if out and out != text:
                _cache[key] = out
                fixed += 1
                done = True
                break
        if done:
            continue
        try:
            mid = _gtranslate(text, sl if sl != "auto" else "auto", "en", timeout=15).strip()
            out = _gtranslate(mid, "en", tl, timeout=15).strip() if mid else ""
        except Exception:
            out = ""
        if out and out != text:
            _cache[key] = out
            fixed += 1
    if fixed:
        save_cache(force=True)
    print(f"echo-repair fixed: {fixed}", flush=True)


def _pick_token_value(text, ti):
    """从 text 中挑出首个可翻译 key 并返回替换文本; 否则 None."""
    raw = text.strip()
    if not raw:
        return None
    val = _lookup_translate(raw)
    if val: return val[ti]
    s = raw.rstrip(CLOSERS)
    if s and (val := _lookup_translate(s)):
        return val[ti]
    if len(raw) >= 2 and raw[0] in PAREN_OPEN:
        inner = raw[1:]
        if (val := _lookup_translate(inner)):
            return val[ti]
        if inner.endswith(")") or inner.endswith(chr(0xFF09)):
            inner2 = inner.rstrip(")" + chr(0xFF09))
            if (val := _lookup_translate(inner2)):
                return val[ti]
    return None


def translate_field(value, tl, ti, curated=None):
    if not value:
        return value
    if curated is not None and value in curated:
        return curated[value][ti]
    parts = split_by_delim(value)
    out = []
    for text, kind in parts:
        if kind == "keep":
            out.append(text)
            continue
        val = _pick_token_value(text, ti)
        if val is not None:
            # 替换第一个可翻译 key (按 _pick_token_value 的查找顺序)
            raw = text.strip()
            if val in TRANSLATE_SEGMENTS.get(raw, [None]*6) if raw in TRANSLATE_SEGMENTS else False:
                out.append(text.replace(raw, val, 1))
            elif raw.rstrip(CLOSERS) in TRANSLATE_SEGMENTS:
                s = raw.rstrip(CLOSERS)
                out.append(text.replace(s, val, 1))
            elif len(raw) >= 2 and raw[0] in PAREN_OPEN:
                inner = raw[1:]
                if inner in TRANSLATE_SEGMENTS:
                    out.append(text.replace(inner, val, 1))
                elif inner.endswith(")") or inner.endswith(chr(0xFF09)):
                    inner2 = inner.rstrip(")" + chr(0xFF09))
                    if inner2 in TRANSLATE_SEGMENTS:
                        out.append(text.replace(inner2, val, 1))
                    else:
                        out.append(text)
                else:
                    out.append(text)
            else:
                out.append(text)
        else:
            out.append(text)
    return "".join(out)


def main():
    with open(SRC, encoding="utf-8") as f:
        src = json.load(f)
    stations = src["stations"]
    load_cache()

    need = set()
    for st in stations:
        for f in ("name", "city"):
            for text, kind in split_by_delim(st[f]):
                if kind == "describe":
                    raw = text.strip()
                    if not raw: continue
                    if _pick_token_value(text, 0):  # any ti will do
                        # collect actual key for MT: prefer raw, else stripped
                        for candidate in [raw, raw.rstrip(CLOSERS), raw[1:] if raw[:1] in PAREN_OPEN else None]:
                            if candidate and candidate in TRANSLATE_SEGMENTS:
                                need.add(("zh-CN", candidate)); break
        for a in st["aliases"]:
            for text, kind in split_by_delim(a):
                if kind == "describe":
                    raw = text.strip()
                    if not raw: continue
                    if _pick_token_value(text, 0):
                        for candidate in [raw, raw.rstrip(CLOSERS), raw[1:] if raw[:1] in PAREN_OPEN else None]:
                                if candidate and candidate in TRANSLATE_SEGMENTS:
                                    need.add(("zh-CN", candidate)); break
    print(f"segments to translate: {len(need)}", flush=True)

    grouped = {}
    for sl, text in need:
        grouped.setdefault(sl, set()).add(text)
    for sl, texts in sorted(grouped.items()):
        print(f"  {len(texts):5d} segments  sl={sl:6s} -> all tl", flush=True)
        for tl in TARGETS:
            translate_many(sorted(texts), sl, tl)
    repair_echoed()

    out_data = {"schemaVersion": 1, "translations": {}}
    missing = {"language": set(), "group": set(), "category": set()}
    for ti, tl in enumerate(TARGETS):
        block = {}
        for st in stations:
            entry = {
                "name": translate_field(st["name"], tl, ti),
                "aliases": [translate_field(a, tl, ti) for a in st["aliases"]],
            }
            for field in ("language", "group", "category"):
                v = st[field]
                cmap = CURATED[field]
                if v in cmap:
                    entry[field] = cmap[v][ti]
                else:
                    missing[field].add(v)
                    entry[field] = translate_field(v, tl, ti)
            entry["city"] = translate_field(st["city"], tl, ti)
            block[st["id"]] = entry
        out_data["translations"][tl] = block
        print(f"built {tl}: {len(block)} stations", flush=True)

    for field, vals in missing.items():
        if vals:
            print(f"WARNING uncovered {field} (MT fallback): {sorted(vals)}", flush=True)

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out_data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("written:", OUT, flush=True)


if __name__ == "__main__":
    main()
