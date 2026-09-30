import SwiftUI
import CoreText
import OSLog

private enum Design {
    static let paper = Color(hex: 0xEDE7DA), card = Color(hex: 0xF8F4EB), forest = Color(hex: 0x2E3A2E)
    static let amber = Color(hex: 0xEAB96A), ink = Color(hex: 0x28281F), line = Color(hex: 0xDED6C6), muted = Color(hex: 0x918D80)
    static let fonts: [String: String] = {
        var names: [String: String] = [:]
        for file in ["NotoSansSC", "Inter", "Archivo", "SpaceMono"] {
            guard let url = Bundle.main.url(forResource: file, withExtension: "ttf", subdirectory: "Fonts") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], let descriptor = descriptors.first {
                names[file] = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String
            }
        }
        return names
    }()
    static func font(_ size: CGFloat, _ family: String = "NotoSansSC", _ weight: Font.Weight = .regular) -> Font {
        .custom(fonts[family] ?? family, size: size, relativeTo: .body).weight(weight)
    }
    static func translate(_ value: String, _ language: String) -> String {
        if language == "繁體中文" {
            return value.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? value
        }
        if language == "阿拉伯文" { return arabic[value] ?? value }
        guard let index = ["英文", "日文", "韩文", "泰文", "西班牙语"].firstIndex(of: language),
              let translations = localized[value], translations.indices.contains(index) else { return value }
        return translations[index]
    }
    static func systemLanguage(_ identifier: String = Locale.preferredLanguages.first ?? Locale.current.identifier) -> String {
        let normalized = identifier.lowercased().replacingOccurrences(of: "_", with: "-")
        if normalized.hasPrefix("zh") {
            let traditionalMarkers = ["hant", "-tw", "-hk", "-mo"]
            return traditionalMarkers.contains(where: normalized.contains) ? "繁體中文" : "简体中文"
        }
        if normalized.hasPrefix("ja") { return "日文" }
        if normalized.hasPrefix("ko") { return "韩文" }
        if normalized.hasPrefix("th") { return "泰文" }
        if normalized.hasPrefix("es") { return "西班牙语" }
        if normalized.hasPrefix("ar") { return "阿拉伯文" }
        return "英文"
    }
    static func resolvedLanguage(_ preference: String) -> String {
        preference == "跟随系统" ? systemLanguage() : preference
    }
    static let languageOptions = ["跟随系统", "繁體中文", "简体中文", "英文", "日文", "韩文", "泰文", "西班牙语", "阿拉伯文"]
    static func channelCount(_ count: Int, favorites: Bool = false, language: String) -> String {
        switch language {
        case "英文": return favorites ? "\(count) favorite stations" : "\(count) stations"
        case "日文": return favorites ? "お気に入りの局 \(count) 件" : "\(count) 局"
        case "韩文": return favorites ? "즐겨찾는 방송국 \(count)개" : "방송국 \(count)개"
        case "泰文": return favorites ? "สถานีโปรด \(count) สถานี" : "\(count) สถานี"
        case "西班牙语": return favorites ? "\(count) emisoras favoritas" : "\(count) emisoras"
        case "阿拉伯文": return favorites ? "\(count) محطة مفضلة" : "\(count) محطة"
        default: return favorites ? "\(count) 个已收藏频道" : "\(count) 个频道"
        }
    }
    static func stopAfter(_ minutes: Int, language: String) -> String {
        switch language {
        case "英文": return "Stop after \(minutes) min"
        case "日文": return "\(minutes) 分後に停止"
        case "韩文": return "\(minutes)분 후 중지"
        case "泰文": return "หยุดใน \(minutes) นาที"
        case "西班牙语": return "Detener en \(minutes) min"
        case "阿拉伯文": return "إيقاف بعد \(minutes) دقيقة"
        default: return "\(minutes) 分钟后停止"
        }
    }
    static func line(_ index: Int, format: String, language: String) -> String {
        switch language {
        case "英文": return "Line \(index) · \(format)"
        case "日文": return "回線 \(index) · \(format)"
        case "韩文": return "회선 \(index) · \(format)"
        case "泰文": return "ช่องสัญญาณ \(index) · \(format)"
        case "西班牙语": return "Línea \(index) · \(format)"
        case "阿拉伯文": return "المسار \(index) · \(format)"
        default: return "线路 \(index) · \(format)"
        }
    }
    static func debugCatalogSummary(_ count: Int, language: String) -> String {
        switch language {
        case "英文": return "Development directory: \(count) stations. iPhone device testing is still required."
        case "日文": return "開発用ディレクトリ: \(count) 局。iPhone 実機での再確認が必要です。"
        case "韩文": return "개발용 목록: \(count)개 방송국. iPhone 실기기 재검증이 필요합니다."
        case "泰文": return "รายชื่อสำหรับพัฒนา: \(count) สถานี ยังต้องทดสอบบน iPhone จริง"
        case "西班牙语": return "Directorio de desarrollo: \(count) emisoras. Aún se requiere comprobarlo en un iPhone real."
        case "阿拉伯文": return "دليل التطوير: \(count) محطة. ما زال يلزم اختباره على iPhone فعلي."
        default: return "开发候选目录：\(count) 个电台，仍需 iPhone 真机复测。"
        }
    }
    static func stationAction(_ action: String, stationName: String, language: String) -> String {
        switch language {
        case "英文": return action == "收藏" ? "Favorite \(stationName)" : action == "取消收藏" ? "Remove \(stationName) from favorites" : "Listen to \(stationName)"
        case "日文": return action == "收藏" ? "\(stationName) をお気に入りに追加" : action == "取消收藏" ? "\(stationName) をお気に入りから解除" : "\(stationName) を聴く"
        case "韩文": return action == "收藏" ? "\(stationName) 즐겨찾기" : action == "取消收藏" ? "\(stationName) 즐겨찾기 해제" : "\(stationName) 듣기"
        case "泰文": return action == "收藏" ? "เพิ่ม \(stationName) ในรายการโปรด" : action == "取消收藏" ? "นำ \(stationName) ออกจากรายการโปรด" : "ฟัง \(stationName)"
        case "西班牙语": return action == "收藏" ? "Añadir \(stationName) a favoritos" : action == "取消收藏" ? "Quitar \(stationName) de favoritos" : "Escuchar \(stationName)"
        case "阿拉伯文": return action == "收藏" ? "إضافة \(stationName) إلى المفضلة" : action == "取消收藏" ? "إزالة \(stationName) من المفضلة" : "استمع إلى \(stationName)"
        default: return "\(action) \(stationName)"
        }
    }
    // Values are English, Japanese, Korean, Thai, and Spanish, respectively.
    static let localized: [String: [String]] = [
        "繁體中文": ["Traditional Chinese", "繁体中国語", "번체 중국어", "จีนตัวเต็ม", "Chino tradicional"],
        "简体中文": ["Simplified Chinese", "簡体中国語", "간체 중국어", "จีนตัวย่อ", "Chino simplificado"],
        "英文": ["English", "英語", "영어", "อังกฤษ", "Inglés"],
        "日文": ["Japanese", "日本語", "일본어", "ญี่ปุ่น", "Japonés"],
        "韩文": ["Korean", "韓国語", "한국어", "เกาหลี", "Coreano"],
        "泰文": ["Thai", "タイ語", "태국어", "ไทย", "Tailandés"],
        "西班牙语": ["Spanish", "スペイン語", "스페인어", "สเปน", "Español"],
        "浅色": ["Light", "ライト", "라이트", "สว่าง", "Claro"],
        "深色": ["Dark", "ダーク", "다크", "มืด", "Oscuro"],
        "跟随系统": ["System", "システムに合わせる", "시스템 설정", "ตามระบบ", "Sistema"],
        "检查更新": ["Check for Updates", "アップデートを確認", "업데이트 확인", "ตรวจสอบการอัปเดต", "Buscar actualizaciones"],
        "知道了": ["OK", "OK", "확인", "ตกลง", "Aceptar"],
        "当前为本地开发版本，尚未接入 App Store 更新检查。": ["This is a local development build. App Store update checks are not available yet.", "これはローカル開発版です。App Store のアップデート確認はまだ利用できません。", "로컬 개발 빌드입니다. App Store 업데이트 확인은 아직 제공되지 않습니다.", "นี่คือเวอร์ชันพัฒนาในเครื่อง ยังไม่รองรับการตรวจสอบอัปเดตจาก App Store", "Esta es una versión local de desarrollo. La comprobación de actualizaciones de App Store aún no está disponible."],
        "清空本机常听记录？": ["Clear listening history on this device?", "この端末の再生履歴を消去しますか？", "이 기기의 청취 기록을 지울까요?", "ล้างประวัติการฟังในอุปกรณ์นี้หรือไม่?", "¿Borrar el historial de escucha de este dispositivo?"],
        "清空记录": ["Clear History", "履歴を消去", "기록 지우기", "ล้างประวัติ", "Borrar historial"],
        "华语广播 · 随时相伴": ["Chinese radio · always with you", "中国語ラジオ · いつでもそばに", "중국어 라디오 · 언제나 함께", "วิทยุภาษาจีน · อยู่เคียงข้างคุณเสมอ", "Radio china · siempre contigo"],
        "聆听你的世界": ["Tune into your world", "あなたの世界を聴こう", "당신의 세상을 들어보세요", "ฟังโลกของคุณ", "Sintoniza tu mundo"],
        "从熟悉的乡音，到远方的日常。\n让世界的声音，在这里相遇。": ["From familiar hometown voices to everyday life far away.\nLet the sounds of the world meet here.", "懐かしい故郷の声から、遠い場所の日常まで。\n世界の音が、ここで出会います。", "익숙한 고향의 목소리에서 먼 곳의 일상까지.\n세상의 소리가 이곳에서 만납니다.", "จากเสียงคุ้นเคยของบ้านเกิดสู่ชีวิตประจำวันในแดนไกล\nให้เสียงของโลกมาพบกันที่นี่", "De las voces familiares de casa a la vida cotidiana lejana.\nQue los sonidos del mundo se encuentren aquí."],
        "开始收听": ["Start Listening", "聴き始める", "듣기 시작", "เริ่มฟัง", "Empezar a escuchar"],
        "波粒": ["Wavelet", "ウェーブレット", "웨이블릿", "เวฟเล็ต", "Wavelet"],
        "打开收音机，\n听见此刻。": ["Turn on the radio,\nhear this moment.", "ラジオをつけて、\n今を聴こう。", "라디오를 켜고,\n지금을 들어보세요.", "เปิดวิทยุ\nฟังช่วงเวลานี้", "Enciende la radio,\nescucha este momento."],
        "打开收音机，听见此刻。": ["Turn on the radio, hear this moment.", "ラジオをつけて、今を聴こう。", "라디오를 켜고, 지금을 들어보세요.", "เปิดวิทยุ ฟังช่วงเวลานี้", "Enciende la radio, escucha este momento."],
        "电台列表": ["Station List", "放送局リスト", "방송국 목록", "รายชื่อสถานี", "Lista de emisoras"],
        "设置": ["Settings", "設定", "설정", "การตั้งค่า", "Ajustes"],
        "返回首页": ["Back to Home", "ホームに戻る", "홈으로 돌아가기", "กลับหน้าแรก", "Volver al inicio"],
        "我的收藏": ["Favorites", "お気に入り", "즐겨찾기", "รายการโปรด", "Favoritos"],
        "检索": ["Search", "検索", "검색", "ค้นหา", "Buscar"],
        "还没有收藏的电台": ["No favorite stations yet", "お気に入りの放送局はまだありません", "아직 즐겨찾는 방송국이 없습니다", "ยังไม่มีสถานีโปรด", "Aún no hay emisoras favoritas"],
        "可在首页或检索结果中点击五角星收藏。": ["Tap the star on Home or in search results to add a favorite.", "ホームまたは検索結果の星をタップして追加できます。", "홈 또는 검색 결과에서 별표를 눌러 즐겨찾기에 추가하세요.", "แตะดาวบนหน้าแรกหรือผลการค้นหาเพื่อเพิ่มรายการโปรด", "Toca la estrella en Inicio o en los resultados para añadir un favorito."],
        "最近收藏": ["Recently Favorited", "最近のお気に入り", "최근 즐겨찾기", "เพิ่มล่าสุด", "Favoritos recientes"],
        "搜索台名、频率、城市": ["Search station, frequency, city", "局名、周波数、都市を検索", "방송국, 주파수, 도시 검색", "ค้นหาสถานี ความถี่ เมือง", "Buscar emisora, frecuencia o ciudad"],
        "清除搜索": ["Clear Search", "検索をクリア", "검색 지우기", "ล้างการค้นหา", "Borrar búsqueda"],
        "地区": ["Region", "地域", "지역", "ภูมิภาค", "Región"],
        "全部地区": ["All Regions", "すべての地域", "모든 지역", "ทุกภูมิภาค", "Todas las regiones"],
        "省市 / 分组": ["Province / Group", "省・市 / グループ", "성 / 그룹", "จังหวัด / กลุ่ม", "Provincia / grupo"],
        "城市": ["City", "都市", "도시", "เมือง", "Ciudad"],
        "节目类型": ["Program Type", "番組タイプ", "프로그램 유형", "ประเภทรายการ", "Tipo de programa"],
        "没有匹配的电台，请调整搜索或筛选条件。": ["No matching stations. Adjust your search or filters.", "一致する放送局がありません。検索または絞り込みを変更してください。", "일치하는 방송국이 없습니다. 검색어나 필터를 조정하세요.", "ไม่พบสถานีที่ตรงกัน โปรดปรับการค้นหาหรือตัวกรอง", "No hay emisoras coincidentes. Ajusta la búsqueda o los filtros."],
        "全部": ["All", "すべて", "전체", "ทั้งหมด", "Todo"],
        "返回": ["Back", "戻る", "뒤로", "กลับ", "Volver"],
        "现在播放": ["Now Playing", "再生中", "지금 재생", "กำลังเล่น", "Reproduciendo"],
        "尚未选择电台": ["No station selected", "放送局が未選択です", "선택한 방송국이 없습니다", "ยังไม่ได้เลือกสถานี", "No hay emisora seleccionada"],
        "播放线路": ["Stream", "再生回線", "재생 회선", "สตรีม", "Transmisión"],
        "线路": ["Line", "回線", "회선", "ช่องสัญญาณ", "Línea"],
        "播放来源": ["Source", "配信元", "재생 출처", "แหล่งที่มา", "Fuente"],
        "查看目录来源": ["View Directory Source", "ディレクトリの出典を見る", "디렉터리 출처 보기", "ดูแหล่งข้อมูลไดเรกทอรี", "Ver fuente del directorio"],
        "电台网站": ["Station Website", "放送局サイト", "방송국 웹사이트", "เว็บไซต์สถานี", "Sitio web de la emisora"],
        "暂无来源信息": ["No source information", "出典情報はありません", "출처 정보가 없습니다", "ไม่มีข้อมูลแหล่งที่มา", "No hay información de la fuente"],
        "播放": ["Playback", "再生", "재생", "การเล่น", "Reproducción"],
        "取消定时": ["Cancel Timer", "タイマーを解除", "타이머 취소", "ยกเลิกตัวตั้งเวลา", "Cancelar temporizador"],
        "睡眠定时": ["Sleep Timer", "スリープタイマー", "수면 타이머", "ตั้งเวลาปิด", "Temporizador de apagado"],
        "未开启": ["Off", "オフ", "꺼짐", "ปิด", "Desactivado"],
        "启动时自动播放": ["Autoplay on Launch", "起動時に自動再生", "실행 시 자동 재생", "เล่นอัตโนมัติเมื่อเปิด", "Reproducir al iniciar"],
        "开启后，点击封面「开始收听」进入首页时，自动播放上次选择的电台。": ["When enabled, tapping Start Listening on the cover plays the last selected station.", "オンにすると、カバーの「聴き始める」をタップした際に前回の放送局を再生します。", "켜면 커버에서 듣기 시작을 누를 때 마지막으로 선택한 방송국을 재생합니다.", "เมื่อเปิดใช้งาน การแตะเริ่มฟังบนหน้าปกจะเล่นสถานีล่าสุด", "Al activarlo, tocar Empezar a escuchar en la portada reproducirá la última emisora seleccionada."],
        "通用": ["General", "一般", "일반", "ทั่วไป", "General"],
        "主题": ["Appearance", "テーマ", "테마", "ธีม", "Tema"],
        "语言": ["Language", "言語", "언어", "ภาษา", "Idioma"],
        "关于": ["About", "このアプリについて", "정보", "เกี่ยวกับ", "Acerca de"],
        "关于波粒": ["About Wavelet", "Wavelet について", "Wavelet 정보", "เกี่ยวกับ Wavelet", "Acerca de Wavelet"],
        "开发版": ["Development", "開発版", "개발 버전", "เวอร์ชันพัฒนา", "Desarrollo"],
        "波粒连接各地区的在线广播与电视伴音。节目与音频由对应电台服务商提供。": ["Wavelet connects online radio and TV audio from different regions. Programs and audio are provided by their respective stations.", "Wavelet は各地域のオンラインラジオとテレビ音声をつなぎます。番組と音声は各放送局が提供します。", "Wavelet은 여러 지역의 온라인 라디오와 TV 오디오를 연결합니다. 프로그램과 오디오는 각 방송국이 제공합니다.", "Wavelet เชื่อมต่อวิทยุออนไลน์และเสียงทีวีจากภูมิภาคต่างๆ รายการและเสียงให้บริการโดยสถานีที่เกี่ยวข้อง", "Wavelet conecta radio en línea y audio de TV de distintas regiones. Los programas y el audio los proporcionan sus respectivas emisoras."],
        "常听记录仅保存在本机。无账号或云同步；播放时电台服务商会接收连接所需的网络信息。": ["Listening history stays only on this device. There are no accounts or cloud sync; stations receive network information needed for playback.", "再生履歴はこの端末にのみ保存されます。アカウントやクラウド同期はありません。再生時には放送局が接続に必要なネットワーク情報を受け取ります。", "청취 기록은 이 기기에만 저장됩니다. 계정이나 클라우드 동기화는 없으며, 재생 중 방송국은 연결에 필요한 네트워크 정보를 받습니다.", "ประวัติการฟังเก็บไว้ในอุปกรณ์นี้เท่านั้น ไม่มีบัญชีหรือการซิงก์คลาวด์ สถานีจะได้รับข้อมูลเครือข่ายที่จำเป็นต่อการเล่น", "El historial se guarda solo en este dispositivo. No hay cuentas ni sincronización en la nube; las emisoras reciben la información de red necesaria para reproducir."],
        "字体：Noto Sans SC / Inter / Space Mono / Archivo，按 SIL Open Font License 使用。": ["Fonts: Noto Sans SC / Inter / Space Mono / Archivo, used under the SIL Open Font License.", "フォント: Noto Sans SC / Inter / Space Mono / Archivo。SIL Open Font License に基づき使用しています。", "글꼴: Noto Sans SC / Inter / Space Mono / Archivo. SIL Open Font License에 따라 사용됩니다.", "แบบอักษร: Noto Sans SC / Inter / Space Mono / Archivo ใช้ภายใต้ SIL Open Font License", "Fuentes: Noto Sans SC / Inter / Space Mono / Archivo, utilizadas bajo la SIL Open Font License."],
        "完成": ["Done", "完了", "완료", "เสร็จสิ้น", "Listo"],
        "查看播放状态": ["View playback status", "再生状態を見る", "재생 상태 보기", "ดูสถานะการเล่น", "Ver estado de reproducción"],
        "上一台": ["Previous station", "前の局", "이전 방송국", "สถานีก่อนหน้า", "Emisora anterior"],
        "暂停播放": ["Pause playback", "再生を一時停止", "재생 일시 정지", "หยุดเล่นชั่วคราว", "Pausar reproducción"],
        "下一台": ["Next station", "次の局", "다음 방송국", "สถานีถัดไป", "Emisora siguiente"],
        "音量": ["Volume", "音量", "볼륨", "ระดับเสียง", "Volumen"],
        "收藏": ["Favorite", "お気に入り", "즐겨찾기", "รายการโปรด", "Favorito"],
        "取消收藏": ["Remove Favorite", "お気に入りを解除", "즐겨찾기 해제", "รายการโปรดออก", "Quitar favorito"],
        "收藏当前电台": ["Favorite current station", "現在の放送局をお気に入りに追加", "현재 방송국 즐겨찾기", "เพิ่มสถานีปัจจุบันในรายการโปรด", "Añadir emisora actual a favoritos"],
        "取消睡眠定时": ["Cancel sleep timer", "スリープタイマーを解除", "수면 타이머 취소", "ยกเลิกตั้งเวลาปิด", "Cancelar temporizador de apagado"],
        "睡眠": ["Sleep", "スリープ", "수면", "พัก", "Dormir"],
        "华语广播": ["Chinese Radio", "中国語ラジオ", "중국어 라디오", "วิทยุภาษาจีน", "Radio china"],
        "选择电台，开始收听": ["Choose a station to start listening", "放送局を選んで聴き始めましょう", "방송국을 선택하고 듣기를 시작하세요", "เลือกสถานีเพื่อเริ่มฟัง", "Elige una emisora para empezar a escuchar"],
        "准备就绪": ["Ready", "準備完了", "준비됨", "พร้อม", "Listo"],
        "正在连接": ["Connecting", "接続中", "연결 중", "กำลังเชื่อมต่อ", "Conectando"],
        "正在缓冲": ["Buffering", "バッファリング中", "버퍼링 중", "กำลังบัฟเฟอร์", "Almacenando en búfer"],
        "正在收听": ["Listening", "再生中", "재생 중", "กำลังฟัง", "Escuchando"],
        "已暂停": ["Paused", "一時停止", "일시 정지됨", "หยุดชั่วคราว", "En pausa"],
        "连接失败": ["Connection failed", "接続に失敗しました", "연결에 실패했습니다", "การเชื่อมต่อล้มเหลว", "Error de conexión"],
        "电台目录读取失败，请重新安装或稍后重试。": ["Could not load the station directory. Reinstall the app or try again later.", "放送局ディレクトリを読み込めません。再インストールするか、後でもう一度お試しください。", "방송국 목록을 불러올 수 없습니다. 앱을 다시 설치하거나 나중에 다시 시도하세요.", "ไม่สามารถโหลดรายชื่อสถานีได้ โปรดติดตั้งใหม่หรือลองอีกครั้งภายหลัง", "No se pudo cargar el directorio de emisoras. Reinstala la app o inténtalo más tarde."],
        "网络已断开。恢复网络后，请点击播放重连。": ["Network disconnected. Restore your connection and tap play to reconnect.", "ネットワークが切断されました。接続を戻して再生をタップしてください。", "네트워크 연결이 끊겼습니다. 연결을 복구한 뒤 재생을 누르세요.", "เครือข่ายขาดการเชื่อมต่อ โปรดเชื่อมต่อใหม่แล้วแตะเล่น", "La red se desconectó. Restablece la conexión y toca reproducir para reconectar."],
        "网络不可用，请连接网络后重试。": ["Network unavailable. Connect to a network and try again.", "ネットワークを利用できません。接続してからもう一度お試しください。", "네트워크를 사용할 수 없습니다. 연결한 뒤 다시 시도하세요.", "เครือข่ายใช้งานไม่ได้ โปรดเชื่อมต่อแล้วลองอีกครั้ง", "La red no está disponible. Conéctate e inténtalo de nuevo."],
        "电台暂无可用线路。": ["This station has no available stream.", "この放送局には利用可能な回線がありません。", "이 방송국에는 사용 가능한 스트림이 없습니다.", "สถานีนี้ไม่มีสตรีมที่ใช้งานได้", "Esta emisora no tiene una transmisión disponible."],
        "连接未成功，可能受网络或地区限制。请重试或手动切换线路。": ["Connection did not succeed. Network or regional restrictions may apply. Try again or switch lines manually.", "接続できませんでした。ネットワークまたは地域の制限の可能性があります。再試行するか、手動で回線を切り替えてください。", "연결하지 못했습니다. 네트워크 또는 지역 제한이 있을 수 있습니다. 다시 시도하거나 회선을 수동으로 바꾸세요.", "เชื่อมต่อไม่สำเร็จ อาจมีข้อจำกัดด้านเครือข่ายหรือภูมิภาค โปรดลองอีกครั้งหรือเปลี่ยนช่องสัญญาณด้วยตนเอง", "La conexión no se completó. Puede haber restricciones de red o región. Inténtalo de nuevo o cambia de línea manualmente."],
        "中国大陆": ["Mainland China", "中国本土", "중국 본토", "จีนแผ่นดินใหญ่", "China continental"],
        "香港": ["Hong Kong", "香港", "홍콩", "ฮ่องกง", "Hong Kong"],
        "澳门": ["Macao", "マカオ", "마카오", "มาเก๊า", "Macao"],
        "台湾": ["Taiwan", "台湾", "대만", "ไต้หวัน", "Taiwán"],
        "美国": ["United States", "アメリカ", "미국", "สหรัฐอเมริกา", "Estados Unidos"],
        "新加坡": ["Singapore", "シンガポール", "싱가포르", "สิงคโปร์", "Singapur"],
        "马来西亚": ["Malaysia", "マレーシア", "말레이시아", "มาเลเซีย", "Malasia"],
        "日本": ["Japan", "日本", "일본", "ญี่ปุ่น", "Japón"],
        "其他地区": ["Other Regions", "その他の地域", "기타 지역", "ภูมิภาคอื่น", "Otras regiones"],
        "电视伴音": ["TV Audio", "テレビ音声", "TV 오디오", "เสียงทีวี", "Audio de TV"],
        "央广及全国广播": ["National Radio", "全国放送", "전국 방송", "วิทยุระดับชาติ", "Radio nacional"],
        "最近收听": ["Recently Played", "最近聴いた局", "최근 청취", "ฟังล่าสุด", "Escuchadas recientemente"],
        "查看全部": ["View All", "すべて表示", "모두 보기", "ดูทั้งหมด", "Ver todo"],
        "综合": ["General", "総合", "종합", "ทั่วไป", "General"],
        "中文/华语": ["Chinese", "中国語", "중국어", "ภาษาจีน", "Chino"],
        "华语": ["Chinese", "中国語", "중국어", "ภาษาจีน", "Chino"],
        "华语（社区收录）": ["Chinese (community listing)", "中国語（コミュニティ掲載）", "중국어(커뮤니티 등록)", "ภาษาจีน (ชุมชนรวบรวม)", "Chino (listado comunitario)"],
        "普通话": ["Mandarin", "標準中国語", "표준 중국어", "ภาษาจีนกลาง", "Mandarín"],
        "粤语": ["Cantonese", "広東語", "광둥어", "กวางตุ้ง", "Cantonés"],
        "英语": ["English", "英語", "영어", "อังกฤษ", "Inglés"],
        "哈萨克语": ["Kazakh", "カザフ語", "카자흐어", "คาซัค", "Kazajo"],
        "维吾尔语": ["Uyghur", "ウイグル語", "위구르어", "อุยกูร์", "Uigur"],
        "蒙古语": ["Mongolian", "モンゴル語", "몽골어", "มองโกเลีย", "Mongol"],
        "藏语": ["Tibetan", "チベット語", "티베트어", "ทิเบต", "Tibetano"],
        "多语种（依节目时段）": ["Multilingual (varies by program)", "多言語（番組により異なる）", "다국어(프로그램별 상이)", "หลายภาษา (ขึ้นอยู่กับรายการ)", "Multilingüe (según el programa)"],
        "新闻资讯": ["News", "ニュース", "뉴스", "ข่าว", "Noticias"],
        "财经": ["Business", "経済", "경제", "ธุรกิจ", "Economía"],
        "音乐": ["Music", "音楽", "음악", "เพลง", "Música"],
        "流行音乐": ["Pop Music", "ポップ音楽", "대중음악", "เพลงป๊อป", "Música pop"],
        "古典音乐": ["Classical Music", "クラシック音楽", "클래식 음악", "ดนตรีคลาสสิก", "Música clásica"],
        "乡村音乐": ["Country Music", "カントリー音楽", "컨트리 음악", "เพลงคันทรี", "Música country"],
        "体育": ["Sports", "スポーツ", "스포츠", "กีฬา", "Deportes"],
        "交通": ["Traffic", "交通", "교통", "จราจร", "Tráfico"],
        "生活": ["Lifestyle", "生活", "생활", "ไลฟ์สไตล์", "Estilo de vida"],
        "文艺戏曲": ["Arts & Opera", "芸術・戯曲", "예술·전통극", "ศิลปะและอุปรากร", "Arte y ópera"],
        "宗教": ["Religion", "宗教", "종교", "ศาสนา", "Religión"],
        "教育少儿": ["Education & Kids", "教育・子ども", "교육·어린이", "การศึกษาและเด็ก", "Educación e infantil"],
        "教育电视": ["Educational TV", "教育テレビ", "교육 TV", "โทรทัศน์การศึกษา", "Televisión educativa"],
        "地方电视伴音": ["Local TV Audio", "地域テレビ音声", "지역 TV 오디오", "เสียงทีวีท้องถิ่น", "Audio de TV local"],
        "央视伴音": ["CCTV Audio", "CCTV 音声", "CCTV 오디오", "เสียง CCTV", "Audio de CCTV"]
    ]
    static let arabic: [String: String] = [
        "繁體中文": "الصينية التقليدية", "简体中文": "الصينية المبسطة", "英文": "الإنجليزية", "日文": "اليابانية", "韩文": "الكورية", "泰文": "التايلاندية", "西班牙语": "الإسبانية", "阿拉伯文": "العربية",
        "浅色": "فاتح", "深色": "داكن", "跟随系统": "النظام", "检查更新": "التحقق من التحديثات", "知道了": "حسنًا",
        "当前为本地开发版本，尚未接入 App Store 更新检查。": "هذه نسخة تطوير محلية. لم تتوفر بعد ميزة التحقق من تحديثات App Store.",
        "清空本机常听记录？": "هل تريد مسح سجل الاستماع على هذا الجهاز؟", "清空记录": "مسح السجل",
        "华语广播 · 随时相伴": "إذاعة صينية · معك دائمًا", "聆听你的世界": "استمع إلى عالمك", "从熟悉的乡音，到远方的日常。\n让世界的声音，在这里相遇。": "من أصوات الوطن المألوفة إلى تفاصيل الحياة البعيدة.\nهنا تلتقي أصوات العالم.",
        "开始收听": "ابدأ الاستماع", "波粒": "Wavelet", "打开收音机，\n听见此刻。": "شغّل الراديو،\nواستمع إلى هذه اللحظة.", "打开收音机，听见此刻。": "شغّل الراديو، واستمع إلى هذه اللحظة.",
        "电台列表": "قائمة المحطات", "设置": "الإعدادات", "返回首页": "العودة إلى الرئيسية", "我的收藏": "المفضلة", "检索": "بحث",
        "还没有收藏的电台": "لا توجد محطات مفضلة بعد", "可在首页或检索结果中点击五角星收藏。": "اضغط النجمة في الرئيسية أو نتائج البحث للإضافة إلى المفضلة.", "最近收藏": "أُضيفت مؤخرًا",
        "搜索台名、频率、城市": "ابحث عن محطة أو تردد أو مدينة", "清除搜索": "مسح البحث", "地区": "المنطقة", "全部地区": "كل المناطق", "省市 / 分组": "المقاطعة / المجموعة", "城市": "المدينة", "节目类型": "نوع البرنامج", "没有匹配的电台，请调整搜索或筛选条件。": "لا توجد محطات مطابقة. عدّل البحث أو عوامل التصفية.", "全部": "الكل",
        "返回": "رجوع", "现在播放": "قيد التشغيل", "尚未选择电台": "لم تُحدّد محطة", "播放线路": "البث", "线路": "المسار", "播放来源": "المصدر", "查看目录来源": "عرض مصدر الدليل", "电台网站": "موقع المحطة", "暂无来源信息": "لا توجد معلومات مصدر",
        "播放": "التشغيل", "取消定时": "إلغاء المؤقت", "睡眠定时": "مؤقت النوم", "未开启": "متوقف", "启动时自动播放": "تشغيل تلقائي عند البدء", "开启后，点击封面「开始收听」进入首页时，自动播放上次选择的电台。": "عند التفعيل، سيؤدي الضغط على «ابدأ الاستماع» في الغلاف إلى تشغيل آخر محطة اخترتها.",
        "通用": "عام", "主题": "المظهر", "语言": "اللغة", "关于": "حول", "关于波粒": "حول Wavelet", "开发版": "نسخة تطوير",
        "波粒连接各地区的在线广播与电视伴音。节目与音频由对应电台服务商提供。": "يربط Wavelet الإذاعات عبر الإنترنت وصوت التلفاز من مناطق مختلفة. البرامج والصوت مقدمان من المحطات المعنية.",
        "常听记录仅保存在本机。无账号或云同步；播放时电台服务商会接收连接所需的网络信息。": "يُحفظ سجل الاستماع على هذا الجهاز فقط. لا توجد حسابات أو مزامنة سحابية؛ أثناء التشغيل تتلقى المحطة معلومات الشبكة اللازمة للاتصال.",
        "字体：Noto Sans SC / Inter / Space Mono / Archivo，按 SIL Open Font License 使用。": "الخطوط: Noto Sans SC / Inter / Space Mono / Archivo، مستخدمة بموجب SIL Open Font License.", "完成": "تم",
        "查看播放状态": "عرض حالة التشغيل", "上一台": "المحطة السابقة", "暂停播放": "إيقاف مؤقت", "下一台": "المحطة التالية", "音量": "مستوى الصوت", "收藏": "مفضلة", "取消收藏": "إزالة من المفضلة", "收藏当前电台": "إضافة المحطة الحالية إلى المفضلة", "取消睡眠定时": "إلغاء مؤقت النوم", "睡眠": "نوم",
        "华语广播": "إذاعة صينية", "选择电台，开始收听": "اختر محطة لبدء الاستماع", "准备就绪": "جاهز", "正在连接": "جارٍ الاتصال", "正在缓冲": "جارٍ التخزين المؤقت", "正在收听": "جارٍ الاستماع", "已暂停": "متوقف مؤقتًا", "连接失败": "فشل الاتصال",
        "电台目录读取失败，请重新安装或稍后重试。": "تعذر تحميل دليل المحطات. أعد تثبيت التطبيق أو حاول لاحقًا.", "网络已断开。恢复网络后，请点击播放重连。": "انقطع الاتصال بالشبكة. أعد الاتصال ثم اضغط تشغيل لإعادة المحاولة.", "网络不可用，请连接网络后重试。": "الشبكة غير متاحة. اتصل بالشبكة وحاول مجددًا.", "电台暂无可用线路。": "لا يتوفر بث لهذه المحطة.", "连接未成功，可能受网络或地区限制。请重试或手动切换线路。": "لم ينجح الاتصال. قد تنطبق قيود على الشبكة أو المنطقة. أعد المحاولة أو بدّل المسار يدويًا.",
        "中国大陆": "البر الرئيسي للصين", "香港": "هونغ كونغ", "澳门": "ماكاو", "台湾": "تايوان", "美国": "الولايات المتحدة", "新加坡": "سنغافورة", "马来西亚": "ماليزيا", "日本": "اليابان", "其他地区": "مناطق أخرى", "电视伴音": "صوت التلفاز", "央广及全国广播": "إذاعة وطنية",
        "最近收听": "تم الاستماع إليها مؤخرًا", "查看全部": "عرض الكل", "综合": "عام", "中文/华语": "الصينية", "华语": "الصينية", "华语（社区收录）": "الصينية (إدراج مجتمعي)", "普通话": "الماندرين", "粤语": "الكانتونية", "英语": "الإنجليزية", "哈萨克语": "الكازاخية", "维吾尔语": "الأويغورية", "蒙古语": "المنغولية", "藏语": "التبتية", "多语种（依节目时段）": "متعدد اللغات (حسب البرنامج)",
        "新闻资讯": "الأخبار", "财经": "الأعمال", "音乐": "الموسيقى", "流行音乐": "موسيقى البوب", "古典音乐": "الموسيقى الكلاسيكية", "乡村音乐": "موسيقى الريف", "体育": "الرياضة", "交通": "المرور", "生活": "نمط الحياة", "文艺戏曲": "الفنون والأوبرا", "宗教": "الدين", "教育少儿": "التعليم والأطفال", "教育电视": "التلفزيون التعليمي", "地方电视伴音": "صوت التلفزيون المحلي", "央视伴音": "صوت CCTV"
    ]
}
private extension Color {
    init(hex: UInt32) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}

