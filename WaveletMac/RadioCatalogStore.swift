import Combine
import Foundation

@MainActor
final class RadioCatalogStore: ObservableObject {
    let player: PlaybackEngine
    @Published private(set) var stations: [Station] = []
    @Published private(set) var loadError: String?
    @Published var searchText = ""
    @Published var region = ""
    @Published var group = ""
    @Published var city = ""
    @Published var category = ""
    @Published var selectedStationID: Station.ID?
    @Published private(set) var favoriteIDs: [Station.ID]
    @Published private(set) var languagePreference: String
    @Published private(set) var themePreference: String
    @Published var autoplayEnabled: Bool {
        didSet { defaults.set(autoplayEnabled, forKey: autoplayKey) }
    }

    private let favoritesKey = "wavelet.mac.favoriteStationIDs.v1"
    private let languageKey = "wavelet.mac.language.v1"
    private let themeKey = "wavelet.mac.theme.v1"
    private let autoplayKey = "wavelet.mac.autoplay.v1"
    private let defaults: UserDefaults
    private var sourceStations: [Station] = []
    private var translations: StationTranslationCatalog?

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        player = PlaybackEngine(defaults: defaults)
        favoriteIDs = defaults.stringArray(forKey: favoritesKey) ?? []
        languagePreference = defaults.string(forKey: languageKey) ?? "跟随系统"
        themePreference = defaults.string(forKey: themeKey) ?? "跟随系统"
        autoplayEnabled = defaults.bool(forKey: autoplayKey)
        do {
            let catalog = try StationCatalog.load(bundle: bundle)
            sourceStations = catalog.stations.sorted(by: Search.directoryOrder)
            translations = try? StationTranslationCatalog.load(bundle: bundle)
            stations = localizedStations(for: languagePreference)
            favoriteIDs = FavoriteStations.sanitized(
                favoriteIDs,
                validIDs: Set(stations.map(\.id))
            )
            selectedStationID = stations.first?.id
            if let station = stations.first {
                player.restore(station, line: player.savedLine(for: station.id))
                if autoplayEnabled { player.play() }
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    var scopedStations: [Station] {
        stations.filter { region.isEmpty || $0.region == region }
    }

    var filteredStations: [Station] {
        scopedStations.filter { station in
            (group.isEmpty || station.group == group) &&
            (city.isEmpty || station.city == city) &&
            (category.isEmpty || station.category == category) &&
            Search.matches(searchText, station: station)
        }
    }

    var selectedStation: Station? {
        guard let selectedStationID else { return nil }
        return stations.first { $0.id == selectedStationID }
    }

    var favoriteStations: [Station] {
        let byID = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, $0) })
        return favoriteIDs.compactMap { byID[$0] }
    }

    func select(_ station: Station) {
        selectedStationID = station.id
        player.select(station, line: player.savedLine(for: station.id))
    }

    func step(_ delta: Int) {
        let list = filteredStations.isEmpty ? stations : filteredStations
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == player.station?.id } ?? (delta > 0 ? -1 : 0)
        select(list[(current + delta + list.count) % list.count])
    }

    func setLanguage(_ value: String) {
        languagePreference = value
        defaults.set(value, forKey: languageKey)
        stations = localizedStations(for: value)
        group = ""
        city = ""
        category = ""
        if let currentID = player.station?.id,
           let station = stations.first(where: { $0.id == currentID }) {
            selectedStationID = currentID
            player.updateStationMetadata(station)
        }
    }

    func setTheme(_ value: String) {
        themePreference = value
        defaults.set(value, forKey: themeKey)
    }

    private func localizedStations(for preference: String) -> [Station] {
        let language = Self.resolvedLanguage(preference)
        return sourceStations.map { source in
            let station = translations?.localized(source, appLanguage: language) ?? source
            guard station.region == "hk" else { return station }
            // Match Macau's region grouping; broadcaster ownership is not a geographic group.
            return Station(
                id: station.id, name: station.name, region: station.region,
                group: MacLocalization.text("香港", language: language), city: "",
                category: station.category, language: station.language,
                aliases: station.aliases, official: station.official,
                source: station.source, streams: station.streams
            )
        }
    }

    var interfaceLanguage: String { Self.resolvedLanguage(languagePreference) }
    var interfaceLocale: Locale {
        let identifiers = ["简体中文": "zh-Hans", "繁體中文": "zh-Hant", "英文": "en", "日文": "ja", "韩文": "ko", "泰文": "th", "西班牙语": "es", "阿拉伯文": "ar"]
        return Locale(identifier: identifiers[interfaceLanguage] ?? "en")
    }

    func text(_ key: String) -> String {
        MacLocalization.text(key, language: interfaceLanguage)
    }

    func lineTitle(_ index: Int, format: String) -> String {
        "\(text("线路")) \(index + 1) · \(format.uppercased())"
    }

    func subtitle(_ station: Station) -> String {
        [text(station.regionName), station.group, station.city]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: " · ")
    }

    static func resolvedLanguage(_ preference: String) -> String {
        guard preference == "跟随系统" else { return preference }
        let identifier = (Locale.preferredLanguages.first ?? Locale.current.identifier)
            .lowercased().replacingOccurrences(of: "_", with: "-")
        if identifier.hasPrefix("zh") {
            return ["hant", "-tw", "-hk", "-mo"].contains(where: identifier.contains) ? "繁體中文" : "简体中文"
        }
        if identifier.hasPrefix("ja") { return "日文" }
        if identifier.hasPrefix("ko") { return "韩文" }
        if identifier.hasPrefix("th") { return "泰文" }
        if identifier.hasPrefix("es") { return "西班牙语" }
        if identifier.hasPrefix("ar") { return "阿拉伯文" }
        return "英文"
    }

    func toggleFavorite(_ station: Station, defaults: UserDefaults = .standard) {
        favoriteIDs = FavoriteStations.toggling(station.id, in: favoriteIDs)
        defaults.set(favoriteIDs, forKey: favoritesKey)
    }

    func isFavorite(_ station: Station) -> Bool {
        favoriteIDs.contains(station.id)
    }
}

