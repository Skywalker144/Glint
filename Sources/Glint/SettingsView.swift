import SwiftUI
import AppKit
import ApplicationServices
import GlintCore

struct SettingsView: View {
    @Bindable var model: AppModel
    @ViewState<String> var tab = "general"
    @ViewState<String> private var historySearch = ""
    @ViewState<Bool> private var clearConfirmation = false
    @ViewState<String> private var networkStatus = ""
    @ViewState<String> private var engineStatus = ""
    @ViewState<[String]> private var models: [String] = []
    @ViewState<Bool> private var busy = false
    @ViewState<Bool> private var accessibility = AXIsProcessTrusted()
    @ViewState<Bool> private var screen = CGPreflightScreenCaptureAccess()
    private let tabs = [("general", "通用", "slider.horizontal.3"), ("translate", "翻译", "globe"), ("ai", "提示词", "sparkles"), ("hotkeys", "快捷键", "keyboard"), ("permissions", "权限", "lock"), ("history", "历史", "clock"), ("about", "关于", "info.circle")]
    private var provider: Provider { Provider.find(model.settings.engine) ?? Catalog.providers[0] }
    private var config: ProviderConfig { model.settings.providers[provider.id] ?? .init() }
    private var contentHeight: CGFloat { ["general":520, "translate":490, "ai":520, "hotkeys":320, "permissions":330, "history":480, "about":520][tab] ?? 480 }
    var body: some View {
        WindowCard {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("设置").font(.system(size: 15, weight: .bold))
                    Text(model.saveMessage).font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                    WindowDragArea().frame(height: 22).frame(maxWidth: .infinity)
                    IconButton(symbol: "xmark", label: "关闭设置", action: model.closeSettings)
                }.padding(.horizontal, 14).padding(.vertical, 8)
                HStack(alignment: .top, spacing: 0) {
                    VStack(spacing: 2) {
                        ForEach(tabs, id: \.0) { item in
                            Button { tab = item.0 } label: {
                                HStack(spacing: 9) { Image(systemName: item.2).frame(width: 15); Text(item.1); Spacer(minLength: 0) }
                                    .padding(.horizontal, 10).padding(.vertical, 8).background(tab == item.0 ? Theme.surface : .clear, in: RoundedRectangle(cornerRadius: 10))
                            }.buttonStyle(.plain).font(.system(size: 13, weight: tab == item.0 ? .semibold : .regular))
                        }
                        Spacer(minLength: 0)
                    }.padding(8).frame(width: 128)
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch tab {
                            case "general": general
                            case "translate": translation
                            case "ai": prompts
                            case "hotkeys": hotkeys
                            case "permissions": permissions
                            case "history": history
                            default: about
                            }
                        }.padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 18).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxWidth: .infinity)
                }.frame(height: contentHeight)
            }
        }.onChange(of: tab, initial: true) { _, _ in model.resizeSettings(contentHeight + 42) }
            .onExitCommand(perform: model.closeSettings)
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in accessibility = AXIsProcessTrusted(); screen = CGPreflightScreenCaptureAccess() }
            .alert("确定要清空所有翻译历史吗？", isPresented: $clearConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive, action: model.clearHistory)
            }
    }
    func heading(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 19, weight: .bold)); Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
    }
    func section(_ title: String, _ detail: String = "") -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(title).font(.system(size: 14, weight: .semibold)); if !detail.isEmpty { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) } }
    }
    var general: some View {
        Group {
            heading("通用", "控制应用启动和基础行为。")
            SettingsCard {
                GlintToggle(title: "开机时自动启动", detail: "登录后在后台静默启动，菜单栏待命", isOn: model.binding(\.launchAtLogin))
                Divider()
                GlintToggle(title: "钉住主窗口", detail: "翻译窗口常驻，切到别的应用也不消失", isOn: model.binding(\.pinned))
                Divider()
                GlintToggle(title: "隐藏菜单栏图标", detail: "隐藏后可按输入翻译快捷键，再点击齿轮打开设置", isOn: model.binding(\.hideTrayIcon))
            }
            section("划词翻译", "选中文字后显示「译」，点击翻译；需要辅助功能权限。")
            SettingsCard {
                GlintToggle(title: "自动显示划词翻译图标", isOn: model.binding(\.selectionPopup))
                Divider()
                HStack { Text("显示方位"); Spacer(); Picker("显示方位", selection: model.binding(\.selectionPopupOptions.position)) { Text("右下").tag("bottom-right"); Text("左下").tag("bottom-left"); Text("右上").tag("top-right"); Text("左上").tag("top-left") }.labelsHidden().frame(width: 160) }
                HStack { Text("显示距离"); Spacer(); TextField("", value: model.binding(\.selectionPopupOptions.distance), format: .number).frame(width: 100); Text("像素").foregroundStyle(Theme.muted) }
                HStack { Text("出现延迟"); Spacer(); TextField("", value: model.binding(\.selectionPopupOptions.delayMs), format: .number).frame(width: 100); Text("毫秒").foregroundStyle(Theme.muted) }
            }.textFieldStyle(.roundedBorder)
            Text("方位和距离以松开鼠标的位置为基准，靠近屏幕边缘时自动避让。").font(.system(size: 12)).foregroundStyle(Theme.muted)
            section("网络代理", "让翻译、朗读和更新请求走本地代理。")
            SettingsCard {
                GlintToggle(title: "使用代理", detail: "关闭时直连", isOn: model.binding(\.proxy.enabled))
                Divider()
                HStack { Text("代理地址"); TextField("127.0.0.1:7890", text: model.binding(\.proxy.url)); Button("测试", action: testProxy).disabled(busy) }.textFieldStyle(.roundedBorder)
                if !networkStatus.isEmpty { Text(networkStatus).font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }
        }
    }
    func providerBinding(_ keyPath: WritableKeyPath<ProviderConfig, String>) -> Binding<String> {
        Binding(get: { config[keyPath: keyPath] }, set: { value in model.changeSettings { $0.providers[provider.id, default: .init()][keyPath: keyPath] = value } })
    }
    var translation: some View {
        Group {
            heading("翻译", "选择翻译服务并就地完成配置，查看语言方向。")
            SettingsCard {
                HStack {
                    Text("翻译服务商")
                    Picker("翻译服务商", selection: model.binding(\.engine)) { ForEach(Catalog.providers) { Text($0.label).tag($0.id) } }.labelsHidden()
                }
                if provider.isAI {
                    Divider()
                    if provider.id == "custom" { HStack { Text("Base URL").frame(width: 66, alignment: .leading); TextField("https://...", text: providerBinding(\.baseURL)) } }
                    HStack { Text("API Key").frame(width: 66, alignment: .leading); SecureField(provider.keyHint ?? "sk-...", text: providerBinding(\.apiKey)) }
                    if let link = provider.keyURL, let url = URL(string: link) { Link("获取 Key ↗", destination: url).font(.system(size: 12)) }
                    HStack {
                        Text("模型").frame(width: 66, alignment: .leading)
                        ModelComboBox(value: providerBinding(\.model), items: models.isEmpty ? provider.models ?? [] : models).frame(height: 26)
                        Button("加载模型", action: loadModels).disabled(busy)
                    }
                } else { Text("免费 Google 翻译开箱即用，无需 API Key 或模型，也不使用系统提示词。").font(.system(size: 12)).foregroundStyle(Theme.muted) }
            }.textFieldStyle(.roundedBorder)
            if provider.isAI {
                HStack { Button("测试翻译", action: testEngine).disabled(busy); Text(engineStatus).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled) }
            }
            section("语言方向", "输入是主语言时翻到副语言；其它语言统一翻到主语言。")
            SettingsCard {
                Picker("主语言", selection: model.binding(\.primaryLanguage)) { ForEach(Catalog.languages) { Text($0.label).tag($0.code) } }
                Divider()
                Picker("副语言", selection: model.binding(\.secondaryLanguage)) { ForEach(Catalog.languages) { Text($0.label).tag($0.code) } }
            }
            HStack { Text(Language.label(model.settings.primaryLanguage) + "输入"); Spacer(); Text("翻译成" + Language.label(model.settings.secondaryLanguage)) }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            HStack { Text("其它语言输入"); Spacer(); Text("翻译成" + Language.label(model.settings.primaryLanguage)) }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
        }.onChange(of: model.settings.engine) { _, _ in models = []; engineStatus = "" }
    }
    var prompts: some View {
        Group {
            heading("提示词", "约束 AI 翻译的输出风格与单词词典行为。")
            if !provider.isAI {
                Text("当前选择的是免费 Google 翻译，不使用系统提示词与词典；切换到 AI 服务商后可在此配置。").padding(12).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            } else {
                HStack { section("系统提示词", "可用占位符：{{primary}}、{{secondary}}、{{target}}。"); Spacer(); Button("恢复默认") { model.changeSettings { $0.systemPrompt = Catalog.defaultSystemPrompt } }.font(.system(size: 12)) }
                TextEditor(text: model.binding(\.systemPrompt)).font(.system(size: 13)).frame(height: 146).padding(6).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack { section("单词词典", "输入单个词时给出音标与紧凑释义。"); Spacer(); Button("恢复默认") { model.changeSettings { $0.dictionaryPrompt = Catalog.defaultDictionaryPrompt } }.font(.system(size: 12)) }
                SettingsCard {
                    GlintToggle(title: "启用单词词典", detail: "输入单词、或划词选中单词时自动切换", isOn: model.binding(\.dictionaryMode))
                    Divider()
                    GlintToggle(title: "例句", detail: "一条短例句，附译文", isOn: model.binding(\.dictionaryExtras.examples))
                    GlintToggle(title: "近义词 / 反义词", detail: "各最多三个，标明词性", isOn: model.binding(\.dictionaryExtras.synonyms))
                    GlintToggle(title: "关联词", detail: "最多三个常用关联词，附简短释义", isOn: model.binding(\.dictionaryExtras.related))
                }
                TextEditor(text: model.binding(\.dictionaryPrompt)).font(.system(size: 13)).frame(height: 146).padding(6).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    var hotkeys: some View {
        Group {
            heading("快捷键", "点击输入框后按下新的组合键。Esc / Delete 清空。")
            SettingsCard {
                ForEach([("input","输入翻译"),("screenshot","截图翻译"),("selection","划词翻译"),("clipboard","剪贴板翻译")], id: \.0) { key, label in
                    HStack { Text(label).frame(width: 80, alignment: .leading); HotkeyRecorder(value: Binding(get: { model.settings.hotkeys[key] ?? "" }, set: { value in model.changeSettings { $0.hotkeys[key] = value } })).frame(height: 30) }
                    if key != "clipboard" { Divider() }
                }
            }
        }
    }
    var permissions: some View {
        Group {
            heading("权限", "检查截图翻译和划词翻译依赖的系统权限。")
            SettingsCard {
                HStack {
                    section("辅助功能", "用于读取当前选中的文字。")
                    Spacer(); Text(accessibility ? "已授权" : "未授权").font(.system(size: 12))
                    Button("打开设置") {
                        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(options)
                        Self.openPermission("Accessibility")
                    }
                }
                Divider()
                HStack {
                    section("屏幕录制", "用于截图翻译时获取屏幕画面。")
                    Spacer(); Text(screen ? "已授权" : "未授权").font(.system(size: 12))
                    Button("打开设置") { Self.openPermission("ScreenCapture") }
                }
            }
            Text("划词监听：" + (model.settings.selectionPopup ? (accessibility ? "已启用" : "等待辅助功能授权") : "已关闭")).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Button("刷新状态") { accessibility = AXIsProcessTrusted(); screen = CGPreflightScreenCaptureAccess() }
            Text("授权后如功能仍未生效，请退出并重新打开 Glint。").font(.system(size: 12)).foregroundStyle(Theme.muted)
        }
    }
    var history: some View {
        Group {
            heading("历史", "查看最近 100 条翻译记录。")
            HStack {
                TextField("搜索原文或译文", text: $historySearch).textFieldStyle(.roundedBorder)
                Button("刷新") { model.history = model.store.history }
                Button("清空") { clearConfirmation = true }.disabled(model.history.isEmpty)
            }
            if model.history.isEmpty { Text("暂无翻译历史").foregroundStyle(Theme.muted) }
            ForEach(model.history.filter { historySearch.isEmpty || ($0.original + $0.translated).localizedCaseInsensitiveContains(historySearch) }) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.original).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
                    Text(item.translated).lineLimit(2)
                    HStack {
                        Text(Language.label(item.source) + " → " + Language.label(item.target)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        Spacer(); Text(StoredDate.display(item.createdAt, time: true)).font(.system(size: 11)).foregroundStyle(Theme.muted)
                    }
                    HStack {
                        Spacer()
                        Button("复制原文") { AppModel.copy(item.original) }
                        Button("复制译文") { AppModel.copy(item.translated) }
                        Button("重新翻译") { model.input = item.original; model.overrides = .init(); model.translate(); model.saveMessage = "重新翻译中…" }
                    }.font(.system(size: 11)).buttonStyle(GlintButtonStyle())
                }.padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    var about: some View {
        Group {
            heading("闪译 · Glint", "划词 / 截图 / 输入翻译")
            SettingsCard {
                HStack { Text("版本"); Spacer(); Text("v" + AppVersion.current) }
                Link("GitHub 仓库 ↗", destination: URL(string: AppVersion.repository)!)
                HStack {
                    Button("检查更新") { Task { await model.update?.check() } }.disabled(model.update?.checking == true || model.update?.downloading == true)
                    if model.update?.ready == true { Button("重启以更新") { model.update?.apply() } }
                    if let update = model.update, !update.latest.isEmpty { Link("下载页面 ↗", destination: URL(string: update.releaseURL)!) }
                }
                if let update = model.update, !update.message.isEmpty { Text(update.message).font(.system(size: 12)).foregroundStyle(Theme.muted).textSelection(.enabled) }
            }
            section("更新日志")
            ForEach(Catalog.changelog) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("v" + entry.version).fontWeight(.semibold)
                        if entry.version == AppVersion.current { Text("当前").font(.system(size: 10)).padding(.horizontal, 6).padding(.vertical, 2).background(Theme.text, in: Capsule()).foregroundStyle(Theme.background) }
                        if let date = entry.date { Text(date).font(.system(size: 11)).foregroundStyle(Theme.muted) }
                    }
                    ForEach(entry.items, id: \.self) { Text("• " + $0).font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true) }
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
                let client = try HTTPClient(proxy: .init(enabled: !model.settings.proxy.url.isEmpty, url: model.settings.proxy.url))
                var request = URLRequest(url: URL(string: "https://www.gstatic.com/generate_204")!); request.timeoutInterval = 8
                let start = Date(); _ = try await client.data(for: request)
                networkStatus = "连接成功 · \(Int(Date().timeIntervalSince(start) * 1000)) ms"
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

struct ModelComboBox: NSViewRepresentable {
    @Binding var value: String
    let items: [String]
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSComboBox {
        let combo = NSComboBox(); combo.isEditable = true; combo.completes = true; combo.delegate = context.coordinator
        combo.font = .systemFont(ofSize: 13); combo.placeholderString = "模型名"; combo.setAccessibilityLabel("模型")
        return combo
    }
    func updateNSView(_ combo: NSComboBox, context: Context) {
        context.coordinator.parent = self
        if combo.objectValues.compactMap({ $0 as? String }) != items { combo.removeAllItems(); combo.addItems(withObjectValues: items) }
        if combo.stringValue != value { combo.stringValue = value }
    }
    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: ModelComboBox
        init(_ parent: ModelComboBox) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) { if let combo = notification.object as? NSComboBox { parent.value = combo.stringValue } }
        func comboBoxSelectionDidChange(_ notification: Notification) { if let combo = notification.object as? NSComboBox, let selected = combo.objectValueOfSelectedItem as? String { parent.value = selected } }
    }
}
