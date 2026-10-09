# 划词图标开发索引

- [macOS 系统选区监听与 Text Marker 选区读取](../src/main/native/macselection.swift)
- [图标窗口与监听生命周期](../src/main/selection-popup.js)
- [划词缓存、点击与显示器边界](../src/main/selection-popup-state.js)
- [设置默认值](../src/main/settings.js)
- [状态回归](../test/selection-popup.test.js)：`node --test test/selection-popup.test.js`
- [Electron 验证](../scripts/check-selection-popup.cjs)：`npx electron scripts/check-selection-popup.cjs`；加 `--interactive` 可验证外部应用选区。
- [macOS 原生工具打包](../scripts/build-native.sh)：`npm run build:native`
- [App 与原生工具的完整本地签名](../scripts/sign-macos.cjs)
- [签名身份与资源封装回归](../test/macos-signing.test.js)：`node --test test/macos-signing.test.js`
