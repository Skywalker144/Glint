# 个人签名

[公开证书](../build/signing.pem)固定 Glint 的签名身份。[签名脚本](../scripts/signing.sh)负责证书创建、导入、签名与校验；[构建脚本](../scripts/build.sh)统一调用它，Debug 与 Release 沿用同一证书。

## 本机与备份

私钥归档 `.signing/identity.p12` 和密码文件 `.signing/password` 保存在项目本地，已被 Git 忽略。请一起备份这两个文件；换电脑或重装时恢复原身份。公开证书已存在时，`create` 会拒绝生成新身份。

从备份导入：

```bash
GLINT_SIGNING_P12_BASE64=$(base64 -i /path/to/identity.p12) \
GLINT_SIGNING_PASSWORD=$(cat /path/to/password) \
bash scripts/signing.sh import
```

导入后使用 README 中的构建与打包命令。专用钥匙串位于 `.signing/Glint.keychain-db`。

## GitHub Actions

[Release 工作流](../.github/workflows/release.yml)从仓库 Actions Secrets 导入同一身份：

```bash
base64 -i .signing/identity.p12 | gh secret set GLINT_SIGNING_P12_BASE64 --repo Skywalker144/Glint
gh secret set GLINT_SIGNING_PASSWORD --repo Skywalker144/Glint < .signing/password
```

公开证书随源码提交，私钥归档与密码仅进入 Secrets。证书缺失或不匹配会阻止构建和发布。此流程使用个人自签名证书，无需 Apple Developer 账号。

## 验证

```bash
bash scripts/test-signing.sh
bash scripts/swift.sh test --disable-xctest --filter UpdateSignatureTests
bash scripts/signing.sh verify dist/Glint.app
```

[签名测试](../Tests/GlintTests/UpdateSignatureTests.swift)使用真实编译与签名验证不同二进制之间的身份延续，并拒绝改签、无签名和被篡改的更新。[更新校验](../Sources/Glint/UpdateSignature.swift)以当前版本的 designated requirement 检查下载包和安装副本。

从 ad-hoc 版本首次切换到此身份时，需要移除旧的辅助功能条目，添加并授权新签名的 Glint。真实系统验收需先授权一个签名版本，再通过应用内更新安装下一签名版本，确认划词翻译可直接使用、辅助功能状态保持已授权。构建与签名测试不能替代这一步。
