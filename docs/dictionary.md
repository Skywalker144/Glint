# 词典与生词本

## 使用

翻译后，原文显示为一行；点击原文可展开编辑。查询模式菜单可选择自动识别、翻译或词典。自动查词开关位于「设置 → 翻译」。

英汉词条提供词库已有的音标、释义、词形变化和考试标签。选择 AI 引擎后，可点击「AI 补充」获取例句与用法；补充内容单独标识。未被词库收录的 AI 词条会显示未经词库验证的提示。

词条下方的「收藏」将内容存入本地生词本。主窗口标题栏和设置侧栏均有入口，支持搜索、朗读、掌握状态、删除与 JSON 导出。导出的是词条及学习状态；应用内暂不提供导入。

## 数据与实现

- 数据来源：[ECDICT](https://github.com/skywind3000/ECDICT)。固定版本、源文件校验值和条目统计以[词库清单](../src/main/data/ecdict/manifest.json)为准；[上游许可证](../src/main/data/ecdict/LICENSE)随应用分发。
- 重建入口：[build-dictionary.py](../scripts/build-dictionary.py)。从清单对应版本获取 `ecdict.csv` 与同目录的 `LICENSE` 后运行 `python3 scripts/build-dictionary.py <ecdict.csv 路径>`。工具验证源文件校验值并生成确定性压缩分片；应用运行时不依赖 Python。
- 加载、归一化和呈现：[dictionary.js](../src/main/dictionary.js)。分片位于 `src/main/data/ecdict`，由现有打包规则包含在 ASAR 中。
- 生词本文件位于 Electron `userData/vocabulary.json`，格式与写入规则以[持久化模块](../src/main/vocabulary.js)为准。清空翻译历史不会删除生词本。

## 验证

定向测试：

```sh
node --test test/dictionary.test.js test/translation-plan.test.js test/vocabulary.test.js test/languages.test.js test/history-util.test.js test/settings.test.js test/prompt.test.js test/speech.test.js
```

Electron 集成验收：

```sh
mkdir -p .cache
node_modules/.bin/asar pack src .cache/glint-source.asar
node_modules/.bin/electron scripts/smoke-dictionary.cjs
```

验收脚本使用项目内隔离配置、真实词库和生产 IPC/界面；外部 AI 用本地 SSE 服务模拟，仅验证协议与交互，不代表线上模型质量。系统登录项、全局快捷键及 OCR 预编译不在此次验收范围。截图和测试配置保留在 `.cache/dictionary-smoke`。