struct ContentView: View {
    enum Route: Hashable { case discovery, settings }
    enum DirectorySection { case favorites, search }
    @Bindable var store: RadioStore
    @State private var entered = false
    @State private var showDiscovery = false
    @State private var showSettings = false
    @State private var showPlayer = false
    @State private var showAbout = false
    @State private var showUpdate = false
    @State private var confirmClear = false
    @State private var returningFromDiscovery = false
    @State private var discoveryOffset: CGFloat = 0
    @State private var playbackOffset: CGFloat = 0
    @State private var directorySection: DirectorySection = .search
    @State private var homeQuote = ""
    @AppStorage("wavelet.autoplay") private var autoplay = false
    @AppStorage("wavelet.theme") private var theme = "浅色"
    @AppStorage("wavelet.language") private var languagePreference = "跟随系统"
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var language: String { Design.resolvedLanguage(languagePreference) }
    private var dark: Bool { theme == "深色" || (theme == "跟随系统" && scheme == .dark) }
    private var paper: Color { dark ? Color(hex: 0x1D241D) : Design.paper }
    private var card: Color { dark ? Design.forest : Design.card }
    private var ink: Color { dark ? Design.card : Design.ink }
    private func t(_ value: String) -> String { Design.translate(value, language) }
    private func text(_ value: String) -> Text { Text(t(value)) }
    private func localizedSubtitle(_ station: Station) -> String {
        [t(station.regionName), station.group, station.city]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: " · ")
    }
    private var dateLocaleIdentifier: String {
        switch language {
        case "繁體中文": "zh-Hant"
        case "英文": "en"
        case "日文": "ja"
        case "韩文": "ko"
        case "泰文": "th"
        case "西班牙语": "es"
        case "阿拉伯文": "ar"
        default: "zh-Hans"
        }
    }
    private var today: String {
        Date.now.formatted(.dateTime.year().month(.wide).day().weekday(.wide).locale(Locale(identifier: dateLocaleIdentifier)))
    }
    private func refreshHomeQuote() { homeQuote = QuoteCatalog.random() }
    private var separator: some View { Rectangle().fill(Design.line.opacity(dark ? 0.2 : 1)).frame(height: 1) }
    private var tabletSidebarWidth: CGFloat { 270 }

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 700 {
                    tabletExperience(size: proxy.size)
                } else {
                    phoneExperience
                }
            }
        }
        .font(Design.font(16)).foregroundStyle(ink).tint(dark ? Design.amber : Design.forest)
        .environment(\.layoutDirection, language == "阿拉伯文" ? .rightToLeft : .leftToRight)
        .preferredColorScheme(theme == "跟随系统" ? nil : dark ? .dark : .light)
        .sheet(isPresented: $showAbout) { about }
        .alert(t("检查更新"), isPresented: $showUpdate) { Button(t("知道了"), role: .cancel) {} }
            message: { text("当前为本地开发版本，尚未接入 App Store 更新检查。") }
        .confirmationDialog(t("清空本机常听记录？"), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(t("清空记录"), role: .destructive) { store.clearHistory() }
        }
        .onChange(of: phase) { if phase == .active { store.player.checkDeadline() } }
        .sensoryFeedback(.selection, trigger: store.player.station?.id)
        .onAppear { store.applyLanguage(language); configurePreviewRoute(); refreshHomeQuote() }
        .onChange(of: language) { store.applyLanguage(language); refreshHomeQuote() }
        .task(id: entered) {
            guard entered else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, entered else { return }
                if !showDiscovery && !showSettings && !showPlayer { refreshHomeQuote() }
            }
        }
    }
    private var phoneExperience: some View {
        Group {
            if entered {
                ZStack {
                    home
                        .allowsHitTesting(!showDiscovery && !showSettings)
                        .accessibilityHidden(showDiscovery || showSettings)
                    if showDiscovery {
                        discovery
                            .simultaneousGesture(returnHomeGesture(from: .discovery))
                            .transition(.move(edge: .leading))
                            .zIndex(1)
                    }
                    if showSettings {
                        settings
                            .simultaneousGesture(returnHomeGesture(from: .settings))
                            .transition(.move(edge: .trailing))
                            .zIndex(1)
                    }
                    if showPlayer {
                        playback
                            .transition(.move(edge: .bottom))
                            .zIndex(2)
                    }
                }
                .background(paper.ignoresSafeArea())
            } else {
                cover
            }
        }
    }

    @ViewBuilder private func tabletExperience(size: CGSize) -> some View {
        if !entered {
            tabletCover(size: size)
        } else if showPlayer {
            tabletPlayback(size: size)
        } else if showDiscovery {
            tabletDiscovery(size: size)
        } else if showSettings {
            tabletSettings(size: size)
        } else {
            tabletHome(size: size)
        }
    }

    private func enterHome() {
        Logger(subsystem: "com.mythmedia.waveletradio", category: "Interaction").notice("enterHome action fired")
        entered = true
        if autoplay { store.player.play() }
    }

    private func tabletCover(size: CGSize) -> some View {
        let landscape = size.width > size.height
        return Group {
            if landscape {
                HStack(spacing: 64) {
                    tabletCoverCopy
                        .frame(maxWidth: 420, alignment: .leading)
                    ReceiverPanel(store: store, openPlayer: {}, coverPreview: true)
                        .allowsHitTesting(false)
                        .frame(maxWidth: 360)
                }
                .padding(.horizontal, 58)
                .padding(.vertical, 44)
            } else {
                HStack(alignment: .center, spacing: 24) {
                    tabletCoverCopy
                        .frame(width: 350, alignment: .leading)
                    ReceiverPanel(store: store, openPlayer: {}, coverPreview: true)
                        .allowsHitTesting(false)
                        .frame(width: 300)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 36)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(card.ignoresSafeArea())
    }

    private var tabletCoverCopy: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                secondaryBrandLogo(size: 204)
                text("华语广播 · 随时相伴")
                    .font(Design.font(13))
                    .foregroundStyle(Design.muted)
                    .padding(.top, 8)
                Rectangle()
                    .fill(Design.line.opacity(dark ? 0.35 : 1))
                    .frame(width: 204, height: 1)
                    .padding(.top, 12)
            }
            .frame(width: 204, alignment: .center)
            text("聆听你的世界")
                .font(Design.font(10, "SpaceMono", .bold))
                .tracking(3)
                .foregroundStyle(Color(hex: 0xBD8A3B))
                .padding(.top, 46)
            text("打开收音机，\n听见此刻。")
                .font(Design.font(42, "NotoSansSC", .black))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            text("从熟悉的乡音，到远方的日常。\n让世界的声音，在这里相遇。")
                .font(Design.font(14))
                .lineSpacing(7)
                .foregroundStyle(Design.muted)
                .padding(.top, 14)
            Button(action: enterHome) {
                Label(t("开始收听"), systemImage: "play.fill")
                    .font(Design.font(15, "NotoSansSC", .bold))
                    .foregroundStyle(Design.amber)
                    .padding(.horizontal, 24)
                    .frame(minHeight: 52)
                    .background(Design.forest, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityIdentifier("enterHome")
        }
    }

    @ViewBuilder private func tabletHome(size: CGSize) -> some View {
        let landscape = size.width > size.height
        if landscape {
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 18) {
                    tabletHeader(showNavigation: true)
                    tabletQuote
                    ReceiverPanel(store: store, openPlayer: { showPlayer = true })
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                tabletSidebar
                    .frame(width: tabletSidebarWidth)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
            .frame(maxWidth: 1120, maxHeight: .infinity, alignment: .top)
            .frame(maxWidth: .infinity)
            .background(paper.ignoresSafeArea())
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    tabletHeader(showNavigation: false)
                    tabletQuote
                    ReceiverPanel(store: store, openPlayer: { showPlayer = true })
                    tabletQuickActions
                    tabletStationCard(title: "最近收听", stations: recentStations, favorites: false)
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 34)
            }
            .background(paper.ignoresSafeArea())
        }
    }

    private func tabletHeader(showNavigation: Bool) -> some View {
        HStack(spacing: 18) {
            headerBrand
            Text(today).font(Design.font(11)).foregroundStyle(Design.muted)
            Spacer(minLength: 12)
            if showNavigation {
                tabletNavButton("电台列表", icon: "music.note.list") { openDiscovery() }
                tabletNavButton("设置", icon: "gearshape") { openSettings() }
            }
        }
        .frame(minHeight: 52)
    }

    private var tabletQuote: some View {
        Text(homeQuote)
            .font(.system(size: 25, weight: .bold, design: .rounded))
            .lineLimit(3)
            .minimumScaleFactor(0.78)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.28), value: homeQuote)
    }

    private func tabletNavButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t(title), systemImage: icon)
                .font(Design.font(13, "NotoSansSC", .bold))
                .padding(.horizontal, 13)
                .frame(minHeight: 44)
                .background(card, in: Capsule())
                .overlay(Capsule().strokeBorder(Design.line))
        }
        .buttonStyle(.plain)
    }

    private var tabletQuickActions: some View {
        HStack(spacing: 10) {
            tabletAction("电台列表", icon: "music.note.list") { openDiscovery(section: .search) }
            tabletAction("我的收藏", icon: "star") { openDiscovery(section: .favorites) }
            tabletAction("现在播放", icon: "play.circle") { showPlayer = true }
            tabletAction("设置", icon: "gearshape") { openSettings() }
        }
    }

    private func tabletAction(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(t(title), systemImage: icon)
                .font(Design.font(12, "NotoSansSC", .bold))
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Design.line))
        }
        .buttonStyle(.plain)
    }

    private var recentStations: [Station] {
        let ranked = rankedRecentStations
        return Array((ranked.isEmpty ? store.stations : ranked).prefix(5))
    }

    private var sidebarRecentStations: [Station] {
        let recent = Array(rankedRecentStations.prefix(6))
        guard recent.count < 6 else { return recent }
        let recentIDs = Set(recent.map(\.id))
        let fillers = store.stations
            .filter { !recentIDs.contains($0.id) }
            .prefix(6 - recent.count)
        return recent + fillers
    }

    private var rankedRecentStations: [Station] {
        let ranked = store.stations
            .filter { store.counts[$0.id, default: 0] > 0 }
            .sorted {
                let left = store.counts[$0.id, default: 0]
                let right = store.counts[$1.id, default: 0]
                return left == right ? Search.before($0.name, $1.name) : left > right
            }
        return ranked
    }

    private var tabletSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            tabletStationCard(title: "最近收听", stations: sidebarRecentStations, favorites: false, plain: true)
            separator
            tabletStationCard(title: "我的收藏", stations: Array(store.favoriteStations.prefix(5)), favorites: true, plain: true)
            Spacer(minLength: 0)
        }
    }

    private func tabletStationCard(title: String, stations: [Station], favorites: Bool, plain: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                text(title).font(Design.font(14, "NotoSansSC", .bold))
                Spacer()
                if favorites {
                    Button { openDiscovery(section: .favorites) } label: {
                        HStack(spacing: 4) {
                            text("查看全部")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(Design.font(10))
                        .foregroundStyle(Design.muted)
                    }
                        .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                if stations.isEmpty {
                    text("还没有收藏的电台")
                        .font(Design.font(12))
                        .foregroundStyle(Design.muted)
                        .frame(maxWidth: .infinity, minHeight: 64)
                } else {
                    ForEach(stations) { station in
                        Button {
                            store.select(station)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: store.player.station?.id == station.id ? "waveform" : "antenna.radiowaves.left.and.right")
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(station.name).font(Design.font(12, "NotoSansSC", .bold)).lineLimit(1)
                                    Text(localizedSubtitle(station)).font(Design.font(9)).foregroundStyle(Design.muted).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "play.circle").foregroundStyle(Design.muted)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if station.id != stations.last?.id { separator }
                    }
                }
            }
            .background(plain ? Color.clear : card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(plain ? Color.clear : Design.line))
        }
    }

    @ViewBuilder private func tabletDiscovery(size: CGSize) -> some View {
        if size.width > size.height {
            tabletDirectoryMain(returnWidth: size.width)
                .frame(maxWidth: .infinity)
                .background(paper.ignoresSafeArea())
        } else {
            tabletDirectoryMain(returnWidth: size.width)
                .background(paper.ignoresSafeArea())
        }
    }

    private func tabletDirectoryMain(returnWidth: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                pageHeader("电台列表")
                directoryTabs
                if directorySection == .favorites {
                    favoritesList(returnWidth: returnWidth)
                } else {
                    searchList(returnWidth: returnWidth)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
    }

    private func tabletCloseRail(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "chevron.left")
                text(title)
                    .font(Design.font(11, "NotoSansSC", .bold))
                    .fixedSize()
                    .rotationEffect(.degrees(-90))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .frame(width: 64)
        .background(card)
        .overlay(alignment: .trailing) { Rectangle().fill(Design.line).frame(width: 1) }
    }

    @ViewBuilder private func tabletSettings(size: CGSize) -> some View {
        if size.width > size.height {
            HStack(alignment: .top, spacing: 34) {
                settings.frame(maxWidth: 620)
                VStack {
                    Spacer(minLength: 32)
                    secondaryBrandLogo(size: 300)
                    Spacer(minLength: 32)
                }
                    .frame(maxWidth: 420)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: 1120, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(paper.ignoresSafeArea())
        } else {
            settings
        }
    }

    @ViewBuilder private func tabletPlayback(size: CGSize) -> some View {
        if size.width > size.height {
            HStack(spacing: 26) {
                playback
                    .clipShape(RoundedRectangle(cornerRadius: 26))
                tabletSidebar
                    .frame(width: tabletSidebarWidth)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: 1120, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .background(paper.ignoresSafeArea())
        } else {
            playback
        }
    }
    private var cover: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 36)
                    secondaryBrandLogo(size: 210)
                    Rectangle().fill(Design.line).frame(width: 60, height: 1).padding(.top, 20)
                    text("华语广播 · 随时相伴").foregroundStyle(Design.muted).padding(.top, 12)
                    text("聆听你的世界").font(Design.font(11, "SpaceMono", .bold)).tracking(3).foregroundStyle(Color(hex: 0xBD8A3B)).padding(.top, 24)
                    text("打开收音机，\n听见此刻。").font(Design.font(30, "NotoSansSC", .black)).multilineTextAlignment(.center).padding(.top, 20)
                    text("从熟悉的乡音，到远方的日常。\n让世界的声音，在这里相遇。")
                        .font(Design.font(15)).lineSpacing(9).multilineTextAlignment(.center).foregroundStyle(Design.muted).padding(.top, 20)
                    Button(action: enterHome) {
                        Label(t("开始收听"), systemImage: "play")
                            .font(Design.font(20, "NotoSansSC", .bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .foregroundStyle(Design.amber)
                            .background(Design.forest, in: Capsule())
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).padding(.top, 26).accessibilityIdentifier("enterHome")
                    Spacer(minLength: 34)
                }.padding(.horizontal, 32).frame(minHeight: proxy.size.height)
            }.background(card.ignoresSafeArea())
                .simultaneousGesture(TapGesture().onEnded {
                    Logger(subsystem: "com.mythmedia.waveletradio", category: "Interaction").notice("cover received tap")
                })
        }
    }
    private func secondaryBrandLogo(size: CGFloat) -> some View {
        Image("WaveletSettingsLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ink)
            .frame(width: size, height: size)
            .scaleEffect(1.5)
            .frame(width: size, height: size)
            .clipped()
            .accessibilityLabel(t("波粒"))
    }
    private var headerBrand: some View {
        Image("WaveletHeaderLogo")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ink)
            .frame(width: 130, height: 52, alignment: .leading)
            .accessibilityLabel(t("波粒"))
    }
    private var home: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let availableHeight = max(1, proxy.size.height)
            let scale = max(0.01, min(1, max(1, availableHeight - 32) / 780, availableWidth / 350))
            VStack(alignment: .leading, spacing: 16) {
                headerBrand.padding(.top, 4)
                VStack(alignment: .leading, spacing: 24) {
                    Text(today).font(Design.font(14)).foregroundStyle(Design.muted)
                    Text(homeQuote)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 100, alignment: .leading)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.28), value: homeQuote)
                }.padding(.bottom, 8)
                ReceiverPanel(store: store, openPlayer: { showPlayer = true })
                Spacer(minLength: 0)
                HStack {
                    navigationButton("电台列表", icon: "music.note.list", route: .discovery)
                    Spacer()
                    navigationButton("设置", icon: "gearshape", route: .settings)
                }
            }
            .dynamicTypeSize(.large)
            .padding(.horizontal, 20)
            .frame(width: availableWidth / scale, height: 780)
            .scaleEffect(scale)
            .frame(width: availableWidth, height: availableHeight, alignment: .center)
        }.background(paper.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
        .simultaneousGesture(DragGesture(minimumDistance: 80).onEnded { value in
            let x = value.translation.width, y = value.translation.height
            guard value.startLocation.y < 440 else { return }
            if abs(x) > abs(y) * 1.5 {
                if x > 90 { openDiscovery() } else if x < -90 { openSettings() }
            } else if y < -100 && abs(x) < 70 { showPlayer = true }
        })
    }
    private func navigationButton(_ title: String, icon: String, route: Route) -> some View {
        Button { if route == .discovery { openDiscovery() } else { openSettings() } } label: {
            HStack(spacing: 7) {
                if route == .discovery {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    text(title)
                    Image(systemName: icon)
                } else {
                    Image(systemName: icon)
                    text(title)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
            }
                .font(Design.font(15, "NotoSansSC", .medium))
                .foregroundStyle(ink.opacity(0.75))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(t(title))
            .accessibilityIdentifier(route == .discovery ? "openDiscovery" : "openSettings")
    }
    private func openDiscovery(section: DirectorySection = .search) {
        directorySection = section
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showDiscovery = true }
    }
    private func openSettings() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showSettings = true }
    }
    private func returnHomeGesture(from route: Route) -> some Gesture {
        DragGesture(minimumDistance: 30).onEnded { value in
            let x = value.translation.width, y = value.translation.height
            guard !returningFromDiscovery, abs(x) > 90, abs(x) > abs(y) * 1.5 else { return }
            guard (route == .discovery && x < 0) || (route == .settings && x > 0) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                if route == .discovery { showDiscovery = false } else { showSettings = false }
            }
        }
    }
    private func pageHeader(_ title: String) -> some View {
        HStack(spacing: 14) {
            Button {
                if showDiscovery {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showDiscovery = false }
                } else if showSettings {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { showSettings = false }
                }
            } label: { Image(systemName: "chevron.left").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.plain).background(card, in: Circle()).overlay(Circle().strokeBorder(Design.line)).accessibilityLabel(t("返回首页")).accessibilityIdentifier("backHome")
            text(title).font(Design.font(30, "NotoSansSC", .bold))
            Spacer()
            if title == "设置" { Text("v1.0.0").font(Design.font(12, "SpaceMono")).foregroundStyle(Design.muted) }
        }.padding(.vertical, 8)
    }
    private var discovery: some View {
        GeometryReader { proxy in
            ZStack {
                discoveryList(returnWidth: proxy.size.width)
                    .offset(x: discoveryOffset)
                    .disabled(returningFromDiscovery)
            }.clipped()
        }
    }
    private func discoveryList(returnWidth: CGFloat) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                pageHeader("电台列表")
                directoryTabs
                if directorySection == .favorites {
                    favoritesList(returnWidth: returnWidth)
                } else {
                    searchList(returnWidth: returnWidth)
                }
            }.padding(.horizontal, 20).padding(.bottom, 14)
        }.background(paper.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
    }
    private var directoryTabs: some View {
        HStack(spacing: 0) {
            directoryTab("我的收藏", icon: "star", section: .favorites)
            directoryTab("检索", icon: "magnifyingglass", section: .search)
        }
        .padding(4)
        .background(Design.line.opacity(dark ? 0.18 : 0.55), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Design.line))
    }
    private func directoryTab(_ title: String, icon: String, section: DirectorySection) -> some View {
        let selected = directorySection == section
        return Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { directorySection = section }
        } label: {
            Label(t(title), systemImage: selected && section == .favorites ? "star.fill" : icon)
                .font(Design.font(15, "NotoSansSC", .bold))
                .foregroundStyle(selected ? (dark ? Design.forest : Design.card) : Design.muted)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? (dark ? Design.amber : Design.forest) : .clear, in: RoundedRectangle(cornerRadius: 13))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(section == .favorites ? "favoritesTab" : "searchTab")
    }
    @ViewBuilder private func favoritesList(returnWidth: CGFloat) -> some View {
        let favorites = store.favoriteStations
            text(Design.channelCount(favorites.count, favorites: true, language: language)).font(Design.font(14, "Inter")).foregroundStyle(Design.muted)
        if favorites.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "star").font(.system(size: 34)).foregroundStyle(Design.muted)
                text("还没有收藏的电台").font(Design.font(17, "NotoSansSC", .bold))
                text("可在首页或检索结果中点击五角星收藏。")
                    .font(Design.font(13)).foregroundStyle(Design.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 42)
            .background(card, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
        } else {
            text("最近收藏").font(Design.font(14, "NotoSansSC", .bold)).foregroundStyle(Design.muted)
            LazyVStack(spacing: 0) {
                ForEach(favorites) { station in
                    stationRow(station, returnWidth: returnWidth)
                    if station.id != favorites.last?.id { separator }
                }
            }.background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
        }
    }
    @ViewBuilder private func searchList(returnWidth: CGFloat) -> some View {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Design.muted)
                    TextField(t("搜索台名、频率、城市"), text: $store.query).autocorrectionDisabled().accessibilityIdentifier("stationSearch")
                    if !store.query.isEmpty { Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }.accessibilityLabel(t("清除搜索")) }
                }.padding(.horizontal, 16).frame(minHeight: 50).background(card, in: RoundedRectangle(cornerRadius: 16))
                VStack(spacing: 0) {
                    HStack {
                        text("地区"); Spacer()
                        Picker(t("地区"), selection: $store.region) {
                            text("全部地区").tag(""); ForEach(Region.all) { text($0.name).tag($0.id) }
                        }.labelsHidden().onChange(of: store.region) { store.group = ""; store.city = ""; store.category = "" }
                    }.frame(minHeight: 54)
                    separator
                    filterPicker("省市 / 分组", selection: $store.group, values: store.scoped.map(\.group)).onChange(of: store.group) { store.city = "" }
                    separator
                    filterPicker("城市", selection: $store.city, values: store.scoped.filter { store.group.isEmpty || $0.group == store.group }.map(\.city))
                    separator
                    filterPicker("节目类型", selection: $store.category, values: store.scoped.map(\.category))
                }.pickerStyle(.menu).padding(.horizontal, 18).background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
                let matches = store.filtered
                text(Design.channelCount(matches.count, language: language)).font(Design.font(14, "Inter")).foregroundStyle(Design.muted)
                if matches.isEmpty { text(store.catalogError ?? "没有匹配的电台，请调整搜索或筛选条件。").foregroundStyle(Design.muted).padding(.vertical, 24) }
                ForEach(sections(matches), id: \.key) { section in
                    Text(section.key.split(separator: "·").map { t(String($0).trimmingCharacters(in: .whitespaces)) }.joined(separator: " · "))
                        .font(Design.font(14, "NotoSansSC", .bold)).foregroundStyle(Design.muted)
                    LazyVStack(spacing: 0) {
                        ForEach(section.stations) { station in stationRow(station, returnWidth: returnWidth); if station.id != section.stations.last?.id { separator } }
                    }.background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
                }
    }
    private func filterPicker(_ title: String, selection: Binding<String>, values: [String]) -> some View {
        HStack {
            text(title); Spacer()
            Picker(t(title), selection: selection) { text("全部").tag(""); ForEach(Array(Set(values.filter { !$0.isEmpty })).sorted(by: Search.before), id: \.self) { text($0).tag($0) } }.labelsHidden()
        }.frame(minHeight: 54)
    }
    private func sections(_ stations: [Station]) -> [(key: String, stations: [Station])] {
        var result: [(key: String, stations: [Station])] = []
        for station in stations {
            let group = station.region == "cn" && station.group == "全国" ? "央广及全国广播" : station.group
            let key = station.regionName + (group.isEmpty ? "" : " · " + group)
            if result.last?.key == key { result[result.count - 1].stations.append(station) } else { result.append((key, [station])) }
        }
        return result
    }
    private func stationRow(_ station: Station, returnWidth: CGFloat) -> some View {
        HStack(spacing: 8) {
            Button { selectAndReturn(station, returnWidth: returnWidth) } label: {
                HStack(spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(station.name).font(Design.font(16, "NotoSansSC", .bold)).fixedSize(horizontal: false, vertical: true)
                    Text("\(localizedSubtitle(station)) · \(t(station.category))").font(Design.font(12)).foregroundStyle(Design.muted)
                }
                Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(Design.stationAction("收听", stationName: station.name, language: language))
            Button { store.toggleFavorite(station) } label: {
                Image(systemName: store.isFavorite(station) ? "star.fill" : "star")
                    .font(.title3).foregroundStyle(store.isFavorite(station) ? Design.amber : Design.muted.opacity(0.4))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Design.stationAction(store.isFavorite(station) ? "取消收藏" : "收藏", stationName: station.name, language: language))
            Button { selectAndReturn(station, returnWidth: returnWidth) } label: {
                Image(systemName: store.player.station?.id == station.id && store.player.state == .playing ? "waveform.circle" : "play.circle")
                    .font(.title).frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Design.stationAction("收听", stationName: station.name, language: language))
        }.padding(.horizontal, 14).padding(.vertical, 12).frame(minHeight: 78)
    }
    private func selectAndReturn(_ station: Station, returnWidth: CGFloat) {
        guard !returningFromDiscovery else { return }
        store.select(station)
        returningFromDiscovery = true
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3), completionCriteria: .removed) {
            discoveryOffset = -returnWidth
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showDiscovery = false
                discoveryOffset = 0
                returningFromDiscovery = false
            }
        }
    }
    private func dismissPlayback() {
        guard showPlayer else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { showPlayer = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { playbackOffset = 0 }
    }
    private var playback: some View {
        GeometryReader { proxy in
            let availableWidth = max(1, proxy.size.width)
            let availableHeight = max(1, proxy.size.height)
            let scale = max(0.01, min(1, availableHeight / 730, availableWidth / 350))
            VStack(spacing: 18) {
                HStack {
                    Button(action: dismissPlayback) { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.accessibilityLabel(t("返回")).accessibilityIdentifier("closePlayback")
                    Spacer(); text("现在播放").font(Design.font(14, "NotoSansSC", .bold)).tracking(3); Spacer()
                    Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
                }
                ZStack {
                    Circle().fill(LinearGradient(colors: [Color(hex: 0xF4D393), Design.amber], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 12) {
                        Image("WaveletMark").resizable().scaledToFit().frame(width: 96, height: 90)
                        Text(store.player.state == .playing ? "LIVE" : "RADIO").font(Design.font(13, "SpaceMono", .bold)).tracking(4)
                    }.foregroundStyle(Design.forest)
                }.frame(width: 166, height: 166).accessibilityHidden(true)
                VStack(spacing: 13) {
                    Text(store.player.station?.name.components(separatedBy: CharacterSet(charactersIn: "(（")).first ?? t("尚未选择电台")).font(Design.font(25, "NotoSansSC", .bold)).foregroundStyle(Design.card).lineLimit(2).minimumScaleFactor(0.7)
                    if let station = store.player.station {
                        Text("\(t(station.regionName)) / \(t(station.language)) · \(t(station.category))").font(Design.font(14))
                    }
                    text(store.player.state.rawValue).font(Design.font(13)).foregroundStyle(Design.amber)
                }.multilineTextAlignment(.center).foregroundStyle(Color(hex: 0xB1BBAE))
                if let station = store.player.station {
                    VStack(alignment: .leading, spacing: 8) {
                        text("播放线路").font(Design.font(13, "NotoSansSC", .bold)).foregroundStyle(Color(hex: 0xB1BBAE))
                        HStack {
                        text("线路"); Spacer()
                        Picker(t("线路"), selection: Binding(get: { store.player.line }, set: { store.player.switchLine($0) })) {
                            ForEach(station.streams.indices, id: \.self) { index in text(Design.line(index + 1, format: station.streams[index].format.uppercased(), language: language)).tag(index) }
                        }.labelsHidden().pickerStyle(.menu).tint(Design.amber)
                        }.frame(minHeight: 44)
                    }.padding(18).background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 22))
                    VStack(alignment: .leading, spacing: 0) {
                        text("播放来源").font(Design.font(13, "NotoSansSC", .bold)).foregroundStyle(Color(hex: 0xB1BBAE)).padding(18)
                        sourceLink("查看目录来源", icon: "folder.badge.questionmark", value: station.source)
                        Divider().overlay(.white.opacity(0.12))
                        sourceLink("电台网站", icon: "arrow.up.right.square", value: station.official)
                    }.background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 22))
                }
                if let error = store.player.errorMessage { text(error).font(Design.font(13)).foregroundStyle(Design.amber).lineLimit(2) }
                Spacer(minLength: 0)
            }
            .dynamicTypeSize(.large)
            .padding(.horizontal, 22).padding(.vertical, 8)
            .frame(width: availableWidth / scale, height: availableHeight / scale, alignment: .top)
            .scaleEffect(scale, anchor: .topLeading)
        }
        .background(Design.forest.ignoresSafeArea())
        .foregroundStyle(Design.card)
        .preferredColorScheme(.dark)
        .offset(y: playbackOffset)
        .gesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    guard value.translation.height > 0, value.translation.height > abs(value.translation.width) else { return }
                    playbackOffset = value.translation.height
                }
                .onEnded { value in
                    guard value.translation.height > abs(value.translation.width) else { return }
                    if playbackOffset > 120 || value.predictedEndTranslation.height > 180 {
                        dismissPlayback()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { playbackOffset = 0 }
                    }
                }
        )
    }
    private func sourceLink(_ title: String, icon: String, value: String) -> some View {
        Group {
            if let url = URL(string: value), ["https", "http"].contains(url.scheme ?? "") {
                Link(destination: url) { HStack { text(title); Spacer(); Image(systemName: icon) }.padding(18).frame(minHeight: 54) }.foregroundStyle(Design.amber)
            } else { text("暂无来源信息").font(Design.font(13)).foregroundStyle(Design.muted).padding(18) }
        }
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pageHeader("设置")
                sectionLabel("播放")
                VStack(spacing: 0) {
                    Menu {
                        ForEach([30, 60, 120, 180], id: \.self) { minutes in Button(Design.stopAfter(minutes, language: language)) { store.player.setSleep(minutes: minutes) } }
                        if store.player.sleepDeadline != nil { Button(t("取消定时")) { store.player.cancelSleep() } }
                    } label: { settingRow("睡眠定时", icon: "timer", value: store.player.sleepRemaining ?? "未开启") }
                    separator
                    Toggle(isOn: $autoplay) { Label(t("启动时自动播放"), systemImage: "play") }.padding(18).frame(minHeight: 64)
                }.background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
                text("开启后，点击封面「开始收听」进入首页时，自动播放上次选择的电台。").font(Design.font(12)).foregroundStyle(Design.muted)
                sectionLabel("通用")
                VStack(spacing: 0) {
                    Menu {
                        Picker(t("主题"), selection: $theme) {
                            ForEach(["浅色", "深色", "跟随系统"], id: \.self) { option in text(option).tag(option) }
                        }
                    }
                        label: { settingRow("主题", icon: "sun.max", value: theme) }
                    separator
                    Menu {
                        Picker(t("语言"), selection: $languagePreference) {
                            ForEach(Design.languageOptions, id: \.self) { option in
                                text(option).tag(option)
                            }
                        }
                    }
                        label: { settingRow("语言", icon: "character", value: languagePreference) }
                }.background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
                sectionLabel("关于")
                VStack(spacing: 0) {
                    Button { showAbout = true } label: { settingRow("关于波粒", icon: "info.circle") }
                    separator
                    Button { showUpdate = true } label: { settingRow("检查更新", icon: "arrow.triangle.2.circlepath", value: "开发版") }
                }.background(card, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Design.line))
            }.buttonStyle(.plain).padding(.horizontal, 22).padding(.bottom, 30)
        }.background(paper.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar)
    }
    private func sectionLabel(_ title: String) -> some View { text(title).font(Design.font(16, "NotoSansSC", .bold)).foregroundStyle(Design.muted) }
    private func settingRow(_ title: String, icon: String, value: String = "") -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 24); text(title); Spacer(minLength: 0)
            text(value).foregroundStyle(Design.muted); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Design.muted)
        }.padding(18).frame(minHeight: 64).contentShape(Rectangle())
    }
    private var about: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    secondaryBrandLogo(size: 150)
                    text("打开收音机，听见此刻。").font(Design.font(22, "NotoSansSC", .bold))
                    text("波粒连接各地区的在线广播与电视伴音。节目与音频由对应电台服务商提供。")
                    text("常听记录仅保存在本机。无账号或云同步；播放时电台服务商会接收连接所需的网络信息。")
                    Button(t("清空本机常听记录"), role: .destructive) { confirmClear = true }.frame(minHeight: 44)
                    #if DEBUG
                    text(Design.debugCatalogSummary(store.stations.count, language: language)).font(Design.font(13)).foregroundStyle(Design.muted)
                    #endif
                    text("字体：Noto Sans SC / Inter / Space Mono / Archivo，按 SIL Open Font License 使用。").font(Design.font(12)).foregroundStyle(Design.muted)
                }.padding(24)
            }.navigationTitle(t("关于波粒")).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("完成")) { showAbout = false } } }
        }
        .presentationBackground(Color(uiColor: .systemBackground))
    }
    private func configurePreviewRoute() {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-page"), args.indices.contains(index + 1) else { return }
        switch args[index + 1] {
        case "home": entered = true
        case "discovery": entered = true; showDiscovery = true
        case "favorites": entered = true; showDiscovery = true; directorySection = .favorites
        case "settings": entered = true; showSettings = true
        case "playback": entered = true; showPlayer = true
        default: break
        }
        #endif
    }
}

