# 更新 API 与镜像

[返回发布指南](README.md) · [客户端发布](client-builds.md)

## 更新签名

在仓库根目录使用 Node.js 生成 Ed25519 密钥。命令输出 Base64 公钥，私钥保存到指定的 PEM 文件。

```sh
node tool/update_release.cjs keygen --output .update-keys/thmr-ed25519.pem
```

在 GitHub 仓库 **Settings → Secrets and variables → Actions** 设置：

| 类型 | 名称 | 用途 |
| --- | --- | --- |
| Variable | `THMR_UPDATE_PUBLIC_KEY` | Base64 公钥，正式标签构建需要配置 |
| Variable | `THMR_UPDATE_API_URL` | 可选，配置客户端 GET 地址，默认值见 [`update_manifest.dart`](../../lib/core/update/update_manifest.dart) |
| Secret | `THMR_UPDATE_PRIVATE_KEY` | 私钥的完整 PEM 内容，包含首尾行 |

已发出的客户端、服务端验签和 CI 必须使用同一对密钥。私钥只用于签名，服务器和客户端都使用公钥。保管密钥及离线备份，换钥需要先安排客户端迁移。本地构建可用 Flutter 的 `--dart-define` 设置公钥与检查地址。

## 插件部署

更新插件由 OPENAPI-Next-Core 服务独立交付。选择与部署包对应的方式，服务中只启用一个同名入口。

| 方式 | 插件入口 | 私有配置和清单目录 |
| --- | --- | --- |
| Next ZIP，经管理后台安装为 `updater` | `apis/updater/index.js` | `apis/updater/data/` |
| 单文件包，解压到 OpenAPI 项目根目录 | `apis/updater.js` | `data/updates/` |

Next ZIP 内包含插件入口、`manifest.json` 和私有 `data/`。覆盖更新会替换插件目录，升级前备份并恢复 `data/`，或将配置和清单指向目录外的持久化文件。单文件包应出现上述根目录层级，使用能够直接访问项目文件的部署方式。

`thmr-config.json` 在私有目录内定义 `publicKey` 和可选的 `publishToken`。可通过服务进程环境变量 `THMR_UPDATE_PUBLIC_KEY`、`THMR_UPDATE_PUBLISH_TOKEN` 覆盖对应字段，以 `THMR_UPDATE_CONFIG`、`THMR_UPDATE_MANIFEST` 指定绝对路径。服务账户需要读取权限，私有文件应留在 Web 静态目录之外。

`GET /updater/thmr` 通过 HTTPS 返回签名清单。需要服务端推送时可使用 `POST /updater/thmr/publish`，配置独立的发布凭据、目录写入权限，并让代理传递 Bearer 授权头和允许 1 MiB JSON 请求。

## 更换镜像和清单

1. 从同一个正式 Release 下载相应安装包和 `thmr-update.json`。原样上传安装包到 HTTPS 镜像。
2. 在插件入口的 `THMR_DOWNLOAD_URLS` 设置 `windows`、`macos`、`linux`、`android` 对应的完整下载地址。macOS 使用 `thmr-app-macos-universal.zip`。留空的平台使用签名清单中的下载地址。修改 JS 配置后重载插件。
3. 将同一个 Release 的签名清单原样放入插件读取的私有目录。接受 `thmr-release.json` 和 `thmr-update.json`，两者同时存在时前者优先，保留一个即可。使用了 `THMR_UPDATE_MANIFEST` 时以指定路径为准。仅替换文件后下一次请求即会读取。

安装包的字节数、SHA-256、格式、版本与构建号都由签名保护。镜像地址由外层 `download_urls` 提供，镜像变更可复用签名。替换包内容或更新说明时，必须重新生成清单并签名。

## 核验与定位

```sh
node tool/update_release.cjs inspect --file thmr-release.json --public-key BASE64_PUBLIC_KEY
```

清单外层存放 `schema`、`algorithm`、`payload` 与 `signature`。验签使用 Base64 解码后的原始字节。版本和构建号等发布字段由该命令验签并解码；`thmr-config.json` 只负责服务配置。字段、签名和架构映射以 [清单生成工具](../../tool/update_release.cjs) 和 [客户端解析器](../../lib/core/update/update_manifest.dart) 为准。

| 症状 | 核对 |
| --- | --- |
| Next 插件状态 | `GET /updater/thmr/status` 返回 `ready` 时检查版本与构建号，其他状态可定位配置或验签故障。 |
| 检查接口返回 204 | 查看服务日志中的有效清单路径，确认文件名、部署目录和读取权限。 |
| 检查接口返回 503 | 核对服务端配置、公钥、文件可读性和原始签名清单。 |
| 返回 200 仍未提示更新 | 核对客户端使用的 API 地址、公钥、平台、版本和构建号。客户端先比较版本，同一版本再比较构建号。 |
| 下载校验失败 | 比较镜像和同一 Release 中对应安装包的字节数与 SHA-256，检查 macOS 是否使用 ZIP。 |
