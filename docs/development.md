# 开发与验收

## 实现索引

| 职责 | 唯一实现入口 |
| --- | --- |
| 窗口、菜单栏、快捷键、命令协调 | [main.rs](../src-tauri/src/main.rs) |
| 取词、截图、OCR、语言识别、焦点恢复 | [Swift 原生桥](../src-tauri/native/main.swift)、[Rust 调用](../src-tauri/src/platform.rs) |
| 查询状态与界面 | [query.ts](../src/query.ts)、[main.ts](../src/main.ts) |
| 本地词典与词形关系 | [dictionary.rs](../src-tauri/src/dictionary.rs) |
| AI 请求、流式解析、钥匙串读取 | [ai.rs](../src-tauri/src/ai.rs) |
| 设置默认值、生词本及去重 | [store.rs](../src-tauri/src/store.rs) |
| 数据版本、校验与 SQLite 生成 | [build-dictionary.py](../scripts/build-dictionary.py) |
| 经核实的词形校订 | [lexical-review.json](../src-tauri/resources/lexical-review.json) |
| 构建与运行命令 | [package.json](../package.json) |

ECDICT 保留完整词条、正反向词形关系；校订表仅保存人工确认的信息。未确认的独立义项不自动折叠到词头。词库生成物不入 Git，构建依赖固定版本数据下载；许可证随应用分发。

系统数据路径由 Tauri 的 `app_data_dir` 决定。API Key 使用系统钥匙串，不进入 SQLite、生词本导出或前端持久化。

## 定向检查

```sh
npm run prepare:desktop
npm run build
node --experimental-strip-types --test tests/query.test.ts
cargo test --manifest-path src-tauri/Cargo.toml dictionary::tests
cargo test --manifest-path src-tauri/Cargo.toml store::tests
cargo test --manifest-path src-tauri/Cargo.toml ai::tests
npm run tauri -- build --debug --bundles app
```

AI 测试启动本机临时 HTTP 服务，需要允许绑定本地端口。它验证传输协议，不代表真实服务验收。

## 验收状态

已验证：前端、Rust、Swift 编译；macOS 应用打包和启动；真实 ECDICT 的产品样例及固定短语；查询状态测试；网络分块中文解码、空响应和中断处理；生词本去重及语境追加；窗口内实际查询、收藏及重启后读取；未配置密钥时保留原文和已有词典结果；系统中英语言识别。

仍需实机验收：

- 为应用开启辅助功能权限，在 Chrome 和 Zotero 中选择文本并触发划词；检查选区、原剪贴板与 Esc 后焦点恢复。自动化按键未能可靠触发系统全局快捷键，因此不将注册成功等同于入口验收通过。
- 开启屏幕录制权限，框选文字、取消框选，检查 OCR 和修改原文后重试；检查多屏定位。
- 配置真实 API Key，测试 DeepSeek 与所需兼容服务、AI JSON 释义、停止和连续查询。
- 用中文输入法组词，检查 Enter 不误提交；检查快捷键与其他应用冲突时保留旧绑定。
- 检查生词本导入导出与菜单栏右键退出。

## 首版边界

当前是可运行的首版实现。浮窗在指针附近定位；精确跟随辅助功能选区矩形尚未接入。AI 补充以来源独立的可折叠文本显示，尚未拆成例句、词组、近反义词的结构化栏目。发音采用明确标识的系统朗读，没有伪装成词典录音。

外部协议参考：[Tauri 菜单栏](https://v2.tauri.app/learn/system-tray/)、[全局快捷键](https://v2.tauri.app/plugin/global-shortcut/)、[DeepSeek Chat Completions](https://api-docs.deepseek.com/api/create-chat-completion/)、[JSON Output](https://api-docs.deepseek.com/guides/json_mode/)。
