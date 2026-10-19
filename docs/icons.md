# 图标索引

- [SVG 母版](../build/icon.svg)：粗线 G 与实心箭头；底板路径从系统 `RoundedRectangle(style: .continuous)` 导出。
- [生成入口](../scripts/icons.sh)、[矢量渲染](../scripts/render-icons.swift)：`bash scripts/icons.sh` 从 SVG 生成 [PNG](../build/icon.png)、[macOS 图标](../build/icon.icns)、[应用内 PDF](../Sources/Glint/Resources/AppIcon.pdf) 和[菜单栏 PDF](../Sources/Glint/Resources/MenuBarIcon.pdf)。
- [完整应用图标](../Sources/Glint/AppIcon.swift)：[设置侧栏与关于页](../Sources/Glint/SettingsView.swift)。
- [G 主体矢量模板](../Sources/Glint/MenuBarIcon.swift)：菜单栏与[翻译面板](../Sources/Glint/TranslatorView.swift)；[屏幕倍率渲染测试](../Tests/GlintTests/NativeTests.swift)。
- [应用元数据](../build/Info.plist)、[资源打包](../scripts/build.sh)

Glint 最低支持 macOS 14；ICNS 自带透明边距与连续圆角底板。macOS Tahoe 26 对已有 Mac 图标自动裁切或适配到系统形状，见 [Apple 的图标设计说明](https://developer.apple.com/videos/play/wwdc2025/220/)。
