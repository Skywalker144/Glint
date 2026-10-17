import SwiftUI
import AppKit
import ApplicationServices
import GlintCore

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, translate, ai, hotkeys, permissions, history, about

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "通用"
        case .translate: "翻译"
        case .ai: "提示词"
        case .hotkeys: "快捷键"
        case .permissions: "权限"
        case .history: "历史"
        case .about: "关于"
        }
    }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .translate: "globe"
        case .ai: "sparkles"
        case .hotkeys: "keyboard"
        case .permissions: "lock.shield"
        case .history: "clock.arrow.circlepath"
        case .about: "info.circle"
        }
    }
    var detail: String {
        switch self {
        case .general: "让 Glint 按你的习惯工作。"
        case .translate: "配置翻译服务与语言方向。"
        case .ai: "调整 AI 翻译与单词词典的输出。"
        case .hotkeys: "点击录制组合键，按 Esc 或 Delete 清空。"
        case .permissions: "管理截图与划词翻译需要的系统权限。"
        case .history: "搜索和回看最近 100 条翻译。"
        case .about: "闪译 · Glint"
        }
    }
}

struct SettingsView: View {
    static let size = CGSize(width: 800, height: 650)
    @Bindable var model: AppModel
    @ViewState<SettingsPage> var tab = .general
    @ViewState<String> private var historySearch = ""
    @ViewState<Bool> private var clearConfirmation = false
    @ViewState<String> private var networkStatus = ""
    @ViewState<String> private var engineStatus = ""
    @ViewState<[String]> private var models: [String] = []
    @ViewState<Bool> private var busy = false
    @ViewState<Bool> private var accessibility = AXIsProcessTrusted()
    @ViewState<Bool> private var screen = CGPreflightScreenCaptureAccess()
    private let popupPositions = [(id: "bottom-right", title: "右下"), (id: "bottom-left", title: "左下"), (id: "top-right", title: "右上"), (id: "top-left", title: "左上")]
    private var provider: Provider { Provider.find(model.settings.engine) ?? Catalog.providers[0] }
    private var config: ProviderConfig { model.settings.providers[provider.id] ?? .init() }
    private var filteredHistory: [HistoryItem] { model.history.filter { historySearch.isEmpty || ($0.original + $0.translated).localizedCaseInsensitiveContains(historySearch) } }
    var body: some View {
        WindowCard {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 10) {
                        Text("译").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.background)
                            .frame(width: 36, height: 36).background(Theme.text, in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Glint").font(.system(size: 14, weight: .semibold))
                            Text("设置").font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary)
                        }
                    }.padding(.horizontal, 8).padding(.top, 12)
                        .background(WindowDragArea())
                    VStack(spacing: 4) {
                        ForEach(SettingsPage.allCases) { page in
                            Button { tab = page } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: page.symbol).font(.system(size: 13)).frame(width: 18)
                                    Text(page.title)
                                    Spacer(minLength: 0)
                                }
                            }.buttonStyle(SettingsNavigationStyle(selected: tab == page))
                                .accessibilityAddTraits(tab == page ? .isSelected : [])
                        }
                    }
                    Spacer(minLength: 0)
                    Text("Glint \(AppVersion.current)").font(.system(size: 10)).foregroundStyle(SettingsPalette.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 6)
                }.padding(12).frame(width: 176).background(SettingsPalette.sidebar)
                Rectangle().fill(SettingsPalette.border).frame(width: 0.5)
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(tab.title).font(.system(size: 23, weight: .semibold))
                            Text(tab.detail).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        IconButton(symbol: "xmark", label: "关闭设置", action: model.closeSettings)
                    }.padding(.horizontal, 30).padding(.top, 30).padding(.bottom, 24).background(WindowDragArea())
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            switch tab {
                            case .general: general
                            case .translate: translation
                            case .ai: prompts
                            case .hotkeys: hotkeys
                            case .permissions: permissions
                            case .history: history
                            case .about: about
                            }
                        }.padding(.horizontal, 30).padding(.top, 2).padding(.bottom, 28).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).id(tab)
                    HStack(spacing: 6) {
                        Image(systemName: model.saveMessage.isEmpty || model.saveMessage == "已自动保存" ? "checkmark.circle" : "info.circle").font(.system(size: 10))
                        Text(model.saveMessage.isEmpty ? "更改自动保存" : model.saveMessage).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }.font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).padding(.horizontal, 30).padding(.vertical, 12)
                        .background(SettingsPalette.background)
                        .overlay(alignment: .top) { Rectangle().fill(SettingsPalette.border).frame(height: 0.5) }
                }.background(SettingsPalette.background)
            }.frame(minHeight: 360)
                .buttonStyle(SettingsButtonStyle()).textFieldStyle(SettingsTextFieldStyle())
                .tint(Theme.text)
        }.onExitCommand(perform: model.closeSettings)
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in accessibility = AXIsProcessTrusted(); screen = CGPreflightScreenCaptureAccess() }
            .alert("确定要清空所有翻译历史吗？", isPresented: $clearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive, action: model.clearHistory)
            }
    }
    func section(_ title: String, _ detail: String = "") -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .semibold)); if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).fixedSize(horizontal: false, vertical: true) } }
    }
    var general: some View {
        Group {
            section("启动与窗口")
            SettingsCard {
                GlintToggle(title: "开机时自动启动", detail: "登录后在菜单栏待命", symbol: "power", isOn: model.binding(\.launchAtLogin))
                SettingsDivider()
                GlintToggle(title: "钉住主窗口", detail: "切换应用时保持翻译窗口显示", symbol: "pin", isOn: model.binding(\.pinned))
                SettingsDivider()
                GlintToggle(title: "隐藏菜单栏图标", detail: "可用快捷键打开翻译窗口，再进入设置", symbol: "menubar.rectangle", isOn: model.binding(\.hideTrayIcon))
            }
            section("划词翻译", "选中文字后显示「译」，点击翻译；需要辅助功能权限。")
            SettingsCard {
                GlintToggle(title: "自动显示划词翻译图标", isOn: model.binding(\.selectionPopup))
                SettingsDivider()
                SettingsRow(title: "显示方位") {
                    ChoiceMenu(title: "显示方位", value: popupPositions.first { $0.id == model.settings.selectionPopupOptions.position }?.title ?? popupPositions[0].title, selection: model.binding(\.selectionPopupOptions.position)) {
                        ForEach(popupPositions, id: \.id) { Text($0.title).tag($0.id) }
                    }.frame(width: 160)
                }
                SettingsRow(title: "显示距离") {
                    HStack { TextField("距离", value: model.binding(\.selectionPopupOptions.distance), format: .number).frame(width: 100).accessibilityLabel("显示距离"); Text("像素").font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).frame(width: 26) }
                }
                SettingsRow(title: "出现延迟") {
                    HStack { TextField("延迟", value: model.binding(\.selectionPopupOptions.delayMs), format: .number).frame(width: 100).accessibilityLabel("出现延迟"); Text("毫秒").font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).frame(width: 26) }
                }
            }
            Text("方位和距离以松开鼠标的位置为基准，靠近屏幕边缘时自动避让。").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
            section("网络代理", "让翻译、朗读和更新请求走本地代理。")
            SettingsCard {
                GlintToggle(title: "使用代理", detail: "关闭时直连", isOn: model.binding(\.proxy.enabled))
                SettingsDivider()
                HStack(spacing: 10) { Text("代理地址"); TextField("127.0.0.1:7890", text: model.binding(\.proxy.url)).accessibilityLabel("代理地址"); Button("测试", action: testProxy).disabled(busy) }
                if !networkStatus.isEmpty { Text(networkStatus).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary) }
            }
        }
    }
    func providerBinding(_ keyPath: WritableKeyPath<ProviderConfig, String>) -> Binding<String> {
        Binding(get: { config[keyPath: keyPath] }, set: { value in model.changeSettings { $0.providers[provider.id, default: .init()][keyPath: keyPath] = value } })
    }
    var translation: some View {
        Group {
            section("翻译引擎")
            SettingsCard {
                SettingsRow(title: "翻译服务商") {
                    ChoiceMenu(title: "翻译服务商", value: provider.label, selection: model.binding(\.engine)) { ForEach(Catalog.providers) { Text($0.label).tag($0.id) } }.frame(width: 230)
                }
                if provider.isAI {
                    SettingsDivider()
                    if provider.id == "custom" { HStack { Text("Base URL").frame(width: 66, alignment: .leading); TextField("https://...", text: providerBinding(\.baseURL)).accessibilityLabel("Base URL") } }
                    HStack { Text("API Key").frame(width: 66, alignment: .leading); SecureField(provider.keyHint ?? "sk-...", text: providerBinding(\.apiKey)).accessibilityLabel("API Key") }
                    if let link = provider.keyURL, let url = URL(string: link) { Link("获取 Key ↗", destination: url).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).frame(maxWidth: .infinity, alignment: .trailing) }
                    HStack {
                        Text("模型").frame(width: 66, alignment: .leading)
                        ModelPicker(value: providerBinding(\.model), items: models.isEmpty ? provider.models ?? [] : models)
                        Button("加载模型", action: loadModels).disabled(busy)
                    }
                } else { Text("免费 Google 翻译开箱即用，无需 API Key 或模型，也不使用系统提示词。").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary) }
            }
            if provider.isAI {
                HStack { Button("测试翻译", action: testEngine).disabled(busy); Text(engineStatus).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).textSelection(.enabled) }
            }
            section("语言方向", "输入是主语言时翻到副语言；其它语言统一翻到主语言。")
            SettingsCard {
                SettingsRow(title: "主语言") {
                    ChoiceMenu(title: "主语言", value: Language.label(model.settings.primaryLanguage), selection: model.binding(\.primaryLanguage)) { ForEach(Catalog.languages) { Text($0.label).tag($0.code) } }.frame(width: 230)
                }
                SettingsDivider()
                SettingsRow(title: "副语言") {
                    ChoiceMenu(title: "副语言", value: Language.label(model.settings.secondaryLanguage), selection: model.binding(\.secondaryLanguage)) { ForEach(Catalog.languages) { Text($0.label).tag($0.code) } }.frame(width: 230)
                }
            }
            VStack(spacing: 10) {
                HStack { Text(Language.label(model.settings.primaryLanguage) + "输入"); Spacer(); Image(systemName: "arrow.right"); Text(Language.label(model.settings.secondaryLanguage)) }
                HStack { Text("其它语言输入"); Spacer(); Image(systemName: "arrow.right"); Text(Language.label(model.settings.primaryLanguage)) }
            }.font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary).padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 9))
        }.onChange(of: model.settings.engine) { _, _ in models = []; engineStatus = "" }
    }
    var prompts: some View {
        Group {
            if !provider.isAI {
                Text("当前选择的是免费 Google 翻译，不使用系统提示词与词典；切换到 AI 服务商后可在此配置。").padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack { section("系统提示词", "可用占位符：{{primary}}、{{secondary}}、{{target}}。"); Spacer(); Button("恢复默认") { model.changeSettings { $0.systemPrompt = Catalog.defaultSystemPrompt } }.font(.system(size: 12)) }
                PromptEditor(title: "系统提示词", text: model.binding(\.systemPrompt))
                HStack { section("单词词典", "输入单个词时给出音标与紧凑释义。"); Spacer(); Button("恢复默认") { model.changeSettings { $0.dictionaryPrompt = Catalog.defaultDictionaryPrompt } }.font(.system(size: 12)).disabled(!model.settings.dictionaryMode) }
                SettingsCard {
                    GlintToggle(title: "启用单词词典", detail: "输入单词、或划词选中单词时自动切换", isOn: model.binding(\.dictionaryMode))
                    SettingsDivider()
                    Group {
                        GlintToggle(title: "例句", detail: "一条短例句，附译文", isOn: model.binding(\.dictionaryExtras.examples))
                        GlintToggle(title: "近义词 / 反义词", detail: "各最多三个，标明词性", isOn: model.binding(\.dictionaryExtras.synonyms))
                        GlintToggle(title: "关联词", detail: "最多三个常用关联词，附简短释义", isOn: model.binding(\.dictionaryExtras.related))
                    }.disabled(!model.settings.dictionaryMode)
                }
                PromptEditor(title: "词典提示词", text: model.binding(\.dictionaryPrompt)).disabled(!model.settings.dictionaryMode)
            }
        }
    }
    var hotkeys: some View {
        Group {
            SettingsCard {
                ForEach([("input","输入翻译"),("screenshot","截图翻译"),("selection","划词翻译"),("clipboard","剪贴板翻译")], id: \.0) { key, label in
                    SettingsRow(title: label) { HotkeyRecorder(value: Binding(get: { model.settings.hotkeys[key] ?? "" }, set: { value in model.changeSettings { $0.hotkeys[key] = value } }), onRecordingChanged: model.onRecordingHotkey).frame(width: 230, height: 30) }
                    if key != "clipboard" { SettingsDivider() }
                }
            }
        }
    }
    var permissions: some View {
        Group {
            SettingsCard {
                HStack {
                    section("辅助功能", "用于读取当前选中的文字。")
                    Spacer(); PermissionBadge(granted: accessibility)
                    Button("打开设置") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        Self.openPermission("Accessibility")
                    }
                }
                SettingsDivider()
                HStack {
                    section("屏幕录制", "用于截图翻译时获取屏幕画面。")
                    Spacer(); PermissionBadge(granted: screen)
                    Button("打开设置") { Self.openPermission("ScreenCapture") }
                }
            }
            Text("划词监听：" + (model.settings.selectionPopup ? (accessibility ? "已启用" : "等待辅助功能授权") : "已关闭")).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
            Button("刷新状态") { accessibility = AXIsProcessTrusted(); screen = CGPreflightScreenCaptureAccess() }
            Text("授权后如功能仍未生效，请退出并重新打开 Glint。").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
        }
    }
    var history: some View {
        Group {
            HStack {
                TextField("搜索原文或译文", text: $historySearch)
                Button("清空", role: .destructive) { clearConfirmation = true }.disabled(model.history.isEmpty)
            }
            if filteredHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: historySearch.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass").font(.system(size: 26, weight: .light))
                    Text(historySearch.isEmpty ? "暂无翻译历史" : "没有匹配的记录").font(.system(size: 12))
                }.foregroundStyle(SettingsPalette.secondary).frame(maxWidth: .infinity).padding(.vertical, 60)
            }
            ForEach(filteredHistory) { item in
                HistoryCard(item: item, retranslate: { model.openTranslation(item.original) })
            }
        }
    }
    var about: some View {
        Group {
            HStack(spacing: 14) {
                Text("译").font(.system(size: 30, weight: .semibold)).frame(width: 62, height: 62)
                    .foregroundStyle(Theme.background).background(Theme.text, in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 6) { Text("闪译 · Glint").font(.system(size: 17, weight: .semibold)); Text("划词 / 截图 / 输入翻译").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary) }
            }
            SettingsCard {
                HStack { Text("版本"); Spacer(); Text("v" + AppVersion.current) }
                Link("GitHub 仓库 ↗", destination: URL(string: AppVersion.repository)!)
                HStack {
                    Button("检查更新") { Task { await model.update?.check() } }.disabled(model.update?.checking == true || model.update?.downloading == true)
                    if model.update?.ready == true { Button("重启以更新") { model.update?.apply() } }
                    if let update = model.update, !update.latest.isEmpty { Link("下载页面 ↗", destination: URL(string: update.releaseURL)!) }
                }
                if let update = model.update, !update.message.isEmpty { Text(update.message).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).textSelection(.enabled) }
            }
            section("更新日志")
            ForEach(Catalog.changelog) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("v" + entry.version).fontWeight(.semibold)
                        if entry.version == AppVersion.current { Text("当前").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.text, in: Capsule()).foregroundStyle(Theme.background) }
                        if let date = entry.date { Text(date).font(.system(size: 11)).foregroundStyle(SettingsPalette.secondary) }
                    }
                    ForEach(entry.items, id: \.self) { Text("• " + $0).font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary).fixedSize(horizontal: false, vertical: true) }
                }
            }
        }
    }
    static func openPermission(_ kind: String) { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_" + kind)!) }
    func testProxy() {
        busy = true; networkStatus = "测试中…"
        Task {
            defer { busy = false }
            do {
                let proxy = model.settings.proxy
                let client = try HTTPClient(proxy: proxy)
                var request = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!); request.timeoutInterval = 8
                let start = Date(); _ = try await client.data(for: request)
                networkStatus = (proxy.enabled ? "代理" : "直连") + "连接成功 · \(Int(Date().timeIntervalSince(start) * 1000)) ms"
            } catch { networkStatus = error.localizedDescription }
        }
    }
    func loadModels() {
        busy = true; engineStatus = "正在加载模型…"
        let selected = provider, saved = config
        Task {
            defer { busy = false }
            do {
                let engine = try TranslationEngine(client: HTTPClient(proxy: model.settings.proxy))
                let values = try await engine.models(provider: selected, config: saved)
                if provider.id == selected.id { models = values; engineStatus = "已加载 \(values.count) 个模型" }
            } catch { engineStatus = error.localizedDescription }
        }
    }
    func testEngine() {
        busy = true; engineStatus = "测试翻译中…"
        let settings = model.settings
        Task {
            defer { busy = false }
            do {
                let request = try TranslationRequest.resolve("Hello, world. This is a test.", settings: settings, overrides: .init(mode: .translate))
                let engine = try TranslationEngine(client: HTTPClient(proxy: settings.proxy))
                let result = try await engine.translate("Hello, world. This is a test.", request: request) { _ in }
                engineStatus = "✓ " + result.translated
            } catch { engineStatus = HTTPClient.friendly(error, engine: settings.engine) }
        }
    }
}
