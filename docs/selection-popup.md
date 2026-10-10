# 划词图标开发索引

- [macOS 系统选区监听与 Text Marker 选区读取](../src/main/native/macselection.swift)
- [图标窗口与监听生命周期](../src/main/selection-popup.js)
- [划词缓存、点击与显示器边界](../src/main/selection-popup-state.js)
- [翻译窗口激活与划词入口](../src/main/index.js)
- [划词原文更新与输入焦点](../src/renderer/translator.js)
- [设置默认值](../src/main/settings.js)
- [状态回归](../test/selection-popup.test.js)：`node --test test/selection-popup.test.js`
- [原生应用激活回归](../test/selection-monitor.test.js)：`node --test test/selection-monitor.test.js`
- [Electron 验证](../scripts/check-selection-popup.cjs)：`npx electron scripts/check-selection-popup.cjs`，覆盖钉住后的连续划词及点击时恢复窗口焦点；窗口内鼠标输入验证不覆盖 macOS 首次点击分发，加 `--interactive` 使用真实鼠标验证外部应用选区与图标点击。
- [翻译界面验证](../scripts/check-translator.cjs)：`npx electron scripts/check-translator.cjs`，覆盖新选区替换在途翻译及划词、手动输入的焦点行为。
- [macOS 原生工具打包](../scripts/build-native.sh)：`npm run build:native`
- [App 与原生工具的完整本地签名](../scripts/sign-macos.cjs)
- [签名身份与资源封装回归](../test/macos-signing.test.js)：`node --test test/macos-signing.test.js`
