import Combine
import Foundation

@MainActor
final class RadioCatalogStore: ObservableObject {
    let player: PlaybackEngine
    @Published private(set) var stations: [Station] = []
    @Published private(set) var loadError: String?
    @Published private(set) var lastImportDuplicateCount = 0
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
    private let migrationKey = "wavelet.mac.personalCatalogMigration.v1"
    private let lastStationKey = "wavelet.mac.lastStationID.v1"
    private let defaults: UserDefaults
    private let repository: PersonalStationRepository
    private var sourceStations: [Station] = []

    init(
        defaults: UserDefaults = .standard,
        repository: PersonalStationRepository = PersonalStationRepository()
    ) {
        self.defaults = defaults
        self.repository = repository
        player = PlaybackEngine(defaults: defaults)
        favoriteIDs = defaults.stringArray(forKey: favoritesKey) ?? []
        languagePreference = defaults.string(forKey: languageKey) ?? "跟随系统"
        themePreference = defaults.string(forKey: themeKey) ?? "跟随系统"
        autoplayEnabled = defaults.bool(forKey: autoplayKey)
        do {
            let data = try repository.load()
            if data == nil, !defaults.bool(forKey: migrationKey) {
                try repository.backupLegacyPreferences(defaults)
                retireLegacyStationPreferences()
                defaults.set(true, forKey: migrationKey)
            }
            if let data { sourceStations = try PersonalCatalog.decode(data) }
            stations = sourceStations.sorted(by: Search.directoryOrder)
            favoriteIDs = FavoriteStations.sanitized(favoriteIDs, validIDs: Set(stations.map(\.id)))
            defaults.set(favoriteIDs, forKey: favoritesKey)
            restoreLastStation()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func retireLegacyStationPreferences() {
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: lastStationKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("wavelet.mac.line.") {
            defaults.removeObject(forKey: key)
        }
        favoriteIDs = []
    }

    private func restoreLastStation() {
        guard !stations.isEmpty else {
            selectedStationID = nil
            return
        }
        let savedID = defaults.string(forKey: lastStationKey)
        let station = stations.first { $0.id == savedID } ?? stations[0]
        selectedStationID = station.id
        player.restore(station, line: player.savedLine(for: station.id))
        if autoplayEnabled { player.play() }
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

    var availableRegions: [(value: String, label: String)] {
        let values = Set(stations.map(\.region).filter { !$0.isEmpty })
        return values.sorted(by: Search.before).map { value in
            (value, Region.all.first { $0.id == value }?.name ?? value)
        }
    }

    var availableGroups: [String] {
        Array(Set(scopedStations.map(\.group).filter { !$0.isEmpty })).sorted(by: Search.before)
    }

    var availableCities: [String] {
        Array(Set(scopedStations.filter { group.isEmpty || $0.group == group }.map(\.city).filter { !$0.isEmpty }))
            .sorted(by: Search.before)
    }

    var availableCategories: [String] {
        let scoped = scopedStations.filter { group.isEmpty || $0.group == group }
        return Array(Set(scoped.filter { city.isEmpty || $0.city == city }.map(\.category).filter { !$0.isEmpty }))
            .sorted(by: Search.before)
    }

    func play(_ station: Station) {
        guard sourceStations.contains(where: { $0.id == station.id }) else { return }
        selectedStationID = station.id
        defaults.set(station.id, forKey: lastStationKey)
        player.select(station, line: player.savedLine(for: station.id))
    }

    func step(_ delta: Int) {
        let list = filteredStations.isEmpty ? stations : filteredStations
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == player.station?.id } ?? (delta > 0 ? -1 : 0)
        play(list[(current + delta + list.count) % list.count])
    }

    func setLanguage(_ value: String) {
        languagePreference = value
        defaults.set(value, forKey: languageKey)
    }

    func setTheme(_ value: String) {
        themePreference = value
        defaults.set(value, forKey: themeKey)
    }

    var interfaceLanguage: String { Self.resolvedLanguage(languagePreference) }
    var interfaceLocale: Locale {
        let identifiers = ["简体中文": "zh-Hans", "繁體中文": "zh-Hant", "英文": "en", "日文": "ja", "韩文": "ko", "泰文": "th", "西班牙语": "es", "阿拉伯文": "ar"]
        return Locale(identifier: identifiers[interfaceLanguage] ?? "en")
    }

    func text(_ key: String) -> String {
        MacLocalization.text(key, language: interfaceLanguage)
    }

    func countText(_ key: String, _ count: Int) -> String {
        MacLocalization.format(key, count: count, language: interfaceLanguage)
    }

    func exportStations() throws -> Data {
        try PersonalCatalog.encode(sourceStations)
    }

    func errorMessage(for error: Error) -> String {
        guard let failure = error as? PersonalCatalog.Failure else { return error.localizedDescription }
        switch failure {
        case let .missingRequiredField(field):
            return "\(text("请填写必填项"))：\(text(field))。"
        case let .httpStatus(code):
            return String(format: text("下载失败（HTTP %d），请检查文件地址。"), code)
        default:
            return text(failure.errorDescription ?? "未知错误")
        }
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

    func toggleFavorite(_ station: Station) {
        guard sourceStations.contains(where: { $0.id == station.id }) else { return }
        favoriteIDs = FavoriteStations.toggling(station.id, in: favoriteIDs)
        defaults.set(favoriteIDs, forKey: favoritesKey)
    }

    func isFavorite(_ station: Station) -> Bool {
        favoriteIDs.contains(station.id)
    }

    @discardableResult
    func addStation(
        name: String, region: String, url: String, city: String,
        category: String, language: String, aliases: [String], source: String, group: String
    ) throws -> PersonalCatalog.ImportResult {
        let station = try PersonalCatalog.makeStation(
            name: name, region: region, url: url, city: city,
            category: category, language: language, aliases: aliases,
            source: source, group: group
        )
        return try importStations(PersonalCatalog.encode([station]))
    }

    @discardableResult
    func importStations(_ data: Data) throws -> PersonalCatalog.ImportResult {
        let incoming = try PersonalCatalog.decode(data)
        let isRecovering = loadError != nil
        let merged = PersonalCatalog.merge(incoming, into: isRecovering ? [] : sourceStations)
        lastImportDuplicateCount = merged.duplicates
        guard merged.added > 0 || isRecovering else { return merged }

        let encoded = try PersonalCatalog.encode(merged.stations)
        if isRecovering { try repository.recover(with: encoded) }
        else { try repository.save(encoded) }
        let wasEmpty = sourceStations.isEmpty
        sourceStations = merged.stations.sorted(by: Search.directoryOrder)
        stations = sourceStations
        loadError = nil
        if wasEmpty, let first = sourceStations.first, player.station == nil {
            selectedStationID = first.id
            defaults.set(first.id, forKey: lastStationKey)
            player.restore(first, line: 0)
        }
        return merged
    }

    func deleteStation(_ station: Station) throws {
        let remaining = sourceStations.filter { $0.id != station.id }
        let encoded = try PersonalCatalog.encode(remaining)
        try repository.save(encoded)

        sourceStations = remaining
        stations = remaining
        favoriteIDs.removeAll { $0 == station.id }
        defaults.set(favoriteIDs, forKey: favoritesKey)
        defaults.removeObject(forKey: "wavelet.mac.line.\(station.id).v1")
        if defaults.string(forKey: lastStationKey) == station.id {
            defaults.removeObject(forKey: lastStationKey)
        }
        if player.station?.id == station.id { player.clearStation() }
        if selectedStationID == station.id { selectedStationID = nil }
        resetInvalidFilters()
    }

    func clearAllStations() throws {
        try repository.remove()
        player.clearStation()
        sourceStations = []
        stations = []
        favoriteIDs = []
        selectedStationID = nil
        searchText = ""
        region = ""
        group = ""
        city = ""
        category = ""
        lastImportDuplicateCount = 0
        loadError = nil
        defaults.removeObject(forKey: favoritesKey)
        defaults.removeObject(forKey: lastStationKey)
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("wavelet.mac.line.") {
            defaults.removeObject(forKey: key)
        }
    }

    func resetInvalidFilters() {
        if !region.isEmpty, !availableRegions.contains(where: { $0.value == region }) { region = "" }
        if !group.isEmpty, !availableGroups.contains(group) { group = "" }
        if !city.isEmpty, !availableCities.contains(city) { city = "" }
        if !category.isEmpty, !availableCategories.contains(category) { category = "" }
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
        "浅色": ["Light", "ライト", "라이트", "สว่าง", "Claro", "فاتح"],
        "深色": ["Dark", "ダーク", "다크", "มืด", "Oscuro", "داكن"],
        "跟随系统": ["System", "システム", "시스템", "ตามระบบ", "Sistema", "النظام"],
        "启动时自动播放": ["Play automatically at launch", "起動時に自動再生", "시작 시 자동 재생", "เล่นอัตโนมัติเมื่อเปิดแอป", "Reproducir al iniciar", "التشغيل تلقائيًا عند البدء"],
        "地区": ["Region", "地域", "지역", "ภูมิภาค", "Región", "المنطقة"],
        "全部地区": ["All regions", "すべての地域", "모든 지역", "ทุกภูมิภาค", "Todas las regiones", "كل المناطق"],
        "省市 / 分组": ["Province / Group", "都道府県 / グループ", "시도 / 그룹", "จังหวัด / กลุ่ม", "Provincia / Grupo", "المحافظة / المجموعة"],
        "城市": ["City", "都市", "도시", "เมือง", "Ciudad", "المدينة"],
        "全部": ["All", "すべて", "전체", "ทั้งหมด", "Todos", "الكل"],
        "搜索电台、地区、城市或分类": ["Search stations, regions, cities or categories", "放送局・地域・都市・ジャンルを検索", "방송국, 지역, 도시, 분류 검색", "ค้นหาสถานี ภูมิภาค เมือง หรือหมวดหมู่", "Buscar emisoras, regiones, ciudades o categorías", "البحث عن المحطات أو المناطق أو المدن أو الفئات"],
        "个电台": ["%d stations", "%d 局", "방송국 %d개", "%d สถานี", "%d emisoras", "%d محطة"],
        "还没有收藏": ["No favorites yet", "お気に入りはまだありません", "즐겨찾기가 없습니다", "ยังไม่มีรายการโปรด", "Aún no hay favoritos", "لا توجد مفضلة بعد"],
        "没有匹配的电台": ["No matching stations", "一致する放送局がありません", "일치하는 방송국이 없습니다", "ไม่พบสถานีที่ตรงกัน", "No hay emisoras coincidentes", "لا توجد محطات مطابقة"],
        "选择电台，开始收听": ["Choose a station to listen", "放送局を選んで聴く", "방송국을 선택하세요", "เลือกสถานีเพื่อฟัง", "Elige una emisora", "اختر محطة للاستماع"],
        "电台之声": ["The Sound of Radio", "ラジオの音", "라디오의 소리", "เสียงของวิทยุ", "El sonido de la radio", "صوت الراديو"],
        "电台之声 · 随时相伴": ["The sound of radio · always with you", "ラジオの音 · いつもあなたと", "라디오의 소리 · 언제나 함께", "เสียงของวิทยุ · อยู่เคียงข้างคุณเสมอ", "El sonido de la radio · siempre contigo", "صوت الراديو · يرافقك دائمًا"],
        "导入您的电台": ["Import Your Stations", "放送局を読み込む", "나만의 방송국 가져오기", "นำเข้าสถานีของคุณ", "Importa tus emisoras", "استورد محطاتك"],
        "添加或导入你的第一个电台": ["Add or import your first station", "最初の放送局を追加または読み込む", "첫 방송국을 추가하거나 가져오세요", "เพิ่มหรือนำเข้าสถานีแรกของคุณ", "Añade o importa tu primera emisora", "أضف محطتك الأولى أو استوردها"],
        "个人电台": ["Personal Stations", "マイラジオ", "개인 방송국", "สถานีส่วนตัว", "Emisoras personales", "محطاتك الشخصية"],
        "个人电台文件无法读取，请导入有效的 JSON 文件恢复；原文件会保留备份。": ["The personal station file could not be read. Import a valid JSON file to recover it; the original will be backed up.", "個人放送局ファイルを読み込めません。有効な JSON ファイルを読み込んで復元してください。元のファイルはバックアップされます。", "개인 방송국 파일을 읽을 수 없습니다. 유효한 JSON 파일을 가져와 복구하세요. 원본은 백업됩니다.", "อ่านไฟล์สถานีส่วนตัวไม่ได้ โปรดนำเข้า JSON ที่ถูกต้องเพื่อกู้คืน โดยจะสำรองไฟล์เดิมไว้", "No se pudo leer el archivo de emisoras. Importa un JSON válido para recuperarlo; se guardará una copia del original.", "تعذرت قراءة ملف المحطات الشخصية. استورد ملف JSON صالحًا للاستعادة؛ وسيُحتفظ بنسخة احتياطية من الملف الأصلي."],
        "个人电台保存于本机，不需要账号或云同步。请仅添加你有权收听的音源。": ["Personal stations are stored on this Mac. No account or cloud sync is used. Add only streams you are authorized to listen to.", "個人の放送局はこの Mac に保存されます。アカウントやクラウド同期は不要です。聴取が許可された音源のみ追加してください。", "개인 방송국은 이 Mac에 저장됩니다. 계정이나 클라우드 동기화는 사용하지 않습니다. 청취 권한이 있는 스트림만 추가하세요.", "สถานีส่วนตัวจะบันทึกไว้บน Mac เครื่องนี้ ไม่ใช้บัญชีหรือคลาวด์ โปรดเพิ่มเฉพาะสตรีมที่คุณมีสิทธิ์ฟัง", "Las emisoras personales se guardan en este Mac. No se usa cuenta ni sincronización en la nube. Añade solo fuentes que tengas derecho a escuchar.", "تُحفظ محطاتك الشخصية على هذا الـ Mac، دون حساب أو مزامنة سحابية. أضف فقط البثوث التي يحق لك الاستماع إليها."],
        "添加电台": ["Add Station", "放送局を追加", "방송국 추가", "เพิ่มสถานี", "Añadir emisora", "إضافة محطة"],
        "电台名称": ["Station name", "放送局名", "방송국 이름", "ชื่อสถานี", "Nombre de la emisora", "اسم المحطة"],
        "播放地址（HTTP / HTTPS）": ["Stream URL (HTTP / HTTPS)", "配信 URL（HTTP / HTTPS）", "스트림 URL (HTTP / HTTPS)", "URL สตรีม (HTTP / HTTPS)", "URL de la fuente (HTTP / HTTPS)", "رابط البث (HTTP / HTTPS)"],
        "节目类型": ["Category", "ジャンル", "분류", "หมวดหมู่", "Categoría", "الفئة"],
        "语言": ["Language", "言語", "언어", "ภาษา", "Idioma", "اللغة"],
        "别名": ["Aliases", "別名", "별칭", "ชื่ออื่น", "Nombres alternativos", "أسماء بديلة"],
        "来源": ["Source", "出典", "출처", "แหล่งที่มา", "Fuente", "المصدر"],
        "多个别名以逗号或换行分隔": ["Separate aliases with commas or new lines", "別名はカンマまたは改行で区切ります", "별칭은 쉼표 또는 줄바꿈으로 구분하세요", "คั่นชื่ออื่นด้วยจุลภาคหรือขึ้นบรรทัดใหม่", "Separa los nombres alternativos con comas o saltos de línea", "افصل الأسماء البديلة بفواصل أو أسطر جديدة"],
        "导入和导出": ["Import and Export", "読み込みと書き出し", "가져오기 및 내보내기", "นำเข้าและส่งออก", "Importar y exportar", "استيراد وتصدير"],
        "导入本地 JSON 文件": ["Import Local JSON File", "ローカル JSON ファイルを読み込む", "로컬 JSON 파일 가져오기", "นำเข้าไฟล์ JSON ในเครื่อง", "Importar archivo JSON local", "استيراد ملف JSON محلي"],
        "HTTPS JSON 文件直链": ["Direct HTTPS URL to a JSON file", "JSON ファイルの HTTPS 直リンク", "JSON 파일의 직접 HTTPS 주소", "ลิงก์ HTTPS โดยตรงไปยังไฟล์ JSON", "Enlace HTTPS directo a un archivo JSON", "رابط HTTPS مباشر لملف JSON"],
        "正在下载并校验…": ["Downloading and validating…", "ダウンロードして検証中…", "다운로드 및 확인 중…", "กำลังดาวน์โหลดและตรวจสอบ…", "Descargando y validando…", "جارٍ التنزيل والتحقق…"],
        "取消": ["Cancel", "キャンセル", "취소", "ยกเลิก", "Cancelar", "إلغاء"],
        "导入网络 JSON 文件": ["Import Network JSON File", "ネットワーク JSON ファイルを読み込む", "네트워크 JSON 파일 가져오기", "นำเข้าไฟล์ JSON จากเครือข่าย", "Importar archivo JSON de Internet", "استيراد ملف JSON عبر الشبكة"],
        "管理个人电台": ["Manage Personal Stations", "マイラジオを管理", "개인 방송국 관리", "จัดการสถานีส่วนตัว", "Gestionar emisoras personales", "إدارة المحطات الشخصية"],
        "尚未添加电台": ["No Stations Yet", "放送局がまだありません", "아직 방송국이 없습니다", "ยังไม่มีสถานี", "Aún no hay emisoras", "لا توجد محطات بعد"],
        "删除此电台？": ["Delete this station?", "この放送局を削除しますか？", "이 방송국을 삭제할까요?", "ลบสถานีนี้หรือไม่", "¿Eliminar esta emisora?", "هل تريد حذف هذه المحطة؟"],
        "删除": ["Delete", "削除", "삭제", "ลบ", "Eliminar", "حذف"],
        "删除电台": ["Delete Station", "放送局を削除", "방송국 삭제", "ลบสถานี", "Eliminar emisora", "حذف المحطة"],
        "删除失败": ["Delete Failed", "削除できませんでした", "삭제 실패", "ลบไม่สำเร็จ", "Error al eliminar", "فشل الحذف"],
        "播放状态": ["Playback Status", "再生状態", "재생 상태", "สถานะการเล่น", "Estado de reproducción", "حالة التشغيل"],
        "确定": ["OK", "OK", "확인", "ตกลง", "Aceptar", "حسنًا"],
        "确认": ["Confirm", "確認", "확인", "ยืนยัน", "Confirmar", "تأكيد"],
        "華語广播": ["Personal Radio", "マイラジオ", "개인 라디오", "วิทยุส่วนตัว", "Radio personal", "راديو شخصي"],
        "导出个人电台": ["Export Personal Stations", "マイラジオを書き出す", "개인 방송국 내보내기", "ส่งออกสถานีส่วนตัว", "Exportar emisoras personales", "تصدير المحطات الشخصية"],
        "JSON 格式与限制": ["JSON Format and Limits", "JSON 形式と制限", "JSON 형식 및 제한", "รูปแบบและข้อจำกัด JSON", "Formato y límites de JSON", "تنسيق JSON والقيود"],
        "支持 schemaVersion 为 1 的 Wavelet JSON，可在 iOS 与 Mac 间互相导入。单个文件及合并后目录最多 10 MB、10000 个电台。导入按播放 URL 去重。导出包含本机全部电台和线路，不包含收藏、收听记录、音量或其他设置。清理或卸载前请先导出备份。": ["Wavelet JSON schemaVersion 1 files can be exchanged between iOS and Mac. Each file and the merged catalog is limited to 10 MB and 10,000 stations. Imports are deduplicated by stream URL. Exports include all stations and streams on this Mac, but not favorites, listening history, volume, or other settings. Export a backup before clearing data or uninstalling.", "iOS と Mac 間で Wavelet JSON schemaVersion 1 ファイルを共有できます。各ファイルと統合後の一覧は 10 MB、10,000 局までです。読み込み時は配信 URL で重複を除外します。書き出しにはこの Mac の全放送局と配信回線が含まれますが、お気に入り、再生履歴、音量などの設定は含まれません。データ消去やアンインストールの前にバックアップを書き出してください。", "iOS와 Mac 간에 Wavelet JSON schemaVersion 1 파일을 주고받을 수 있습니다. 파일 및 병합된 목록은 최대 10MB, 10,000개 방송국입니다. 가져올 때 스트림 URL로 중복을 제거합니다. 내보내기에는 이 Mac의 모든 방송국과 스트림이 포함되지만 즐겨찾기, 청취 기록, 볼륨 및 설정은 포함되지 않습니다. 데이터를 지우거나 앱을 제거하기 전에 백업을 내보내세요.", "ใช้ไฟล์ Wavelet JSON schemaVersion 1 ร่วมกันระหว่าง iOS และ Mac ได้ แต่ละไฟล์และรายการหลังรวมมีขนาดไม่เกิน 10 MB และ 10,000 สถานี การนำเข้าจะตัดรายการซ้ำตาม URL สตรีม การส่งออกมีทุกสถานีและสตรีมใน Mac เครื่องนี้ แต่ไม่รวมรายการโปรด ประวัติการฟัง ระดับเสียง หรือการตั้งค่าอื่น โปรดส่งออกข้อมูลสำรองก่อนล้างข้อมูลหรือถอนการติดตั้ง", "Los archivos Wavelet JSON schemaVersion 1 se pueden intercambiar entre iOS y Mac. Cada archivo y el catálogo combinado admiten hasta 10 MB y 10.000 emisoras. La importación elimina duplicados por URL de emisión. La exportación incluye todas las emisoras y fuentes de este Mac, pero no favoritos, historial, volumen ni otros ajustes. Exporta una copia antes de borrar datos o desinstalar.", "يمكن تبادل ملفات Wavelet JSON ذات schemaVersion 1 بين iOS وMac. الحد الأقصى لكل ملف وللدليل بعد الدمج هو 10 ميغابايت و10,000 محطة. تُزال التكرارات عند الاستيراد وفق رابط البث. يشمل التصدير كل المحطات والبثوث على هذا الـ Mac، ولا يشمل المفضلة أو سجل الاستماع أو مستوى الصوت أو الإعدادات الأخرى. صدّر نسخة احتياطية قبل مسح البيانات أو إزالة التطبيق."],
        "清除所有电台": ["Clear All Stations", "すべての放送局を消去", "모든 방송국 지우기", "ล้างสถานีทั้งหมด", "Borrar todas las emisoras", "مسح كل المحطات"],
        "将清空所有电台，请确认": ["Clear all stations?", "すべての放送局を消去しますか？", "모든 방송국을 지울까요?", "ล้างสถานีทั้งหมดหรือไม่", "¿Borrar todas las emisoras?", "هل تريد مسح كل المحطات؟"],
        "电台列表和我的收藏将全部清空。": ["Your station list and favorites will be cleared.", "放送局一覧とお気に入りがすべて消去されます。", "방송국 목록과 즐겨찾기가 모두 지워집니다.", "รายการสถานีและรายการโปรดจะถูกล้างทั้งหมด", "Se borrarán la lista de emisoras y los favoritos.", "سيتم مسح قائمة المحطات والمفضلة بالكامل."],
        "已清除": ["Cleared", "消去しました", "삭제 완료", "ล้างแล้ว", "Borrado", "تم المسح"],
        "本机电台和收藏已清空。": ["Stations and favorites on this Mac have been cleared.", "この Mac の放送局とお気に入りを消去しました。", "이 Mac의 방송국과 즐겨찾기를 지웠습니다.", "ล้างสถานีและรายการโปรดใน Mac เครื่องนี้แล้ว", "Se borraron las emisoras y favoritos de este Mac.", "تم مسح المحطات والمفضلة على هذا الـ Mac."],
        "文件中没有电台，现有目录未更改。": ["The file contains no stations. Your catalog was not changed.", "ファイルに放送局がないため、一覧は変更されていません。", "파일에 방송국이 없어 목록은 변경되지 않았습니다.", "ไฟล์ไม่มีสถานี รายการเดิมจึงไม่เปลี่ยนแปลง", "El archivo no contiene emisoras. No se modificó el catálogo.", "لا يحتوي الملف على محطات، ولم يتغير الدليل الحالي."],
        "已新增 %d 个电台。": ["Added %d stations.", "%d 局を追加しました。", "%d개 방송국을 추가했습니다.", "เพิ่ม %d สถานีแล้ว", "Se añadieron %d emisoras.", "تمت إضافة %d محطة."],
        "部分电台或已存在，请去除重复项": ["Some stations already exist. Remove duplicates from the file and try again.", "一部の放送局はすでに登録されています。ファイルから重複を削除してください。", "일부 방송국이 이미 있습니다. 파일에서 중복 항목을 제거하세요.", "มีบางสถานีอยู่แล้ว โปรดลบรายการซ้ำออกจากไฟล์", "Algunas emisoras ya existen. Elimina los duplicados del archivo.", "بعض المحطات موجودة بالفعل. أزل التكرارات من الملف."],
        "提示": ["Notice", "お知らせ", "알림", "แจ้งเตือน", "Aviso", "تنبيه"],
        "导入完成": ["Import Complete", "読み込み完了", "가져오기 완료", "นำเข้าเสร็จสิ้น", "Importación completada", "اكتمل الاستيراد"],
        "导出完成": ["Export Complete", "書き出し完了", "내보내기 완료", "ส่งออกเสร็จสิ้น", "Exportación completada", "اكتمل التصدير"],
        "已导出本机全部电台和播放线路。": ["All stations and streams on this Mac were exported.", "この Mac のすべての放送局と配信回線を書き出しました。", "이 Mac의 모든 방송국과 스트림을 내보냈습니다.", "ส่งออกทุกสถานีและสตรีมใน Mac เครื่องนี้แล้ว", "Se exportaron todas las emisoras y fuentes de este Mac.", "تم تصدير جميع المحطات والبثوث على هذا الـ Mac."],
        "无法添加电台": ["Unable to Add Station", "放送局を追加できません", "방송국을 추가할 수 없음", "เพิ่มสถานีไม่ได้", "No se pudo añadir la emisora", "تعذرت إضافة المحطة"],
        "导入失败": ["Import Failed", "読み込みに失敗しました", "가져오기 실패", "นำเข้าไม่สำเร็จ", "Error de importación", "فشل الاستيراد"],
        "导入": ["Import", "読み込む", "가져오기", "นำเข้า", "Importar", "استيراد"],
        "导出": ["Export", "書き出す", "내보내기", "ส่งออก", "Exportar", "تصدير"],
        "导出失败": ["Export Failed", "書き出しに失敗しました", "내보내기 실패", "ส่งออกไม่สำเร็จ", "Error de exportación", "فشل التصدير"],
        "无法清除电台": ["Unable to Clear Stations", "放送局を消去できません", "방송국을 지울 수 없음", "ล้างสถานีไม่ได้", "No se pudieron borrar las emisoras", "تعذر مسح المحطات"],
        "下载失败（HTTP %d），请检查文件地址。": ["Download failed (HTTP %d). Check the file URL.", "ダウンロードに失敗しました（HTTP %d）。URL を確認してください。", "다운로드 실패(HTTP %d). 파일 주소를 확인하세요.", "ดาวน์โหลดไม่สำเร็จ (HTTP %d) โปรดตรวจสอบ URL", "Error de descarga (HTTP %d). Comprueba la URL.", "فشل التنزيل (HTTP %d). تحقق من الرابط."],
        "请填写必填项": ["Please fill in the required field", "必須項目を入力してください", "필수 항목을 입력하세요", "โปรดกรอกข้อมูลที่จำเป็น", "Completa el campo obligatorio", "يرجى ملء الحقل المطلوب"],
        "请输入有效的 HTTP 或 HTTPS 播放地址。": ["Enter a valid HTTP or HTTPS stream URL.", "有効な HTTP または HTTPS の配信 URL を入力してください。", "올바른 HTTP 또는 HTTPS 스트림 URL을 입력하세요.", "โปรดป้อน URL สตรีม HTTP หรือ HTTPS ที่ถูกต้อง", "Introduce una URL de emisión HTTP o HTTPS válida.", "أدخل رابط بث HTTP أو HTTPS صالحًا."],
        "网络 JSON 文件请使用 HTTPS 地址。": ["Use an HTTPS URL for network JSON files.", "ネットワーク JSON ファイルには HTTPS URL を使用してください。", "네트워크 JSON 파일에는 HTTPS 주소를 사용하세요.", "โปรดใช้ HTTPS สำหรับไฟล์ JSON ออนไลน์", "Usa una URL HTTPS para archivos JSON en línea.", "استخدم رابط HTTPS لملفات JSON عبر الشبكة."],
        "JSON 格式无效，请查看格式说明。": ["Invalid JSON format. See the format notes.", "JSON 形式が無効です。形式の説明を確認してください。", "잘못된 JSON 형식입니다. 형식 설명을 확인하세요.", "รูปแบบ JSON ไม่ถูกต้อง โปรดดูคำอธิบายรูปแบบ", "Formato JSON no válido. Consulta las instrucciones.", "تنسيق JSON غير صالح. راجع شرح التنسيق."],
        "不支持此文件格式版本。": ["This file format version is not supported.", "このファイル形式のバージョンには対応していません。", "지원하지 않는 파일 형식 버전입니다.", "ไม่รองรับไฟล์รูปแบบเวอร์ชันนี้", "Esta versión del formato no es compatible.", "إصدار تنسيق الملف هذا غير مدعوم."],
        "单次最多导入 10000 个电台。": ["Import up to 10,000 stations at a time.", "一度に読み込める放送局は 10,000 局までです。", "한 번에 최대 10,000개까지 가져올 수 있습니다.", "นำเข้าได้สูงสุด 10,000 สถานีต่อครั้ง", "Importa hasta 10.000 emisoras a la vez.", "يمكن استيراد 10,000 محطة كحد أقصى في المرة الواحدة."],
        "个人电台最多保留 10000 个。": ["A maximum of 10,000 personal stations is allowed.", "個人の放送局は最大 10,000 局まで保存できます。", "개인 방송국은 최대 10,000개까지 저장할 수 있습니다.", "บันทึกสถานีส่วนตัวได้สูงสุด 10,000 สถานี", "Se permiten hasta 10.000 emisoras personales.", "الحد الأقصى للمحطات الشخصية هو 10,000."],
        "文件或合并后的目录超过 10 MB，无法处理。": ["The file or merged catalog exceeds 10 MB.", "ファイルまたは統合後の一覧が 10 MB を超えています。", "파일 또는 병합된 목록이 10MB를 초과했습니다.", "ไฟล์หรือรายการหลังรวมมีขนาดเกิน 10 MB", "El archivo o catálogo combinado supera los 10 MB.", "يتجاوز الملف أو الدليل المدمج 10 ميغابايت."],
        "电台名称不能为空。": ["Station name cannot be empty.", "放送局名を空にすることはできません。", "방송국 이름은 비워 둘 수 없습니다.", "ชื่อสถานีต้องไม่ว่าง", "El nombre de la emisora no puede estar vacío.", "لا يمكن ترك اسم المحطة فارغًا."],
        "电台缺少有效的播放地址。": ["A station is missing a valid stream URL.", "有効な配信 URL がない放送局があります。", "유효한 스트림 주소가 없는 방송국이 있습니다.", "มีสถานีที่ไม่มี URL สตรีมที่ถูกต้อง", "Falta una URL de emisión válida en una emisora.", "تفتقد إحدى المحطات رابط بث صالحًا."],
        "下载地址跳转到了非 HTTPS 页面，已取消导入。": ["The download redirected to a non-HTTPS page. Import was canceled.", "ダウンロード先が HTTPS 以外に転送されたため、読み込みを中止しました。", "다운로드가 HTTPS가 아닌 주소로 이동하여 가져오기를 취소했습니다.", "การดาวน์โหลดเปลี่ยนไปยังหน้าที่ไม่ใช่ HTTPS จึงยกเลิกการนำเข้า", "La descarga redirigió a una página sin HTTPS. Se canceló la importación.", "أُعيد توجيه التنزيل إلى صفحة غير HTTPS، فأُلغي الاستيراد."],
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
