# iOS 开发与 TestFlight

THMR 支持 iOS 15 及以上。GitHub Actions 使用 `macos-26` 运行器构建 iOS。Apple 要求上传构建使用 iOS 26 SDK 或更新版本。 [Apple 的 SDK 要求](https://developer.apple.com/news/?id=ueeok6yw)

## 在 Apple 后台创建 THMR

1. 在 Apple Developer 选中持有 Apple Developer Program 会员资格的团队，进入 **Identifiers → + → App IDs → App**。Description 可填 `THMR iOS`，Bundle ID 选择 **Explicit**，输入 `cn.yunmoan.thmr`，然后注册。如果团队已有这个标识，直接使用现有标识。注册需要 Account Holder 或 Admin 权限。 [打开 Identifiers](https://developer.apple.com/account/resources/identifiers/list) · [Apple 的 App ID 注册步骤](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
2. 使用同一团队登录 App Store Connect，进入 **Apps → + → New App**。平台选 **iOS**，名称填 `THMR`（若已被占用，填可用的名称），主要语言选简体中文，Bundle ID 选刚注册的标识，SKU 可填 `thmr-ios`。按团队需要设置用户访问范围，点击 **Create**。如界面提示协议待处理，由 Account Holder 在 **Business** 中处理。 [打开 App Store Connect](https://appstoreconnect.apple.com/) · [创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)

Bundle ID 必须与 `ios/Runner.xcodeproj` 的 Runner target 一致。如果 Apple 提示该 ID 已被另一团队使用，先确定团队拥有的新 ID，再同步修改 Runner 的 Debug、Profile 和 Release 配置。

## 为 GitHub Actions 配置签名

1. 在有私钥的 Mac 上导出 **Apple Distribution** 签名身份。若需要新证书，在「钥匙串访问」的证书助理中将证书签名请求（CSR）存到磁盘，在 Apple Developer 的 **Certificates → + → Apple Distribution** 上传 CSR 并下载 `.cer`。在生成 CSR 的同一台 Mac 上导入 `.cer`，在「我的证书」里选中证书和关联私钥，导出带密码的 `.p12`。也可以通过 Xcode 的 **Settings → Accounts → Manage Certificates** 创建证书。 [Apple 的证书说明](https://developer.apple.com/help/account/certificates/certificates-overview/)
2. 在 Apple Developer 的 **Profiles → + → Distribution → App Store Connect** 创建描述文件，选择 THMR 的显式 App ID，以及上一步导出的证书。生成并下载 `.mobileprovision`。 [创建 App Store Connect 描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
3. 在 App Store Connect 的 **Users and Access → Integrations → App Store Connect API → Team Keys** 创建团队 API Key，可选 **Developer** 权限用于上传。首次使用 API 时由 Account Holder 申请访问。记下 **Key ID** 和 **Issuer ID**，下载 `AuthKey_*.p8` 并妥善保存。 [团队 API Key](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/) · [上传构建的角色权限](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
4. 在 GitHub 仓库进入 **Settings → Environments**，创建 `testflight` 环境。在 **Deployment branches and tags** 中可选择 **Selected branches and tags**，添加 `v*` 的 Tag 规则。把下列值录入 **Environment secrets**。

| Secret | 值 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | `.p12` 文件的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 文件的 Base64 |
| `IOS_APP_STORE_CONNECT_KEY_ID` | 团队 API Key 的 Key ID |
| `IOS_APP_STORE_CONNECT_ISSUER_ID` | 团队 API 的 Issuer ID |
| `IOS_APP_STORE_CONNECT_KEY_P8` | `.p8` 文件的完整原文，包括首尾行 |

在 macOS 上可以逐项把值复制到剪贴板，然后分别粘贴到对应的 Secret。

```bash
base64 -i THMR-Distribution.p12 | pbcopy
base64 -i THMR-AppStore.mobileprovision | pbcopy
pbcopy < AuthKey_YOUR_KEY_ID.p8
```

## 发版和邀请测试者

PR、`main` 推送和手动运行 **Build iOS** 都只做无签名的 iOS 编译检查。正式发版时，更新 `CHANGELOG.md`，把包含 iOS 配置的提交打上稳定版本标签（例如 `v0.2.0`）并推送。**Build Clients** 成功发布 GitHub Release 后，会启动 **Upload iOS to TestFlight**。这次独立运行使用 Release 的版本号和构建号签名、导出 IPA 并上传到 App Store Connect。所有 iOS Secrets 留空时，首发流程会跳过上传。部分配置时任务会列出缺少的项。上传失败时可重跑上传工作流中的失败任务。 [现有 GitHub 发版流程](AUTO_UPDATE.md#5-发版链路)

Apple 处理构建后，在 **App Store Connect → Apps → THMR → TestFlight** 添加测试组和构建。团队成员使用内部组，可打开自动分发。团队外的朋友使用外部组，按 Apple 要求填写测试资料并提交首个外测构建审核，通过后可用邮件或测试链接邀请。测试者从 TestFlight 安装，每个构建最多可测试 90 天。 [Apple TestFlight 说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)

`Info.plist` 按当前 TestFlight 分发设置了 `ITSAppUsesNonExemptEncryption = false`。iOS 原生播放库包含标准 TLS 实现 Mbed TLS，Apple 的判断范围包括这类第三方库。若将来修改加密依赖或分发范围，重新核对该声明。 [Apple 加密声明](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) · [Apple 出口合规材料要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)

## 在 Mac 上开发

从 Apple Developer 安装适配本机 macOS 版本的完整 Xcode。macOS Sequoia 15.6 及以上可使用 Xcode 26.3。首次启动后选择命令行工具并安装 iOS 模拟器。 [下载 Xcode 26.3](https://developer.apple.com/download/all/?q=Xcode%2026.3) · [Xcode 系统要求](https://developer.apple.com/xcode/system-requirements)

安装 CocoaPods，已有 Homebrew 时可运行 `brew install cocoapods`。仓库用 CocoaPods 提供 libmpv 音频框架，并将文件选择器编译为文档导出所需的功能。 [CocoaPods 安装说明](https://guides.cocoapods.org/using/getting-started.html)

本地工具若安装在项目的 `.toolchains/`，在仓库根目录执行 `export PATH="$PWD/.toolchains/flutter/bin:$PWD/.toolchains/bin:$PATH"` 后再运行以下命令。

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS

export FLUTTER_SWIFT_PACKAGE_MANAGER=false
flutter doctor -v
flutter pub get --enforce-lockfile
open -a Simulator
flutter devices
flutter run -d DEVICE_ID
```

将 `DEVICE_ID` 换成 `flutter devices` 列出的模拟器 ID。也可用 `flutter build ios --release --no-codesign` 检查真机架构的编译结果。使用真机调试时，先执行 `flutter build ios --config-only --no-codesign`，再用 Xcode 打开 `ios/Runner.xcworkspace`，在 **Runner → Signing & Capabilities** 启用自动签名并选中同一个 Apple 团队。

首个 TestFlight 包可用 iPhone 验证首次启动、直播播放、锁屏后播放及控制中心暂停与恢复，再检查登录和诊断报告导出。