private struct ReceiverPanel: View {
    @Bindable var store: RadioStore
    let openPlayer: () -> Void
    var coverPreview = false
    @AppStorage("wavelet.language") private var languagePreference = "跟随系统"
    private var language: String { Design.resolvedLanguage(languagePreference) }
    private func text(_ value: String) -> Text { Text(Design.translate(value, language)) }
    private var station: Station? { store.player.station }
    private var channel: String {
        if coverPreview { return "0" }
        return store.stations.firstIndex(where: { $0.id == station?.id }).map { String(format: "%02d", $0 + 1) } ?? "––"
    }
    private var indicator: String {
        switch store.player.state {
        case .ready: Design.translate("准备就绪", language)
        case .connecting: Design.translate("正在连接", language)
        case .buffering: Design.translate("正在缓冲", language)
        case .playing: Design.translate("正在收听", language)
        case .paused: Design.translate("已暂停", language)
        case .failed: Design.translate("连接失败", language)
        }
    }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("WAVELET").font(Design.font(15, "SpaceMono", .bold)).tracking(3); Spacer(minLength: 4)
                Text("SR-01 / DIGITAL RADIO").font(Design.font(9, "SpaceMono")).tracking(1).foregroundStyle(Color(hex: 0x97A28F))
            }
            Button(action: openPlayer) { screen }.buttonStyle(.plain).accessibilityLabel(Design.translate("查看播放状态", language)).accessibilityIdentifier("receiverScreen")
            HStack {
                Button { store.step(-1) } label: { Image(systemName: "backward.end").font(.title).frame(width: 52, height: 52) }.accessibilityLabel(Design.translate("上一台", language))
                Spacer()
                Button { store.player.toggle() } label: {
                    Image(systemName: store.player.state.active ? "pause" : "play").font(.system(size: 28)).foregroundStyle(Design.amber)
                        .frame(width: 70, height: 70).background(Color(hex: 0x222D22), in: Circle()).overlay(Circle().strokeBorder(.white.opacity(0.1)))
                }.accessibilityLabel(Design.translate(store.player.state.active ? "暂停播放" : "开始收听", language)).disabled(station == nil)
                Spacer()
                Button { store.step(1) } label: { Image(systemName: "forward.end").font(.title).frame(width: 52, height: 52) }.accessibilityLabel(Design.translate("下一台", language))
            }.buttonStyle(.plain)
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.1").foregroundStyle(Color(hex: 0x97A28F))
                Slider(value: Binding(get: { store.player.volume }, set: { store.player.volume = $0 }), in: 0...1).tint(Design.amber).accessibilityLabel(Design.translate("音量", language))
                Image(systemName: "speaker.wave.2").foregroundStyle(Color(hex: 0x97A28F))
            }.frame(minHeight: 38)
            Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
            HStack(spacing: 8) {
                Circle().fill(store.player.state == .failed ? .red : Design.amber).frame(width: 7, height: 7)
                text(store.player.state.rawValue).font(Design.font(13)); Spacer(minLength: 0)
                if let station {
                    Button { store.toggleFavorite(station) } label: {
                        Label {
                            text("收藏")
                        } icon: {
                            Image(systemName: store.isFavorite(station) ? "star.fill" : "star")
                        }
                        .foregroundStyle(store.isFavorite(station) ? Design.amber : Color(hex: 0xC4CDBE))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Design.translate(store.isFavorite(station) ? "取消收藏" : "收藏当前电台", language))
                    .accessibilityIdentifier("favoriteCurrentStation")
                }
                if let remaining = store.player.sleepRemaining {
                    Button { store.player.cancelSleep() } label: { Label(remaining, systemImage: "moon").font(Design.font(12, "SpaceMono")) }.accessibilityLabel(Design.translate("取消睡眠定时", language))
                } else {
                    Menu { ForEach([30, 60, 120, 180], id: \.self) { minutes in Button(Design.stopAfter(minutes, language: language)) { store.player.setSleep(minutes: minutes) } } }
                        label: { Label { text("睡眠") } icon: { Image(systemName: "moon") } }
                }
            }.font(Design.font(13)).frame(minHeight: 44).foregroundStyle(Color(hex: 0xC4CDBE))
            if let error = store.player.errorMessage { text(error).font(Design.font(12)).foregroundStyle(Design.amber).lineLimit(2) }
        }.foregroundStyle(Design.card).padding(18).background(Design.forest, in: RoundedRectangle(cornerRadius: 32))
    }
    private var screen: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("INTERNET RADIO"); Spacer(minLength: 4); Text(indicator) }.font(Design.font(10, "SpaceMono", .bold)).tracking(1)
            Rectangle().fill(Design.ink.opacity(0.25)).frame(height: 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .lastTextBaseline, spacing: 10) {
                    Text(coverPreview ? Design.translate("中文/华语", language) : station.map { "\(Design.translate($0.regionName, language)) / \(Design.translate($0.language, language))" } ?? Design.translate("华语广播", language))
                        .font(Design.font(12))
                    Spacer(minLength: 8)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(channel).font(Design.font(32, "Inter")).minimumScaleFactor(0.6).lineLimit(1)
                        Text("CH").font(Design.font(8, "SpaceMono", .bold))
                    }
                }
                if !coverPreview {
                    Text(station?.name ?? Design.translate("选择电台，开始收听", language))
                        .font(Design.font(18, "NotoSansSC", .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            VStack(spacing: 9) {
                HStack { ForEach(["01", "03", "06", "09", "12"], id: \.self) { value in Text(value); if value != "12" { Spacer() } } }.font(Design.font(9, "SpaceMono"))
                GeometryReader { proxy in
                    Canvas { context, size in
                        for tick in 0...36 {
                            let x = CGFloat(tick) / 36 * size.width
                            var line = Path(); line.move(to: CGPoint(x: x, y: tick % 3 == 0 ? 0 : 5)); line.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(line, with: .color(Design.ink.opacity(0.35)), lineWidth: 1)
                        }
                    }
                    Capsule().fill(Design.forest).frame(width: 2, height: 25).offset(x: proxy.size.width * needlePosition, y: -4)
                }.frame(height: 18)
            }.accessibilityHidden(true)
            HStack {
                text(coverPreview ? "综合" : station?.category ?? "华语广播"); Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in Text(context.date, format: .dateTime.hour().minute()).font(Design.font(12, "SpaceMono")) }
            }.font(Design.font(12)).padding(.top, 2)
        }.foregroundStyle(Color(hex: 0x493B1F)).padding(16)
            .background(LinearGradient(colors: [Color(hex: 0xF3D293), Design.amber], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 20))
    }
    private var needlePosition: Double {
        if coverPreview { return 0.02 }
        guard let index = store.stations.firstIndex(where: { $0.id == station?.id }) else { return 0.45 }
        return 0.02 + Double(index) / Double(max(1, store.stations.count - 1)) * 0.94
    }
}

#Preview { ContentView(store: RadioStore()) }