/// Interface translations are separate from catalog metadata. Preference values
/// stay stable so existing saved settings continue to work in every language.
enum MacLocalization {
    static let languages = ["英文", "日文", "韩文", "泰文", "西班牙语", "阿拉伯文"]
    static let nativeLanguageNames = ["繁體中文": "繁體中文", "简体中文": "简体中文", "英文": "English", "日文": "日本語", "韩文": "한국어", "泰文": "ไทย", "西班牙语": "Español", "阿拉伯文": "العربية"]
    // Each row follows languages above: English, Japanese, Korean, Thai, Spanish, Arabic.
    static let translations: [String: [String]] = [
        "播放来源": ["Source", "配信元", "재생 출처", "แหล่งที่มา", "Fuente", "المصدر"],
        "查看目录来源": ["View directory source", "配信元を確認", "목록 출처 보기", "ดูแหล่งข้อมูลสถานี", "Ver fuente del directorio", "عرض مصدر الدليل"],
        "电台网站": ["Station website", "放送局サイト", "방송국 웹사이트", "เว็บไซต์สถานี", "Sitio de la emisora", "موقع المحطة"],
        "暂无来源信息": ["No source information", "配信元情報なし", "출처 정보 없음", "ไม่มีข้อมูลแหล่งที่มา", "Sin información de fuente", "لا توجد معلومات مصدر"],
        "最小化": ["Minimize", "最小化", "최소화", "ย่อหน้าต่าง", "Minimizar", "تصغير"],
        "中国大陆": ["Mainland China", "中国本土", "중국 본토", "จีนแผ่นดินใหญ่", "China continental", "الصين القارية"],
        "香港": ["Hong Kong", "香港", "홍콩", "ฮ่องกง", "Hong Kong", "هونغ كونغ"],
        "澳门": ["Macao", "マカオ", "마카오", "มาเก๊า", "Macao", "ماكاو"],
        "台湾": ["Taiwan", "台湾", "대만", "ไต้หวัน", "Taiwán", "تايوان"],
        "美国": ["United States", "アメリカ", "미국", "สหรัฐอเมริกา", "Estados Unidos", "الولايات المتحدة"],
        "新加坡": ["Singapore", "シンガポール", "싱가포르", "สิงคโปร์", "Singapur", "سنغافورة"],
        "马来西亚": ["Malaysia", "マレーシア", "말레이시아", "มาเลเซีย", "Malasia", "ماليزيا"],
        "日本": ["Japan", "日本", "일본", "ญี่ปุ่น", "Japón", "اليابان"],
        "其他地区": ["Other regions", "その他の地域", "기타 지역", "ภูมิภาคอื่น", "Otras regiones", "مناطق أخرى"],
        "电视伴音": ["TV audio", "テレビ音声", "TV 오디오", "เสียงทีวี", "Audio de TV", "صوت التلفزيون"],
        "我的收藏": ["Favorites", "お気に入り", "즐겨찾기", "รายการโปรด", "Favoritos", "المفضلة"],
        "电台列表": ["Stations", "放送局一覧", "방송국 목록", "สถานีวิทยุ", "Emisoras", "المحطات"],
        "设置": ["Settings", "設定", "설정", "การตั้งค่า", "Ajustes", "الإعدادات"],
        "播放线路": ["Stream", "配信回線", "스트림", "สตรีม", "Fuente", "البث"],
        "线路": ["Stream", "回線", "스트림", "สตรีม", "Fuente", "البث"],
        "暂无线路": ["No streams", "回線なし", "스트림 없음", "ไม่มีสตรีม", "Sin fuentes", "لا يوجد بث"],
        "准备就绪": ["Ready", "準備完了", "준비 완료", "พร้อม", "Listo", "جاهز"],
        "正在连接": ["Connecting", "接続中", "연결 중", "กำลังเชื่อมต่อ", "Conectando", "جارٍ الاتصال"],
        "正在缓冲": ["Buffering", "バッファリング中", "버퍼링 중", "กำลังบัฟเฟอร์", "Cargando", "جارٍ التخزين المؤقت"],
        "正在收听": ["Playing", "再生中", "재생 중", "กำลังเล่น", "Reproduciendo", "قيد التشغيل"],
        "已暂停": ["Paused", "一時停止", "일시 정지", "หยุดชั่วคราว", "En pausa", "متوقف مؤقتًا"],
        "连接失败": ["Connection failed", "接続失敗", "연결 실패", "เชื่อมต่อไม่สำเร็จ", "Error de conexión", "فشل الاتصال"],
        "收藏": ["Favorite", "お気に入り", "즐겨찾기", "รายการโปรด", "Favorito", "المفضلة"],
        "睡眠": ["Sleep", "スリープ", "취침", "ตั้งเวลาปิด", "Temporizador", "مؤقت النوم"],
        "睡眠定时": ["Sleep timer", "スリープタイマー", "취침 타이머", "ตั้งเวลาปิด", "Temporizador", "مؤقت النوم"],
        "未设置": ["Not set", "未設定", "설정 안 됨", "ยังไม่ได้ตั้งค่า", "Sin configurar", "غير مضبوط"],
        "取消定时": ["Cancel timer", "タイマーを解除", "타이머 취소", "ยกเลิกเวลา", "Cancelar temporizador", "إلغاء المؤقت"],
        "分钟后停止": ["Stop in %d minutes", "%d 分後に停止", "%d분 후 중지", "หยุดใน %d นาที", "Detener en %d minutos", "إيقاف بعد %d دقيقة"],
        "音量": ["Volume", "音量", "음량", "ระดับเสียง", "Volumen", "مستوى الصوت"],
        "播放": ["Playback", "再生", "재생", "การเล่น", "Reproducción", "التشغيل"],
        "开始收听": ["Play", "再生", "재생", "เล่น", "Reproducir", "تشغيل"],
        "暂停播放": ["Pause", "一時停止", "일시 정지", "หยุดชั่วคราว", "Pausar", "إيقاف مؤقت"],
        "暂停": ["Pause", "一時停止", "일시 정지", "หยุดชั่วคราว", "Pausar", "إيقاف مؤقت"],
        "通用": ["General", "一般", "일반", "ทั่วไป", "General", "عام"],
        "主题": ["Appearance", "外観", "테마", "ธีม", "Apariencia", "المظهر"],
        "语言": ["Language", "言語", "언어", "ภาษา", "Idioma", "اللغة"],
        "浅色": ["Light", "ライト", "라이트", "สว่าง", "Claro", "فاتح"],
        "深色": ["Dark", "ダーク", "다크", "มืด", "Oscuro", "داكن"],
        "跟随系统": ["System", "システム", "시스템", "ตามระบบ", "Sistema", "النظام"],
        "启动时自动播放": ["Play automatically at launch", "起動時に自動再生", "시작 시 자동 재생", "เล่นอัตโนมัติเมื่อเปิดแอป", "Reproducir al iniciar", "التشغيل تلقائيًا عند البدء"],
        "地区": ["Region", "地域", "지역", "ภูมิภาค", "Región", "المنطقة"],
        "全部地区": ["All regions", "すべての地域", "모든 지역", "ทุกภูมิภาค", "Todas las regiones", "كل المناطق"],
        "省市 / 分组": ["Province / Group", "都道府県 / グループ", "시도 / 그룹", "จังหวัด / กลุ่ม", "Provincia / Grupo", "المحافظة / المجموعة"],
        "城市": ["City", "都市", "도시", "เมือง", "Ciudad", "المدينة"],
        "节目类型": ["Category", "ジャンル", "분류", "หมวดหมู่", "Categoría", "الفئة"],
        "全部": ["All", "すべて", "전체", "ทั้งหมด", "Todos", "الكل"],
        "搜索电台、地区、城市或分类": ["Search stations, regions, cities or categories", "放送局・地域・都市・ジャンルを検索", "방송국, 지역, 도시, 분류 검색", "ค้นหาสถานี ภูมิภาค เมือง หรือหมวดหมู่", "Buscar emisoras, regiones, ciudades o categorías", "البحث عن المحطات أو المناطق أو المدن أو الفئات"],
        "个电台": ["%d stations", "%d 局", "방송국 %d개", "%d สถานี", "%d emisoras", "%d محطة"],
        "还没有收藏": ["No favorites yet", "お気に入りはまだありません", "즐겨찾기가 없습니다", "ยังไม่มีรายการโปรด", "Aún no hay favoritos", "لا توجد مفضلة بعد"],
        "没有匹配的电台": ["No matching stations", "一致する放送局がありません", "일치하는 방송국이 없습니다", "ไม่พบสถานีที่ตรงกัน", "No hay emisoras coincidentes", "لا توجد محطات مطابقة"],
        "选择电台，开始收听": ["Choose a station to listen", "放送局を選んで聴く", "방송국을 선택하세요", "เลือกสถานีเพื่อฟัง", "Elige una emisora", "اختر محطة للاستماع"],
        "华语广播": ["Chinese radio", "中国語放送", "중국어 방송", "วิทยุภาษาจีน", "Radio en chino", "إذاعة صينية"],
        "现在播放": ["Now playing", "再生中", "지금 재생 중", "กำลังเล่น", "Reproduciendo", "قيد التشغيل"],
        "尚未选择电台": ["No station selected", "放送局未選択", "선택된 방송국 없음", "ยังไม่ได้เลือกสถานี", "Ninguna emisora seleccionada", "لم يتم اختيار محطة"],
        "查看播放状态": ["Show playback status", "再生状態を表示", "재생 상태 보기", "ดูสถานะการเล่น", "Ver estado de reproducción", "عرض حالة التشغيل"],
        "关闭": ["Close", "閉じる", "닫기", "ปิด", "Cerrar", "إغلاق"],
        "无法加载电台目录": ["Unable to load stations", "放送局を読み込めません", "방송국을 불러올 수 없습니다", "ไม่สามารถโหลดสถานี", "No se pueden cargar las emisoras", "تعذر تحميل المحطات"],
        "未知错误": ["Unknown error", "不明なエラー", "알 수 없는 오류", "ข้อผิดพลาดที่ไม่ทราบสาเหตุ", "Error desconocido", "خطأ غير معروف"],
        "上一台": ["Previous station", "前の放送局", "이전 방송국", "สถานีก่อนหน้า", "Emisora anterior", "المحطة السابقة"],
        "下一台": ["Next station", "次の放送局", "다음 방송국", "สถานีถัดไป", "Emisora siguiente", "المحطة التالية"],
        "打开菜单": ["Open menu", "メニューを開く", "메뉴 열기", "เปิดเมนู", "Abrir menú", "فتح القائمة"],
        "显示主窗口": ["Show radio", "ラジオを表示", "라디오 표시", "แสดงวิทยุ", "Mostrar radio", "عرض الراديو"],
        "退出 Wavelet": ["Quit Wavelet", "Wavelet を終了", "Wavelet 종료", "ออกจาก Wavelet", "Salir de Wavelet", "إنهاء Wavelet"],
        "网络已断开。恢复网络后，请点击播放重连。": ["Network disconnected. Press play after reconnecting.", "ネットワーク切断。再接続後に再生してください。", "네트워크 연결이 끊겼습니다. 연결 후 재생하세요.", "เครือข่ายขาดการเชื่อมต่อ กดเล่นเมื่อเชื่อมต่ออีกครั้ง", "Red desconectada. Pulsa reproducir tras reconectar.", "انقطع اتصال الشبكة. اضغط تشغيل بعد إعادة الاتصال."],
        "网络不可用，请连接网络后重试。": ["No network. Connect and try again.", "ネットワークに接続して再試行してください。", "네트워크 연결 후 다시 시도하세요.", "ไม่มีเครือข่าย โปรดเชื่อมต่อและลองอีกครั้ง", "Sin red. Conéctate e inténtalo de nuevo.", "الشبكة غير متاحة. اتصل وحاول مجددًا."],
        "电台暂无可用线路。": ["This station has no available streams.", "この放送局には利用可能な回線がありません。", "사용 가능한 스트림이 없습니다.", "สถานีนี้ไม่มีสตรีมที่ใช้ได้", "Esta emisora no tiene fuentes disponibles.", "لا يوجد بث متاح لهذه المحطة."],
        "连接未成功，可能受网络或地区限制。请重试或手动切换线路。": ["Connection failed. Retry or switch streams; network or regional restrictions may apply.", "接続失敗。ネットワークや地域制限の可能性があります。再試行または回線を変更してください。", "연결 실패. 네트워크 또는 지역 제한일 수 있습니다. 다시 시도하거나 스트림을 변경하세요.", "เชื่อมต่อไม่สำเร็จ อาจมีข้อจำกัดเครือข่ายหรือภูมิภาค โปรดลองอีกครั้งหรือเปลี่ยนสตรีม", "Conexión fallida. Reintenta o cambia de fuente; puede haber restricciones de red o región.", "فشل الاتصال. حاول مجددًا أو غيّر البث؛ قد توجد قيود على الشبكة أو المنطقة."],
        "Mac 已进入睡眠。唤醒后请手动点击播放。": ["Mac went to sleep. Press play after waking.", "Mac がスリープしました。復帰後に再生してください。", "Mac이 잠자기 상태입니다. 깨운 후 재생하세요.", "Mac เข้าสู่โหมดพัก กดเล่นหลังปลุกเครื่อง", "El Mac entró en reposo. Pulsa reproducir al despertar.", "دخل Mac في وضع السكون. اضغط تشغيل بعد الاستيقاظ."],
        "Mac 已唤醒。为避免意外发声，请手动点击播放。": ["Mac woke up. Press play to resume audio.", "Mac が復帰しました。再生ボタンで再開してください。", "Mac이 깨어났습니다. 재생 버튼으로 계속하세요.", "Mac ตื่นแล้ว กดเล่นเพื่อฟังต่อ", "El Mac despertó. Pulsa reproducir para continuar.", "استيقظ Mac. اضغط تشغيل لاستئناف الصوت."],
        "音频输出设备已变化。请确认输出设备后手动继续播放。": ["Audio output changed. Check the device, then resume playback.", "音声出力が変更されました。機器を確認して再生を再開してください。", "오디오 출력이 변경되었습니다. 장치를 확인한 후 재생하세요.", "อุปกรณ์เสียงเปลี่ยนแล้ว ตรวจสอบอุปกรณ์แล้วเล่นต่อ", "La salida de audio cambió. Comprueba el dispositivo y reanuda.", "تغيّر مخرج الصوت. تحقق من الجهاز ثم استأنف التشغيل."]
    ]

    static func text(_ key: String, language: String) -> String {
        if let nativeName = nativeLanguageNames[key] { return nativeName }
        if language == "繁體中文" {
            return key.applyingTransform(StringTransform("Simplified-Traditional"), reverse: false) ?? key
        }
        guard let index = languages.firstIndex(of: language), let row = translations[key] else { return key }
        return row[index]
    }

    static func format(_ key: String, count: Int, language: String) -> String {
        let template = text(key, language: language)
        if template.contains("%d") { return String(format: template, count) }
        return "\(count) \(template)"
    }
}
