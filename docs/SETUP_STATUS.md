# 本次配置结果

2026-11-04 已完成：

- 复用本机现有的 Ed25519 更新签名密钥，客户端已内置对应公钥。
- GitHub 已设置更新 API 地址、公钥，以及 6 项加密 Secrets：更新私钥、API 发布凭据、Android keystore 与密码/别名。
- 已创建 Android 长期正式签名；本机 `android/key.properties` 也已配置，后续 Release 构建自动使用该签名。
- 下载包默认由 GitHub Release 托管，检查与发布清单使用 `https://api.zyghit.cn/updater/thmr`。

## API 上传后的检查结果

预配置部署包在项目本机的 `.update-keys/api-upload.zip`。

1. 将压缩包里的 `apis` 和 `data` 文件夹放到 **OpenAPI 项目根目录**，覆盖对应文件；不要放进 `public`。
2. 重新加载 updater 插件或重启 API 服务。文件参数已填好，不用再创建密钥或设置环境变量。
3. 若发布接口返回 `413`，把服务器 `config.ini` 的 `[security]` 中 `maxPostSizeKB` 设为 `1024`，然后重启服务。

本次实测：读取接口返回 `204`，表示已上线但尚未发布新版本；发布接口仍返回 `413`，需要完成上面第 3 步。请求体使用空对象，不会发布或覆盖版本清单。

请求大小限制修好后，推送 `v0.2.0` 这类正式标签，构建成功后会自动生成签名清单并发布到 API。

## Android 首次安装

你已选择改用正式签名。旧调试签名 App 首次需要卸载再安装新的 APK；后续保持此密钥即可覆盖更新。

密钥与密码保存在本机 `.update-keys/`，均已排除 Git 跟踪，请备份此文件夹。API 上传包只含发布凭据，不含 Android keystore 或更新签名私钥。

## macOS

macOS 构建及自更新代码已配置。尚未提供 Apple Developer ID / 公证材料，当前构建使用本地签名；Apple 公证需之后补齐证书与 API Key，无法通过生成普通本地密钥代替。

高级说明见 [完整配置文档](AUTO_UPDATE.md)。
