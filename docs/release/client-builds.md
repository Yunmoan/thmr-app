# 客户端发布

[返回发布指南](README.md)

## 版本与说明

版本优先取 `v` 标签，然后是手动构建的版本参数，最后取 [`pubspec.yaml`](../../pubspec.yaml)。CI 构建号使用 `run number × 100 + run attempt`。本地构建默认使用 `pubspec.yaml`，可以用 `--build-name` 和 `--build-number` 覆盖。版本解析规则见 [`resolve_version.py`](../../tool/resolve_version.py)。

在 [`CHANGELOG.md`](../../CHANGELOG.md) 的 `## 版本号` 小节维护拟发布的更新说明。缺少对应段落时，CI 会在构建前停止。预发布版本可以使用同一数字版本的说明。发布页正文、`RELEASE_NOTES.md` 附件和签名清单中的 `notes` 都由这个文件生成。

## 构建与发布

| 触发方式 | 结果 |
| --- | --- |
| Pull request | [Build Clients](../../.github/workflows/build.yml) 生成 Actions Artifacts。 |
| 默认分支推送、手动运行 | 构建 `build-版本-构建号` 预发布 Release。 |
| `v<版本>` 标签推送 | 稳定标签发布正式 Release，预发布标签如 `v<版本>-rc.1` 生成预发布 Release。 |

各平台会在通过验证后上传到同一 GitHub Release 草稿。全部平台成功后，工作流上传校验和与发布说明并发布 Release。稳定标签需要更新签名和 Android 正式签名。普通预览构建在公钥与私钥均未配置时，仍会上传安装包、校验和与发布说明，省略更新清单。正式 Release 的签名清单需再部署到更新 API，客户端才会发现新版。 [更新签名与部署](update-api.md)

同一稳定版本需要发布更高构建号时，等待默认分支的 **Build Clients** 成功，将该次提交打上 `v<版本>+<构建号>` 标签，然后在该标签上运行 [Finalize Existing Release](../../.github/workflows/finalize-release.yml)，输入构建运行 ID、版本和构建号。该流程校验并替换原正式 Release 的产物与清单。发布任务完成后，稳定版本的新构建会分发到配置好的 TestFlight 渠道。 [TestFlight 上传与补传](testflight.md#上传与分发)

## 平台签名

更新清单签名与平台包签名各有用途。清单配置见 [更新 API 与镜像](update-api.md#更新签名)。iOS 的签名在独立的 [TestFlight 环境](testflight.md#github-actions-签名) 配置。

### Android

在仓库的 Actions Secrets 配置固定的签名材料。对已部署的应用沿用原 keystore，系统按签名判断能否覆盖安装。

| Secret | 用途 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 正式 keystore 的 Base64 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 密钥密码 |

本地签名方式见 [Android Gradle 配置](../../android/app/build.gradle.kts)。可通过忽略提交的 `android/key.properties` 或 `THMR_ANDROID_KEYSTORE_PATH`、`THMR_ANDROID_KEYSTORE_PASSWORD`、`THMR_ANDROID_KEY_ALIAS`、`THMR_ANDROID_KEY_PASSWORD` 环境变量配置，开发构建可使用 debug keystore。

### macOS

公开分发可在仓库 Actions Secrets 配置以下材料。[`macos_distribution.sh`](../../tool/macos_distribution.sh) 使用同一个通用 `.app` 生成首次安装用的 DMG 和自更新用的 ZIP，并按配置签名、公证和 staple。未提供 Developer ID 证书时使用 ad-hoc 签名。

| Secret | 用途 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Developer ID Application 证书与私钥的 `.p12`（Base64） |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `MACOS_CODESIGN_IDENTITY` | Developer ID Application 签名身份 |
| `APPLE_API_KEY_P8` | App Store Connect API Key 的 `.p8` 原文 |
| `APPLE_API_KEY_ID` | Key ID |
| `APPLE_API_ISSUER_ID` | Issuer ID |

## 产物与验收

可分发的包及安装方法见 [安装说明](../user/install.md)。同时分发 macOS ZIP 时，自更新镜像必须使用 ZIP。macOS 构建验证每个 Mach-O 的 Intel 与 Apple Silicon 架构、签名和权限，并在运行器的原生架构启动应用。另一架构的启动需要实机确认。Linux 产物需要完整保留 `bundle/`，并按 [Linux 构建与验证](../development/linux.md) 检查运行依赖。

在要支持的平台从实际分发的版本覆盖更新，检查用户数据保留、启动成功和失败回滚。Android 使用同一签名检查系统覆盖安装，macOS 用实际分发包检查公证与两个架构的首次启动。
