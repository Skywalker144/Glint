# 开发索引

- [运行与打包](../README.md)
- [手动源语言、翻译方向与模式的统一解析](../src/main/translation-request.js)
- [翻译执行、流式元信息与历史记录](../src/main/translate.js)
- [语言选择、交换、模式切换与纯文本复制交互](../src/renderer/translator.js)
- [模式与提示词回归测试](../test/translation-request.test.js)：`node --test test/translation-request.test.js test/prompt.test.js test/languages.test.js`
- [Electron 交互验证](../scripts/test-translator.cjs)：`npx electron scripts/test-translator.cjs`，使用隔离的 `.cache` 数据目录及本地模拟流式接口。
