# 划词索引

- [macOS 选区监听、Text Marker 读取与事件失效](../Sources/Glint/SelectionMonitor.swift)
- [浮动图标、屏幕坐标、点击激活与快捷键取词入口](../Sources/Glint/SelectionService.swift)
- [来源 App 的复制菜单定位](../Sources/Glint/SelectionCopyMenu.swift)
- [快捷键取词优先级、剪贴板恢复与取消](../Sources/Glint/SelectionTextReader.swift)
- [翻译入口、阻塞条件与生命周期](../Sources/Glint/GlintApp.swift)
- [输入与结果焦点](../Sources/Glint/NativeInput.swift)
- [方位、距离、延迟默认值与范围](../Sources/GlintCore/Models.swift)
- [设置控件与权限状态](../Sources/Glint/SettingsView.swift)
- [换行、剪贴板恢复及取词回归](../Tests/GlintTests/SelectionTextTests.swift)
- [真实全局快捷键与跨应用菜单复制](../Tests/GlintTests/SelectionMenuTests.swift)、[测试编辑器](../Tests/GlintTests/selection_menu_host.swift)、[原生测试驱动](../Tests/GlintTests/selection_menu_driver.swift)
- [坐标回归](../Tests/GlintTests/NativeTests.swift)、[真实系统验收范围](README.md#验证)

[菜单复制参考实现](https://github.com/tisfeng/SelectedTextKit/blob/main/Sources/SelectedTextKit/TextSelection/SelectedTextManager.swift)、[复制菜单识别规则参考](https://github.com/tisfeng/SelectedTextKit/blob/main/Sources/SelectedTextKit/AXSwift/AXSwift%2BMenu.swift)。

跨应用测试需辅助功能权限，会临时切换前台测试应用并恢复剪贴板；独立运行以避免其他窗口测试争抢焦点：

```bash
GLINT_LIVE_SELECTION=1 bash scripts/swift.sh test --disable-xctest --filter SelectionMenuTests
```
