# 本次配置结果

2026-11-04 已完成：

- 复用本机现有的 Ed25519 更新签名密钥，客户端已内置对应公钥。
- GitHub 已设置更新 API 地址、公钥，以及 6 项加密 Secrets：更新私钥、API 发布凭据、Android keystore 与密码/别名。
- 已创建 Android 长期正式签名；本机 `android/key.properties` 也已配置，后续 Release 构建自动使用该签名。
- 构建产物自动上传 GitHub Release，客户端向 `https://api.zyghit.cn/updater/thmr` 检查更新。

## 以后每次更新怎么操作

1. 从 GitHub Release 下载四个平台的安装包，保持原文件上传到内部镜像。
2. 打开 API 的 `apis/updater.js`，修改文件顶部的四个完整 HTTPS 地址：

```js
const THMR_DOWNLOAD_URLS = {
    windows: 'https://你的镜像/thmr-app-windows-x64.zip',
    macos: 'https://你的镜像/thmr-app-macos-universal.zip',
    linux: 'https://你的镜像/thmr-app-linux-x64.tar.gz',
    android: 'https://你的镜像/thmr-app-android.apk',
};
```

3. 从**同一个 Release**下载 `thmr-update.json`，重命名为 `thmr-release.json`，放到 API 的 `data/updates/` 文件夹。
4. 重载 updater 插件或重启 API。客户端即可检查、下载并验证新版。

地址留空时使用该版 GitHub Release 地址。macOS 只填一个通用包地址。搬运时保持原包字节不变，不能解压重打包；版本、大小、SHA-256 来自签名清单，不需要手改。

普通 main / 手动构建会生成 `build-版本号-构建号` 预发布 Release；`v0.2.0` 这类稳定标签生成正式 Release。每个平台成功后立即上传对应包到同一个 Release 草稿，仓库所有者可先下载；全部完成后补充签名清单与校验和并自动发布。PR 仅保留 Actions 产物。

## API 首次部署

预配置部署包在项目本机的 `.update-keys/api-upload.zip`。

1. 将压缩包里的 `apis` 和 `data` 文件夹放到 **OpenAPI 项目根目录**，覆盖对应文件；不要放进 `public`。
2. 重新加载 updater 插件或重启 API 服务。文件参数已填好，不用再创建密钥或设置环境变量。
3. 按上面的步骤填镜像地址并上传签名清单。清单缺失时读取接口返回 `204`，表示尚未发布新版本。

此流程通过上传文件发布更新。若以后改用可选的 POST 发布接口，它仍需要把服务器 `config.ini` 的 `[security] maxPostSizeKB` 设为 `1024` 后重启，以解决此前实测的 `413`。

## Android 首次安装

你已选择改用正式签名。旧调试签名 App 首次需要卸载再安装新的 APK；后续保持此密钥即可覆盖更新。

密钥与密码保存在本机 `.update-keys/`，均已排除 Git 跟踪，请备份此文件夹。API 上传包只含发布凭据，不含 Android keystore 或更新签名私钥。

## macOS

macOS 默认使用 ad-hoc 开发签名构建通用包，无需提供 Apple 证书。GitHub 的 arm64 托管运行器出现容量不足，当前改用稳定版 Intel 运行器，仍核对 Intel / Apple Silicon 两种架构。可用仓库 Variable `THMR_MACOS_RUNNER` 调整运行器。

公开分发的 Apple 公证可之后补齐 Developer ID 证书与 API Key。

高级说明见 [完整配置文档](AUTO_UPDATE.md)。
