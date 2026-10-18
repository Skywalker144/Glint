# 开发索引

- [系统要求、运行、打包与旧版数据导入](../README.md)
- [窗口、菜单栏、系统入口与登录启动](../Sources/Glint/GlintApp.swift)
- [浮窗生命周期、自动高度与焦点](../Sources/Glint/WindowController.swift)
- [翻译面板及语言控件](../Sources/Glint/TranslatorView.swift)、[主题、布局间距与宽度拖拽](../Sources/Glint/Theme.swift)、[输入法与键盘](../Sources/Glint/NativeInput.swift)
- [译文滚动、流式顶部保持与操作栏](../Sources/Glint/TranslationResult.swift)、[布局、屏幕底部高度约束、宽度拖动与阅读位置回归](../Tests/GlintTests/TranslatorLayoutTests.swift)
- [翻译状态、取消、收藏及历史写入口](../Sources/Glint/AppModel.swift)
- [语言与文字系统规则](../Sources/GlintCore/Language.swift)、[模式与方向解析](../Sources/GlintCore/TranslationRequest.swift)
- [服务商与流式翻译](../Sources/GlintCore/TranslationEngine.swift)、[网络、代理及错误](../Sources/GlintCore/HTTPClient.swift)
- [语言、服务商、提示词和更新日志目录](../Sources/GlintCore/Resources/)
- [设置与词条数据类型](../Sources/GlintCore/Models.swift)、[持久化及旧数据导入](../Sources/GlintCore/LocalStore.swift)
- [七个设置面板与窗口尺寸](../Sources/Glint/SettingsView.swift)、[设置表面、导航与开关](../Sources/Glint/SettingsStyle.swift)、[共用菜单、输入框、按钮与编辑器](../Sources/Glint/Controls.swift)、[生词本](../Sources/Glint/VocabularyView.swift)
- [原生 Markdown、表格与公式](../Sources/Glint/NativeMarkdown.swift)、[在线及系统朗读](../Sources/Glint/SpeechService.swift)、[历史卡片](../Sources/Glint/HistoryCard.swift)
- [多屏截图选区、Retina 合成及 Vision OCR](../Sources/Glint/CaptureService.swift)、[OCR 段落整理](../Sources/Glint/OCRText.swift)
- [全局快捷键与录制](../Sources/Glint/Hotkeys.swift)、[划词索引](selection-popup.md)
- [更新下载、校验与安装](../Sources/Glint/UpdateService.swift)、[Apple Silicon 构建](../scripts/build.sh)、[分发包](../scripts/package.sh)、[Release 工作流](../.github/workflows/release.yml)
- [个人签名、私钥备份、CI 配置与跨版本验收](signing.md)
- [图标](icons.md)
- [原迁移路线评估](migration-feasibility.md)
- [UI / UX 实现与验收索引](ui-ux-optimization.md)

设置视觉参考 [affectUI Clean](https://github.com/flohoeller/affectui)，由原生 SwiftUI 实现；颜色、表面和交互样式以 [SettingsStyle.swift](../Sources/Glint/SettingsStyle.swift) 与 [Controls.swift](../Sources/Glint/Controls.swift) 为准。

## 验证

完整发布前测试入口：[Release checks 工作流](../.github/workflows/checks.yml)。

按改动范围选择测试，使用 `--filter` 限定套件：

```bash
bash scripts/swift.sh test --disable-xctest --filter 'TranslationRulesTests|NativeTests|TranslatorLayoutTests|InteractionTests|CaptureTextTests'
```

[核心测试](../Tests/GlintCoreTests/)包含由旧版生成的 420 组方向／模式／提示词行为样本、迁移与原文件保护，以及本机 HTTP 服务的真实分段 SSE、Unicode、取消和错误测试。[原生测试](../Tests/GlintTests/)覆盖文字渲染、公式、真实 Vision OCR、快捷键和多屏坐标。设置 `GLINT_LIVE_NETWORK=1` 可另外测试真实 Google 翻译和在线朗读音频。测试需要访问本机网络与系统 OCR 服务；样本和数据均存于 `.cache/`。

```bash
bash scripts/build.sh debug
dist/Glint.app/Contents/MacOS/Glint --data-directory "$PWD/.cache/ui-data" --verify-ui "$PWD/.cache/ui"
```

[诊断入口](../Sources/Glint/AppDiagnostics.swift)仅编入 Debug。它使用独立数据生成三个窗口宽度、翻译页与全部设置页的深浅主题、富文本和生词本截图。`--data-directory` 禁用全局快捷键、划词监听、登录启动设置变更和自动检查更新，适合隔离交互验证。

真实系统验收还需覆盖：外部应用选区与浮动「译」点击、屏幕录制授权后的截图拖拽、全屏与多显示器、登录启动、在线服务商密钥和代理，以及两个签名发布版本之间的更新。系统权限和真实服务商响应不能由本机模拟服务代替。
