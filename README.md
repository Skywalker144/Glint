# 闪译 · Glint

一个轻量的跨平台（Mac / Windows）翻译小工具，对标 Bob / TTime。黑白单色界面、跟随系统深浅、G2 圆角。快捷键、翻译引擎都可在「设置」里自定义。

## 三个全局快捷键

| 快捷键 | 功能 | 说明 |
| --- | --- | --- |
| `Option+Q` | 输入翻译 | 弹出窗口，输入/粘贴文字，回车翻译 |
| `Option+W` | 截图翻译 | 框选屏幕区域 → OCR 识别 → 翻译 |
| `Option+E` | 划词翻译 | 选中任意文字 → 自动取词 → 翻译 |

> Windows 上 `Option` 即 `Alt`，快捷键通用。

- 翻译方向自动判断：中文 → 英文，其他语言 → 中文。
- 常驻菜单栏（图标为「译」），不占 Dock。右键菜单可手动触发功能或退出。

## 运行

```bash
npm install   # 首次
npm start
```

## 下载（普通用户）

到 [Releases](https://github.com/Skywalker144/Glint/releases) 下载：Mac 用 `.dmg`，Windows 用 `.exe`。

> 未做代码签名 / 公证：
> - **Mac**：若提示「已损坏，无法打开」，在终端运行 `xattr -cr /Applications/Glint.app` 去掉下载隔离即可（一次性；"右键打开"对"已损坏"无效）。
> - **Windows**：若弹 SmartScreen，点「更多信息 → 仍要运行」。
>
> 想下载即开、无任何警告，需要 Apple 开发者账号（$99/年）做**公证**。

## 发布新版本（开发者）

打 `v*` 标签即触发 GitHub Actions 在 Mac / Windows 各自打包并发布到 Release：

```bash
npm version patch        # 升版本号并打 tag
git push --follow-tags   # 推送触发 CI
```

本地单平台打包：`npm run dist:mac` / `npm run dist:win`（Mac 包需要 `swiftc` 预编译 Vision OCR）。

## macOS 首次使用要授权（重要）

开发模式下，系统会把权限记在 **Electron** 这个程序名下：

1. **屏幕录制**（截图翻译需要）：系统设置 → 隐私与安全性 → 屏幕录制 → 勾选 **Electron**，然后**重启 App**。
2. **辅助功能**（划词翻译需要）：系统设置 → 隐私与安全性 → 辅助功能 → 勾选 **Electron**。

第一次用截图 / 划词时若没反应，基本都是还没授权。授权后重新 `npm start` 即可。

> 截图 OCR：**Mac 用系统 Vision 框架**（离线、免费、中文很准），首次启动会用 `swiftc` 自动编译一个小程序并缓存（约 10s，仅一次）。非 Mac 平台回退 `tesseract.js`（首次联网下载中英文识别数据约 10–15MB）。

## 设置（托盘「译」→ 设置…）

左侧分栏：**快捷键 / 翻译引擎 / 关于**。

- **快捷键**：点录制框按下组合键即可，保存时校验冲突与可注册性。
- **翻译引擎**：下拉选服务商（免费 Google / OpenAI / DeepSeek / Anthropic / Gemini / OpenRouter / 自定义）。选 AI 后填 API Key、加载模型并选择，可「测试翻译」验证；每家各存各的 Key/模型，切换不丢。自定义可填任意 OpenAI 兼容的 Base URL（Groq / xAI / 本地 Ollama 等）。

## 技术栈

- **Electron**：跨平台桌面外壳、全局快捷键、托盘、剪贴板。
- **OCR**：Mac 用系统 **Vision**（`src/main/native/macocr.swift`，swiftc 编译）；其他平台用 **tesseract.js**。
- **翻译引擎**：免费 Google，或 OpenAI / DeepSeek / Anthropic / Gemini / OpenRouter / 自定义（OpenAI 兼容）等 AI，设置里切换。

## 代码结构

```
src/
  main/
    index.js          主进程：窗口、托盘、快捷键、截图取词、设置
    translate.js      判断翻译方向 + 调用引擎
    engines/
      index.js        调度器 translateWith / listModels
      providers.js    服务商注册表（加新服务商改这里）
      openai-compat.js OpenAI/DeepSeek/Gemini/OpenRouter/自定义 通用引擎
      anthropic.js    Anthropic Messages API
      google.js       免费 Google 翻译
    ocr.js            OCR：Mac Vision，其他平台 tesseract.js
    native/macocr.swift  Vision OCR 命令行程序
    settings.js       设置持久化（userData/settings.json）
    platform.js       平台相关：划词取词（要加 Windows 支持改这里）
  preload/
    index.js          安全地把能力暴露给界面
  renderer/
    theme.css         共享主题（配色变量 + 通用组件）
    translator.*      主翻译窗口（输入 + 结果）
    settings.*        设置窗口
    capture.*         截图选区遮罩
```

## 之后可以加的

- 划词/截图结果用贴近鼠标的小气泡展示
- 目标语言可选、翻译历史 / 收藏夹、开机自启
- 把 API Key 存进系统钥匙串（目前明文存在 settings.json）
- Windows 托盘图标 & 取词适配、打包成安装包
```
