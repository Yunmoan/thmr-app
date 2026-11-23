# TestFlight 签名与分发

[返回发布指南](README.md) · [iOS 本地开发](../development/ios.md)

## Apple 后台

1. 在 Apple Developer 中创建显式 App ID，Bundle ID 使用 [Runner 工程](../../ios/Runner.xcodeproj/project.pbxproj) 的 `cn.yunmoan.thmr`。已有同团队 App ID 时可复用。 [注册 App ID](https://developer.apple.com/help/account/identifiers/register-an-app-id/)
2. 使用同一个团队，在 App Store Connect 创建 iOS 应用，选中此 Bundle ID，设置应用名称、主要语言和 SKU。 [创建 App 记录](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)
3. 创建 **Apple Distribution** 证书并连同私钥导出带密码的 `.p12`。为 App ID 和此证书创建 **App Store Connect** 描述文件，下载 `.mobileprovision`。 [签名证书](https://developer.apple.com/help/account/certificates/certificates-overview/) · [描述文件](https://developer.apple.com/help/account/provisioning-profiles/create-an-app-store-provisioning-profile)
4. 在 App Store Connect 的 **Users and Access → Integrations → App Store Connect API → Team Keys** 创建有上传权限的团队 API Key，记录 Key ID 与 Issuer ID，保存 `.p8`。 [团队 API Key](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/) · [上传构建的角色权限](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)

## GitHub Actions 签名

在仓库 **Settings → Environments** 创建 `testflight` 环境。如果限制可以部署的标签，允许工作流使用的 `v*` 标签。将下面的值添加为该环境的 Secrets。

| Secret | 内容 |
| --- | --- |
| `IOS_CERTIFICATE_BASE64` | `.p12` 的 Base64 |
| `IOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `.mobileprovision` 的 Base64 |
| `IOS_APP_STORE_CONNECT_KEY_ID` | 团队 API Key 的 Key ID |
| `IOS_APP_STORE_CONNECT_ISSUER_ID` | 团队 API 的 Issuer ID |
| `IOS_APP_STORE_CONNECT_KEY_P8` | `.p8` 的完整原文，包括首尾行 |

在 macOS 可逐项把文件内容复制到剪贴板，再分别录入对应 Secret。

```sh
base64 -i THMR-Distribution.p12 | pbcopy
base64 -i THMR-AppStore.mobileprovision | pbcopy
pbcopy < AuthKey_YOUR_KEY_ID.p8
```

## 上传与分发

[客户端发布](client-builds.md#构建与发布) 后会调用 [Upload iOS to TestFlight](../../.github/workflows/ios-testflight.yml)。上传任务先核对稳定 Release 的版本与构建号，然后从相应源码构建、签名、导出并上传 IPA。首次正式发布允许在所有 iOS Secrets 均为空时跳过上传，部分配置会报错。同版本构建更新要求完整签名。

补传时，在已发布的版本或构建标签上手动运行上传工作流，填写正式 Release 的版本和构建号。也可以从包含上传工作流的提交创建 `v<版本>+<构建号>-testflight` 标签，再选中该标签手动运行，任务仍从 `v<版本>+<构建号>` 读取源码。对失败的运行可以重试失败的任务。

Apple 处理构建后，在 **Apps → THMR → TestFlight** 将该构建加入测试组。团队成员使用内部组，其他测试者使用外部组，按 Apple 流程提交 Beta 审核并发送邀请。上传前核对 Apple 的 SDK 要求。 [TestFlight 说明](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/) · [Apple 上传要求](https://developer.apple.com/news/upcoming-requirements/)

[`Info.plist`](../../ios/Runner/Info.plist) 中的 `ITSAppUsesNonExemptEncryption` 随包一起提交。调整加密依赖或分发范围时，重新核对 Apple 出口合规要求，同时复查播放器所用库。 [Apple 加密合规说明](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)
