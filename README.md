# 闪译 · Glint

适用于 Apple Silicon Mac、macOS 14 及以上的原生翻译工具。SwiftUI + AppKit 界面，常驻菜单栏，支持输入、截图、划词和剪贴板翻译，保留紧凑黑白浮窗、词典、生词本、历史、朗读与七个设置面板。

快捷键可在设置中录制；默认值、语言及服务商目录以[源码资源](docs/README.md)为准。截图使用 ScreenCaptureKit 与离线 Vision OCR；跨应用划词需要辅助功能权限。两项权限可从「设置 → 权限」打开系统授权页。

## 开发与运行

需要 macOS，以及能构建 `Package.swift` 和锁定依赖的 Xcode 或 Swift 工具链。发布使用 [Release 工作流](.github/workflows/release.yml)运行环境自带的 Xcode。首次构建联网获取锁定在 `Package.resolved` 中的依赖。无需 Node、Electron 或 WebView。

```bash
bash scripts/build.sh debug
open dist/Glint.app
```

用 Xcode 打开 `Package.swift` 可编辑与调试；验证系统集成时运行脚本生成的 `.app`，保持应用标识与资源完整。

首次在新环境构建前，按[个人签名配置](docs/signing.md)导入固定签名身份。

## 打包

```bash
bash scripts/package.sh
```

生成仅支持 Apple Silicon（arm64）的 `.app`、`.dmg` 和 `-mac.zip`，保存在 `dist/`，不支持 Intel Mac。所有版本使用[固定个人签名身份](docs/signing.md)。版本及最低系统版本以 [Info.plist](build/Info.plist) 为准。

公开发布入口是 [Release 工作流](.github/workflows/release.yml)：更新 Info.plist 与[应用内更新日志](Sources/GlintCore/Resources/changelog.json)，完成验证后提交，再推送匹配的 `v*` 标签。工作流生成 Release 草稿，审核后由维护者发布。构建失败时，可从默认分支手动运行该工作流，输入原标签重新构建，无需移动标签。

## 数据

原生版首次启动会导入旧 Glint 的设置、历史和生词本，保留原文件并另存备份。原生版使用独立目录 `~/Library/Application Support/com.skywalker144.glint`，导入与持久化实现见 [LocalStore](Sources/GlintCore/LocalStore.swift)。API Key 沿用本地设置存储。

[开发索引](docs/README.md)包含实现入口、验证命令和系统集成验收范围。
