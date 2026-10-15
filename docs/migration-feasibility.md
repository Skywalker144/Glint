# Tauri / Swift 迁移可行性

当前产品范围为 macOS 14+、SwiftUI + AppKit；实现与验证入口见[开发索引](README.md)。以下保留原路线评估，源码链接固定到评估时的 Electron 版本。

调研日期：2026-10-09。结论来自当前源码与官方文档；未实现迁移原型，未测量包体、内存、CPU 或启动时间。

## 结论与选择

两条路线都可行，没有发现明确的功能阻碍，但都需要替换 Electron 主进程能力。

- 继续维护 macOS 与 Windows：优先 Tauri 2，保留网页界面，将系统能力、网络请求、配置与数据写入收敛到 Rust 后端。
- 产品明确只面向 macOS：优先 SwiftUI + AppKit。SwiftUI 负责界面，AppKit 负责浮窗、焦点、选区与菜单栏，Vision 和 ScreenCaptureKit 负责 OCR 与截图。
- 在当前仍有双平台发布的前提下，默认建议 Tauri。若决定取消 Windows，Swift 更符合这个常驻翻译工具的系统交互需求。

Swift 语言支持 Windows，但这不意味着 SwiftUI / AppKit macOS 应用可以直接运行在 Windows；维持双平台将需要另一套界面和系统适配。[Swift Windows](https://www.swift.org/install/windows/)、[SwiftUI](https://developer.apple.com/swiftui/)。

## 源码依据

| 迁移边界 | 唯一源码入口 | 对迁移的意义 |
| --- | --- | --- |
| 前后端能力契约 | [preload](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/preload/index.js) | 界面通过 `window.api` 调用后台，适合替换桥接层 |
| 系统窗口与生命周期 | [main](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/index.js)、[生词本窗口](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/vocabulary-window.js) | Electron 耦合最集中，需要重实现 |
| 翻译语义与服务商 | [请求解析](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/translation-request.js)、[引擎](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/engines/index.js)、[提示词](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/engines/prompt.js) | 规则可以迁移，不能随换框架改变行为 |
| 网络与 SSE | [HTTP](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/engines/http.js)、[SSE](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/engines/sse.js) | 依赖 Electron 网络层，需保持超时、代理、取消和流式行为 |
| 跨应用取词 | [platform](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/platform.js) | 当前使用模拟复制，不是直接读取辅助功能选中文字 |
| OCR | [OCR 调度](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/ocr.js)、[Swift Vision](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/native/macocr.swift) | 已有 Swift 核心，macOS 识别算法可以沿用 |
| 网页渲染 | [renderer](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/renderer/)、[Markdown](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/markdown.js) | Tauri 可复用大部分界面；Swift 原生界面需要重写 |
| 本地数据 | [设置](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/settings.js)、[历史](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/history.js)、[生词本](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/vocabulary-store.js) | JSON 数据可导入，目录与迁移过程需显式处理 |
| 发布与更新 | [更新器](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/src/main/updater.js)、[发布工作流](https://github.com/Skywalker144/Glint/blob/81dc8576dcc217c9ebc5eb9fcdd0ed8671e59a32/.github/workflows/release.yml) | 新包格式、更新元数据和旧版本升级路径都需要设计 |

## 能力映射与风险

| 能力 | Tauri 2 | SwiftUI + AppKit | 主要验证点 |
| --- | --- | --- | --- |
| 托盘、快捷键、剪贴板、自启 | 官方内置能力或插件 | NSStatusItem、快捷键库、NSPasteboard、SMAppService | 快捷键冲突、录制期间暂停、登录后静默启动 |
| 无边框翻译浮窗 | WebviewWindow；特殊 macOS 行为可能需要原生扩展 | NSPanel + NSHostingView | 输入焦点、失焦隐藏、钉住、横向缩放、自动高度 |
| 全屏应用与多屏 | 基础窗口 API + 平台适配 | NSPanel / NSWindow collectionBehavior | Spaces、全屏应用、负坐标与混合 DPI |
| 划词 | macOS Accessibility / 合成复制；Windows 独立适配 | AXUIElement + 必要时合成复制 | 必须先取词后显示窗口；不同应用支持差异 |
| 截图选区 | 平台截图服务 + 现有网页选区 | ScreenCaptureKit + 原生选区窗口 | 权限、Retina 裁剪、选区覆盖层不进入截图 |
| OCR | Swift helper 或原生绑定；Windows OCR 路线需单独确定 | 直接集成现有 Vision 逻辑 | 中文、阅读顺序、文本清洗与离线行为 |
| AI / 免费翻译、模型列表 | Rust HTTP 客户端 + SSE + Channel | URLSession + AsyncSequence | 连续请求取消、空闲超时、错误映射与任意 Base URL |
| 代理 | 后端统一客户端配置 | URLSession 配置及目标系统支持的代理 API | HTTP / SOCKS 类型、直连语义、翻译/TTS/更新保持一致 |
| Markdown 与公式 | 浏览器化打包现有 Markdown / KaTeX 库 | 原生 Markdown 组件；公式需专门方案或局部 WKWebView | 表格、代码、公式、流式刷新、纯文本复制 |
| 朗读 | 在线音频 + WebView 语音或原生语音 | 在线音频 + AVSpeechSynthesizer | WebKit / WebView2 的语音差异 |
| 更新 | 官方 updater + 签名元数据 | Sparkle + appcast | 旧 Electron 版本如何收到最后一次迁移更新 |

Tauri 的[官方能力目录](https://v2.tauri.app/plugin/)、[全局快捷键](https://v2.tauri.app/plugin/global-shortcut/)和[托盘](https://v2.tauri.app/learn/system-tray/)覆盖基础桌面能力；截图与跨应用取词仍需项目自己的平台服务。Swift 的[NSPanel](https://developer.apple.com/documentation/appkit/nspanel)适合浮窗，[ScreenCaptureKit 截图 API](https://developer.apple.com/videos/play/wwdc2023/10136/)覆盖单帧截图，[URLSession 异步接口](https://developer.apple.com/videos/play/wwdc2021/10095/)支持逐步读取网络响应。表中的映射是方案判断，不代表已完成端到端验证。

## Tauri 路线

保留 HTML/CSS/JS，不需要为了迁移引入 React。以类型化命令替换 `window.api` 桥接；翻译请求、服务商配置、网络客户端与持久化在后端保持单一写入口。Markdown / KaTeX 属于展示，可以打包到前端。提示词与服务商注册表只能有一个权威来源，不能在 Rust 与 JS 各维护一份。

主进程 JS 不会因为换外壳而自动运行：Node `fs`、`child_process`、Electron `net`、IPC 都需要替换。纯规则模块可选择整体迁移到 Rust；原测试用例保留为行为对照。长期方案不建议额外携带 Node sidecar，这会增加运行时和部署边界。

macOS 可以将现有 Swift OCR 编译为 helper，[Tauri 支持随包附带外部程序](https://v2.tauri.app/develop/sidecar/)，需要覆盖目标架构。Windows 当前的 Tesseract Node worker 不能直接原样使用；候选是原生 OCR 或浏览器 Tesseract worker，必须验证语言包、离线部署与包内资源加载后再选定。

需要先验证的限制：

- Tauri 使用系统 WebView，macOS 与 Windows 分别有不同内核和版本，现有 `-webkit-app-region` 应改成 Tauri 拖动机制；`corner-shape`、文字排版、音频与自动高度须在目标系统验证。[WebView 版本](https://v2.tauri.app/reference/webview-versions/)。
- 当前透明卡片外观需要真实窗口透明度。Tauri 文档明确指出 macOS 透明窗口涉及 `macOSPrivateApi`；只需半透明背景时可考察公开的窗口效果 API。[窗口配置](https://v2.tauri.app/reference/config/#transparent)。
- 翻译增量应通过有序 Channel 推送，取消任务由后端统一管理。[Channel](https://v2.tauri.app/develop/calling-frontend/#channels)。
- 官方 HTTP 插件支持代理，但不是 Electron `defaultSession` 的直接替代；采用统一 Rust 网络服务更便于覆盖用户自定义 Base URL、API Key 和所有代理请求。[HTTP 参数](https://v2.tauri.app/reference/javascript/http/)。
- 官方 updater 强制校验更新签名，需新密钥、签名产物与静态 JSON 或更新服务；这是独立于 Apple Developer ID 的签名。[Updater](https://v2.tauri.app/plugin/updater/)。

## Swift 路线

建议使用 SwiftUI + AppKit，而不是强求所有窗口行为都通过 SwiftUI 实现。平台窗口控制集中到 AppKit，翻译和数据服务通过协议与界面分离，取消与流式状态集中管理。macOS 最低版本应先确定；若允许 macOS 14+，可围绕 SCScreenshotManager 建立截图服务，支持更旧系统则需要不同截图路径。

可以复用 Vision OCR 思路、服务商协议、提示词内容、JSON 数据结构、图标与测试场景。网页控件、布局 CSS、Electron IPC 和 Node 持久化需要重写。系统集成潜力更好，但不代表划词兼容性和浮窗行为会自动正确。

完整富文本是这条路线的重要额外工作：Swift 的 Markdown 支持不能直接等同当前 MarkdownIt + KaTeX 效果。若局部使用 WKWebView 负责复杂译文，能沿用公式渲染，但会保留 WebView 的资源开销，应单独测量。原生 Markdown 的范围参考 [AttributedString Markdown](https://developer.apple.com/documentation/foundation/instantiating-attributed-strings-with-markdown-syntax)。自动更新建议评估成熟的 [Sparkle](https://sparkle-project.org/documentation/)，替换现有自定义应用替换脚本。

## 原型与验收顺序

1. 先做系统能力原型：快捷键 → 跨应用取词 / 多屏选区截图 → OCR → 浮窗显示。覆盖浏览器、原生编辑器、PDF、全屏应用与不同 DPI 显示器；确认修饰键释放、焦点与剪贴板完整保留。
2. 再接入一个 OpenAI 兼容服务商和 Anthropic：验证 SSE、停止、新请求替换旧请求、代理切换、超时与自定义本地地址。
3. 迁移界面和规则：语言方向、词典、Markdown / 公式、生词本、朗读、设置与历史。类型与注册表保持单一来源。
4. 验证存量数据：备份后导入设置、历史、生词本；保持词条身份、查询计数与时间。不要让新旧应用同时写同一份文件。
5. 验证真实安装包：应用标识、辅助功能与屏幕权限、签名、自启、更新失败恢复，以及旧 Electron 到新实现的升级路径。
6. 使用相同设备、输入和服务商测量冷启动、常驻空闲、译文流式刷新和 OCR 的 CPU / 内存 / 包体。Tauri 不携带浏览器库，通常有包体优势；具体收益必须实测，不能承诺固定内存或速度倍数。[Tauri 进程模型](https://v2.tauri.app/concept/process-model/)。

只有系统能力原型和真实安装包验收通过，才应将“功能上可行”提升为“可以替换现有发布版本”。
