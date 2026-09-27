# Glint

macOS 桌面翻译工具，使用 Tauri 2、Rust 和原生 TypeScript。

- [产品方案](docs/product.md)
- [开发与验收](docs/development.md)

```sh
npm ci
npm run desktop
```

首次启动会下载并校验 ECDICT 数据，构建离线 SQLite 词典和 Swift 原生桥。需要 macOS 13+、Node.js 22.12+、Rust 和 Xcode Command Line Tools。

```sh
npm run bundle
```

本地应用生成于 `src-tauri/target/release/bundle/macos/Glint.app`。这是开发构建流程，不包含发布、签名身份配置或公证。
