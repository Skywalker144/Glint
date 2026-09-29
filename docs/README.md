# 开发索引

- [运行与打包](../README.md)
- [手动源语言、翻译方向与模式的统一解析](../src/main/translation-request.js)
- [翻译执行、流式元信息与历史记录](../src/main/translate.js)
- [一至两行原文框与紧凑工具栏布局](../src/renderer/translator.css)
- [语言选择、交换、模式切换与纯文本复制交互](../src/renderer/translator.js)
- [模式与提示词回归测试](../test/translation-request.test.js)：`node --test test/translation-request.test.js test/prompt.test.js test/languages.test.js`
- [Electron 交互验证](../scripts/check-translator.cjs)：`npx electron scripts/check-translator.cjs`，使用隔离的 `.cache` 数据目录及本地模拟流式接口。
- [词典格式与可选补充内容提示词](../src/main/engines/prompt.js)
- [词典内容偏好与持久化默认值](../src/main/settings.js)
- [共享文字系统分析与混合语言判断](../src/shared/language-scripts.js)
- [规范词头与词条身份](../src/main/dictionary-entry.js)
- [生词本格式迁移、备份、持久化与收藏后查询计数](../src/main/vocabulary-store.js)
- [生词本窗口与入口](../src/main/vocabulary-window.js)
- [生词本搜索、排序与离线词条详情](../src/renderer/vocabulary.js)
- [生词本数据回归](../test/vocabulary.test.js)：`node --test test/vocabulary.test.js`
- [生词本 Electron 交互验证](../scripts/check-vocabulary.cjs)：`npx electron scripts/check-vocabulary.cjs`，使用隔离的 `.cache` 数据目录及本地模拟流式接口。
- [自动发布工作流](../.github/workflows/release.yml)
- [应用内更新日志](../src/main/changelog.js)
