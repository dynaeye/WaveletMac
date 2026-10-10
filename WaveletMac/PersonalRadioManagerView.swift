import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PersonalRadioManagerView: View {
    @ObservedObject var store: RadioCatalogStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @State private var region = ""
    @State private var city = ""
    @State private var category = ""
    @State private var language = ""
    @State private var aliases = ""
    @State private var source = ""
    @State private var group = ""
    @State private var remoteAddress = ""
    @State private var isDownloading = false
    @State private var downloadTask: Task<Void, Never>?
    @State private var showClearConfirmation = false
    @State private var alert: ManagerAlert?

    private struct ManagerAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private func t(_ key: String) -> String { store.text(key) }

    private var formIsComplete: Bool {
        let required = [name, region, city, category, language]
        guard required.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return (try? PersonalCatalog.validatedURL(address)) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(t("个人电台")).font(.title2.weight(.semibold))
                    Text(store.countText("个电台", store.stations.count)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button(t("关闭")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let loadError = store.loadError {
                        Label(t("个人电台文件无法读取，请导入有效的 JSON 文件恢复；原文件会保留备份。"), systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(t(loadError)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text(t("个人电台保存于本机，不需要账号或云同步。请仅添加你有权收听的音源。"))
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    section("添加电台") {
                        VStack(alignment: .leading, spacing: 11) {
                            field("电台名称", value: $name, required: true)
                            field("播放地址（HTTP / HTTPS）", value: $address, required: true)
                            HStack(spacing: 12) {
                                field("地区", value: $region, required: true)
                                field("城市", value: $city, required: true)
                            }
                            HStack(spacing: 12) {
                                field("节目类型", value: $category, required: true)
                                field("语言", value: $language, required: true)
                            }
                            HStack(spacing: 12) {
                                field("别名", value: $aliases, hint: "多个别名以逗号或换行分隔")
                                field("来源", value: $source)
                            }
                            field("省市 / 分组", value: $group)

                            HStack {
                                Spacer()
                                Button(t("添加电台"), action: addStation)
                                    .buttonStyle(.borderedProminent)
                                    .disabled(!formIsComplete || isDownloading)
                            }
                        }
                    }

                    section("导入和导出") {
                        VStack(alignment: .leading, spacing: 10) {
                            Button { importLocalFile() } label: {
                                Label(t("导入本地 JSON 文件"), systemImage: "doc.badge.plus")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.bordered)
                            .disabled(isDownloading)

                            TextField(t("HTTPS JSON 文件直链"), text: $remoteAddress)
                                .textFieldStyle(.roundedBorder)
                                .disabled(isDownloading)

                            HStack {
                                if isDownloading {
                                    ProgressView().controlSize(.small)
                                    Text(t("正在下载并校验…")).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(t("取消"), action: cancelDownload)
                                } else {
                                    Button { beginNetworkImport() } label: {
                                        Label(t("导入网络 JSON 文件"), systemImage: "arrow.down.doc")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    Spacer()
                                    Button { exportFile() } label: {
                                        Label(t("导出个人电台"), systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(isDownloading || store.loadError != nil)
                                }
                            }
                        }
                    }

                    section("JSON 格式与限制") {
                        Text(t("支持 schemaVersion 为 1 的 Wavelet JSON，可在 iOS 与 Mac 间互相导入。单个文件及合并后目录最多 10 MB、10000 个电台。导入按播放 URL 去重。导出包含本机全部电台和线路，不包含收藏、收听记录、音量或其他设置。清理或卸载前请先导出备份。"))
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    HStack {
                        Button(t("清除所有电台"), role: .destructive) { showClearConfirmation = true }
                            .disabled(store.stations.isEmpty || isDownloading)
                        Spacer()
                    }
                }
                .padding(22)
                .frame(maxWidth: 760, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 620, minHeight: 660)
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear { cancelDownload() }
        .alert(item: $alert) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text(t("确定")))
            )
        }
        .confirmationDialog(
            t("将清空所有电台，请确认"),
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(t("确认"), role: .destructive, action: clearAll)
            Button(t("取消"), role: .cancel) { }
        } message: {
            Text(t("电台列表和我的收藏将全部清空。"))
        }
    }

    @ViewBuilder
    private func field(_ title: String, value: Binding<String>, required: Bool = false, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(t(title)).font(.callout.weight(.medium))
                if required { Text("*").foregroundStyle(.red) }
            }
            TextField(hint.map(t) ?? "", text: value)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(t(title)).font(.headline)
            content()
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.5)))
        }
    }

    private func addStation() {
        do {
            let result = try store.addStation(
                name: name, region: region, url: address, city: city,
                category: category, language: language,
                aliases: [aliases], source: source, group: group
            )
            if result.added > 0 { clearForm() }
            showImportResult(result)
        } catch {
            showAlert(t("无法添加电台"), store.errorMessage(for: error))
        }
    }

    private func importLocalFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = t("导入")
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let hasScope = url.startAccessingSecurityScopedResource()
        defer { if hasScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? NSNumber, size.intValue > PersonalCatalog.maximumBytes {
                throw PersonalCatalog.Failure.tooLarge
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let result = try store.importStations(data)
            showImportResult(result)
        } catch {
            showAlert(t("导入失败"), store.errorMessage(for: error))
        }
    }

    private func beginNetworkImport() {
        let address = remoteAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        isDownloading = true
        downloadTask = Task {
            do {
                let data = try await NetworkStationCatalog.download(from: address)
                try Task.checkCancellation()
                let result = try store.importStations(data)
                showImportResult(result)
            } catch is CancellationError {
                // Closing the sheet or pressing Cancel leaves the directory untouched.
            } catch {
                if !Task.isCancelled { showAlert(t("导入失败"), store.errorMessage(for: error)) }
            }
            isDownloading = false
            downloadTask = nil
        }
    }

    private func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Wavelet-Personal-Stations.json"
        panel.canCreateDirectories = true
        panel.prompt = t("导出")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try store.exportStations()
            try data.write(to: url, options: .atomic)
            showAlert(t("导出完成"), t("已导出本机全部电台和播放线路。"))
        } catch {
            showAlert(t("导出失败"), store.errorMessage(for: error))
        }
    }

    private func clearAll() {
        do {
            try store.clearAllStations()
            showAlert(t("已清除"), t("本机电台和收藏已清空。"))
        } catch {
            showAlert(t("无法清除电台"), store.errorMessage(for: error))
        }
    }

    private func showImportResult(_ result: PersonalCatalog.ImportResult) {
        if result.incomingCount == 0 {
            showAlert(t("导入完成"), t("文件中没有电台，现有目录未更改。"))
            return
        }
        if result.added == 0 {
            showAlert(t("提示"), t("部分电台或已存在，请去除重复项"))
            return
        }
        var message = MacLocalization.format("已新增 %d 个电台。", count: result.added, language: store.interfaceLanguage)
        if result.duplicates > 0 {
            message += "\n\(t("部分电台或已存在，请去除重复项"))"
        }
        showAlert(t("导入完成"), message)
    }

    private func showAlert(_ title: String, _ message: String) {
        alert = ManagerAlert(title: title, message: message)
    }

    private func clearForm() {
        name = ""
        address = ""
        region = ""
        city = ""
        category = ""
        language = ""
        aliases = ""
        source = ""
        group = ""
    }
}
