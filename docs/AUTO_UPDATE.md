# THMR 自动更新：部署与发布

本次已代为配置的结果和剩余上传步骤见 [配置结果](SETUP_STATUS.md)。已有部署包时，直接上传包里的 `apis` 和 `data`，无需重复生成密钥或手工配置下面列出的 Secrets。

## 1. 完成后的行为与平台边界

客户端只向 **`https://api.zyghit.cn/updater/thmr`** 检查更新，不再请求 GitHub 的发布 API。默认后台下载新版，验证 Ed25519 签名、架构、文件大小与 SHA-256；用户点击安装后，由程序完成后续操作，无需浏览器下载和手工解压。

| 平台 | 安装方式 | 必要条件 |
| --- | --- | --- |
| Windows x64 | 关闭旧进程、替换完整目录、重启；新版启动失败自动恢复旧目录 | 完整便携包放在当前用户可写的独立目录；不要只更新 exe |
| macOS Intel / Apple Silicon | 校验 `.app` 签名和 Bundle ID、替换应用、重启；失败恢复 | 直接分发的非沙盒版本；目录可写；公开分发应配置 Developer ID 与 Apple 公证 |
| Linux x64 | 替换完整 `bundle`、重启；失败恢复 | 当前用户可写的独立便携目录；系统提供 libmpv/GTK 等运行库 |
| Android | 后台下载并校验 APK，核对包名、版本码和签名后打开系统安装器 | 首次允许 THMR 安装应用；**系统要求用户确认安装**；每次发布保持相同签名密钥 |
| iOS | 不启用此自更新器 | 通过 App Store / TestFlight 分发与更新 |

下载不会自动退出正在使用的应用。桌面端在点击“安装并重启”后自动完成替换；重启后需要成功渲染首帧、经过 3 秒无 Flutter 启动错误并返回事务回执，否则 60 秒后恢复旧版。数据和设置仍在系统应用数据目录，不放进被替换的程序目录。

本机制面向本仓库输出的 zip / tar.gz / APK；不替换系统包管理器安装的 DEB/RPM、只读目录、Mac App Store 或 Google Play 的更新渠道。Windows `Program Files` 等受保护目录需要改用有权限的安装方案，不会偷偷请求管理员权限或修改系统策略。

macOS 首次安装使用 `thmr-app-macos-universal.dmg`，带安装引导背景、THMR 图标和 Applications 拖拽入口。请先拖入 Applications，再启动应用。另附的 `thmr-app-macos-universal.zip` 专供现有自更新器使用，更新镜像仍填写 ZIP 地址；DMG 和 ZIP 来自同一个签名后的 `.app`。

## 2. 先生成更新签名密钥

在可信本机安装 Node.js 22+，在仓库根目录运行：

```powershell
node tool/update_release.cjs keygen --output .update-keys/thmr-ed25519.pem
```

命令只输出 **Base64 公钥**，私钥写入指定 PEM 文件，已通过 `.gitignore` 排除；再次执行不会覆盖旧密钥。保管好私钥和离线备份。此密钥用于更新清单，独立于 Android 签名与 Apple Developer ID。

把输出的同一个公钥配置到客户端构建和 API 服务器。**私钥只交给发布 CI，服务器只需要公钥。** 不要把私钥或发布 token 写入 JS 插件、客户端、仓库或公开配置文件。首次发出的客户端必须已经包含正确公钥，之后不能只修改服务器公钥，否则旧客户端会拒绝新签名；换钥需要专门的迁移版本。

## 3. 部署更新插件

推荐使用为 OPENAPI-Next-Core 制作的私有 Next 包 `.update-keys/thmr-updater-next.zip`。在后台上传 ZIP，插件名为 `updater`，启用覆盖更新，即可替换原 legacy 单文件插件。ZIP 内含 `updater/index.js`、`manifest.json`、说明和 `data/thmr-config.json`；生成时可附带已验签的客户端发布清单。包内含发布凭据，不上传公开仓库或 Release。

Next 安装后，私有文件位于 `apis/updater/data/`。`GET /updater/thmr/status` 返回 `ready` 和已验签的客户端 `version` / `build_number`；其他状态区分清单缺失、配置无效、清单不可读及验签失败。`GET /updater/thmr` 继续兼容现有客户端，`/updater/ofcpl` 保留。

后续只更新该目录中的签名清单，无需重装插件。后台覆盖升级会删除原插件目录，升级插件前备份 `data` 并在升级后恢复，或设置下方环境变量使用目录外的持久化文件。Next 本地配置不存在时仍兼容旧根目录配置。

### 保留 legacy 单文件安装

交付文件：独立部署包中的 `apis/updater.js`（本机源文件位于 `server-plugin/updater.js`，该目录不提交到客户端仓库）。它保留你提供的 `/ofcpl` 响应，只新增 THMR 路由，使用现有 Express 和 Node 内置模块，无需安装新的运行依赖。

1. 备份原 `apis/updater.js`，再将交付文件复制到该位置；按现有 OpenAPI 插件机制加载。文件名保持 `updater.js`。
   也支持在 `data/updates/thmr-config.json` 保存私有的 `publicKey` 与 `publishToken`，插件会自动读取；预配置部署包已经填好该文件。环境变量的优先级高于此文件。
2. 在 **OpenAPI 服务进程**的环境中设置以下值，然后重启服务。使用 systemd、容器或进程管理器的私有配置保存，不向前端暴露。

| 服务端环境变量 | 值 |
| --- | --- |
| `THMR_UPDATE_PUBLIC_KEY` | 上一步输出的 Base64 公钥 |
| `THMR_UPDATE_CONFIG` | 可选，私有配置的绝对路径；Next 默认 `apis/updater/data/thmr-config.json`，legacy 默认 `data/updates/thmr-config.json` |
| `THMR_UPDATE_MANIFEST` | 可选，清单的绝对路径；默认与选中的配置同目录，识别 `thmr-release.json` 和 `thmr-update.json`；显式指定时严格读取该路径 |
| `THMR_UPDATE_PUBLISH_TOKEN` | 随机发布凭据，至少 32 字符；与 GitHub Secret 中的值相同 |

可以用 `node -e "console.log(require('node:crypto').randomBytes(32).toString('hex'))"` 生成发布凭据。清单父目录必须允许服务账户写入。插件原子替换清单，校验发布签名并拒绝版本倒退。

3. 为公开 GET 更新检查提供 HTTPS，并确保没有面向网页的验证码或交互挑战。可选的 POST 发布工具还需要代理保留 `Authorization` 请求头、允许 `/updater/thmr/publish`，并为 JSON 请求留出 1 MiB 上限；文件上传发布方式使用上面的清单文件路径。
4. 检查 `https://api.zyghit.cn/updater/thmr`。尚未发布清单时返回 **204**；有有效签名清单时返回 **200**；已存在的清单损坏、签名错误或公钥未正确配置时返回 **503**，不会伪装成“已经是最新版”。

### OPENAPI-Next-Core 的文件位置

已核对 [OPENAPI-Next-Core 插件加载器](https://github.com/ZGIT-Network/OPENAPI-Next-Core/blob/18b170a51c63b4128ba300de60c2966c43e77ed1/core/pluginManager.js) 和 [静态资源挂载](https://github.com/ZGIT-Network/OPENAPI-Next-Core/blob/18b170a51c63b4128ba300de60c2966c43e77ed1/index.js)：插件通过 Node `require` 加载，可用 `fs` 读取服务器本地文件；只有 `public` 目录作为静态资源发布。客户端请求 `/updater/thmr`，由插件读取并验签本地清单后返回 JSON，**不会请求 `/data/updates/...`**。

手动部署时把 `api-upload.zip` 解压到包含 `index.js`、`config.ini` 的项目根目录，得到：

```text
<OpenAPI>/
  index.js
  apis/updater.js
  data/updates/thmr-config.json
  data/updates/thmr-release.json  # 另从对应客户端 Release 下载部署
```

`data` 不需要对公网可访问，也不要移入 `public`；`thmr-config.json` 含发布凭据。服务进程需要有这些文件的读取权限；使用 POST 发布时还需要该目录的写入权限。

**上述 `api-upload.zip` 根目录部署包不能交给管理后台的“上传 ZIP 安装插件”。** [后台安装器](https://github.com/ZGIT-Network/OPENAPI-Next-Core/blob/18b170a51c63b4128ba300de60c2966c43e77ed1/core/adminPluginsApi.js) 只会把 ZIP 内容写到 `apis/<插件名>/`。后台安装应改用专门的 `thmr-updater-next.zip`：入口为 `apis/updater/index.js`（带 `manifest.json`），配置和清单放在 `apis/updater/data/`。不要同时保留同名的单文件和目录插件。

判定方式：`/data/updates/...` 返回 404 是预期行为；`/updater/thmr` 的 200 才表示清单可用。204 仅说明插件解析到的清单路径不存在，也可能是目录层级错误，不能仅凭 204 判断文件一定未上传。

现有 `apis/updater.js` legacy 单文件安装无需改为目录插件。加载时控制台会打印 `Configuration file` 与 `Release manifest` 的绝对路径；根据此日志核对文件是否上传到位、服务账户是否有读取权限。手动替换有效的清单后，下次 GET 会重新读取，无需因清单变化重启；修改 JS 镜像配置时才需热重载或重启。

### 手动修改镜像地址

直接修改 Next 插件 `apis/updater/index.js`（legacy 为 `apis/updater.js`）**顶部**的 `THMR_DOWNLOAD_URLS`：

```js
const THMR_DOWNLOAD_URLS = {
    windows: 'https://你的镜像/thmr-app-windows-x64.zip',
    macos: 'https://你的镜像/thmr-app-macos-universal.zip',
    linux: 'https://你的镜像/thmr-app-linux-x64.tar.gz',
    android: 'https://你的镜像/thmr-app-android.apk',
};
```

先把 Release 原始安装包上传到镜像，再修改这四个完整 HTTPS 地址；macOS 通用包只填一次。地址留空使用该版本的 GitHub Release 地址。将**同一个 Release** 的签名清单放到 Next 的 `apis/updater/data/`（legacy 为根目录 `data/updates/`）。可使用原名 `thmr-update.json`，也可改为 `thmr-release.json`；两者同时存在时优先读取后者，建议只保留一个。仅替换清单无需重启，修改 JS 镜像地址需要重载插件。

镜像地址通过响应中的 `download_urls` 提供，客户端先验签，再使用镜像位置下载，仍强制核对签名保护的版本、文件大小、格式和 SHA-256。只改镜像地址不需要私钥，也不需要重新签名；不要改 `payload`、`signature` 或解压重打包安装文件。

路由：

| 请求 | 作用 |
| --- | --- |
| `GET /updater/ofcpl` | 保留原 CPL 更新响应 |
| `GET /updater/thmr` | THMR 签名更新清单，`Cache-Control: no-store` |
| `GET /updater/thmr/status` | Next 插件健康检查，显示已验签版本或故障类型，不返回凭据和本地路径 |
| `POST /updater/thmr/publish` | 带 `Authorization: Bearer <发布凭据>` 的发布请求 |

## 4. 配置 GitHub Actions

进入 **仓库 Settings → Secrets and variables → Actions**。

### Repository Variables（非机密）

| Variable | 必填 | 说明 |
| --- | --- | --- |
| `THMR_UPDATE_PUBLIC_KEY` | 是 | 同一个 Base64 公钥；正式标签构建缺少它会失败 |
| `THMR_UPDATE_API_URL` | 否 | 默认 `https://api.zyghit.cn/updater/thmr`，不要加 `/publish` |
| `THMR_MACOS_RUNNER` | 否 | 默认 `macos-26-intel`，避开当前 arm64 容量不足；恢复后可填 `macos-latest` |

CI 将安装包上传到 GitHub Release，**更新检查走你的 API**。下载后按上面的四个字段改成镜像地址。镜像搬运完成、清单文件上传后，客户端才会看到这次更新；构建工作流不自动提交更新到 API。

### Repository Secrets（机密）

| Secret | 必填 | 说明 |
| --- | --- | --- |
| `THMR_UPDATE_PRIVATE_KEY` | 是 | PEM 私钥文件的完整内容，包含 BEGIN/END 行 |
| `THMR_UPDATE_PUBLISH_TOKEN` | 可选 | 供可选的 POST 发布工具使用；当前默认通过上传清单文件发布 |
| `ANDROID_KEYSTORE_BASE64` | 正式标签必填 | 固定 Android keystore 文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | 正式 Android 必填 | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 正式 Android 必填 | 密钥别名 |
| `ANDROID_KEY_PASSWORD` | 正式 Android 必填 | 密钥密码 |

Android 版本码是 `Actions run number × 100 + run attempt`，完整重跑工作流会提高版本码；单独重试失败的平台沿用此次校验阶段确定的构建号，保持各包一致。普通本地构建使用 `pubspec.yaml` 的构建号，或显式传入 `--build-number`。

如果你有正在分发的 APK，使用**原来的 keystore**；不能为了这次更新随意换钥。旧版若使用了另一把 debug 密钥，Android 不能覆盖安装，需要先迁移到固定签名的首个版本；这不能靠绕过安装器解决。首次正式分发可用 JDK `keytool -genkeypair` 创建长期密钥。备份 keystore 与密码，不要提交仓库。

在 PowerShell 中把 keystore 转为 Base64：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\private\thmr-release.jks'))
```

### macOS Developer ID / 公证（公开分发时配置）

提供以下 Secrets 后，`tool/macos_distribution.sh` 会重签并公证应用、staple，再从同一个应用生成 ZIP 和 DMG；DMG 也会签名、公证和 staple。构建最终挂载只读 DMG，检查引导背景、Finder 布局、Applications 入口、应用签名和版本：

| Secret | 说明 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | 含私钥的 **Developer ID Application** `.p12` 的 Base64 内容 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 导出密码 |
| `MACOS_CODESIGN_IDENTITY` | 对应 `Developer ID Application: 名称 (TEAMID)` 签名身份 |
| `APPLE_API_KEY_P8` | App Store Connect API Key 的完整 `.p8` 内容 |
| `APPLE_API_KEY_ID` | API Key ID |
| `APPLE_API_ISSUER_ID` | Issuer ID |

默认使用 `CODE_SIGN_IDENTITY = "-"` 的 ad-hoc 开发签名，不依赖 Apple 证书或开发团队配置。配置上述材料后再执行 Developer ID 重签与公证。直接分发的 Release 已关闭 App Sandbox，否则应用不能替换自身；后续如果改做 Mac App Store 渠道，应关闭此自更新器并恢复相应沙盒配置。

## 5. 发版链路

提交本次客户端代码和配置后，推送正式版本标签，例如：

```bash
git tag v0.2.0
git push origin v0.2.0
```

普通 main 推送和手动构建同样自动上传 Release，使用 `build-版本号-构建号` 标签，并标记为预发布；PR 只产生 Actions 产物，不创建 Release。自动生成的标签以 `build-` 开头，不会再次触发 `v*` 构建。

所有客户端使用同一个版本、构建号、公钥和 API 地址。CI 依次：

1. 分析与测试，检查正式发布的公钥配置。
2. 创建一个 Release 草稿，再构建 Windows、macOS、Linux 和 Android；核对版本，使用固定 Android 签名及 macOS 开发签名；可选执行 Apple 公证。
3. 每个平台成功后立即上传对应包到此草稿，仓库所有者可先下载已完成的包。
4. 全部平台成功后计算 SHA-256，生成并签名 `thmr-update.json`，补充上传元数据，再自动发布 Release。
5. 你下载原包上传到镜像，修改插件顶部四个 URL，把同一 Release 的签名清单放到 `data/updates/thmr-release.json` 并重载插件。
6. 客户端后续检查发现新版，使用镜像地址下载并校验，用户确认安装后自动替换。

带 `-rc.1` 的预发布标签仅构建和上传预发布包，不覆盖正式更新 API。Mac 原生包版本采用数字核心版本，客户端通过同一 `THMR_CLIENT_VERSION` 保留完整预发布身份。

当前默认通过文件上传发布清单。**不要手工编辑 payload 或 signature**；版本、哈希或说明发生变化时需要 CI 重新签名。镜像地址在插件顶部独立修改，无需改签名清单。

## 6. 本地构建与验收

PowerShell 示例（公钥可公开；不要把私钥传给 Flutter）：

```powershell
flutter build windows --release --build-name=0.2.0 --build-number=2 `
  --dart-define=THMR_CLIENT_VERSION=0.2.0 `
  --dart-define=THMR_UPDATE_API_URL=https://api.zyghit.cn/updater/thmr `
  --dart-define=THMR_UPDATE_PUBLIC_KEY=<Base64公钥>
```

本地 Android 正式签名通过 `THMR_ANDROID_KEYSTORE_PATH`、`THMR_ANDROID_KEYSTORE_PASSWORD`、`THMR_ANDROID_KEY_ALIAS`、`THMR_ANDROID_KEY_PASSWORD` 环境变量传给 Gradle。未设置时普通开发构建仍使用本机 debug keystore。

自动测试：

```bash
flutter test
python -m unittest discover -s tool -p 'test_*.py' -v
```

本机持有独立 API 插件源码时，可另外运行插件测试；客户端 CI 不依赖此目录：

```bash
cd server-plugin
npm ci
npm test
```

`test_update_helpers.py` 在隔离临时目录里用假应用测试真正的安装辅助程序，覆盖启动成功提交与启动失败回滚；Windows 使用系统 C# 编译器生成测试 exe，Linux 使用 shell 假应用。它不会替换正在使用的 THMR 安装。

正式上线前还需在真实设备验证：从你实际分发的旧版更新到新版、用户数据保留、Android 相同签名覆盖安装、macOS 公证与不同架构、Linux 运行库以及不可写目录的错误反馈。

## 7. 协议与故障定位

API 返回 `{schema:1, algorithm:"ed25519", payload:"<Base64>", signature:"<Base64>"}`，配置镜像后额外提供 `download_urls` 平台到地址的映射。签名覆盖 **payload 解码后的原始 UTF-8 字节**；不对 JSON 重新排序或再编码后验签。`download_urls` 只决定从哪里下载同一个签名保护的安装包，不覆盖版本、大小、哈希或格式。

payload 包含 `program:"THMR"`、`version`、整数 `build_number`、`notes`、`pub_date`、`release_page` 和 `platforms`。平台键为 `windows-x86_64`、`darwin-x86_64`、`darwin-aarch64`、`linux-x86_64`、`android-universal`；每项包含 HTTPS `url`、小写 SHA-256 `sha256`、字节数 `size` 与 `format`（zip / tar.gz / apk）。签名格式专属于 THMR，**不复用原 CPL/Tauri 的签名格式**。

### 为什么 data 中看不到版本号

首次 API 部署包中的 `data/updates/thmr-config.json` 是公钥和发布凭据配置，不是版本清单。只有把 Release 的 `thmr-update.json` 原样部署为 `data/updates/thmr-release.json`，接口才会提供版本信息；缺少清单时返回 204。

清单外层是验签信封，版本藏在 Base64 `payload` 中。CI 会在生成后重新验签并检查它与本次构建的版本、构建号一致。可在本地使用公开的公钥检查：

```powershell
node tool/update_release.cjs inspect --file thmr-release.json --public-key <Base64公钥>
```

命令验签后显示 `version`、`build_number` 和各平台包信息；不要手工编辑 `payload` 或在配置文件里添加版本。客户端按语义版本比较，同一版本下再比较构建号，较高构建号也会提示更新。

若指安装包里的 `data` 目录：Windows 从 EXE 的 ProductVersion 读取版本，macOS 从 `Contents/Info.plist` 读取，Android 从包信息读取；Linux 则读取 `data/flutter_assets/version.json`。各平台不要求在 `data` 根目录重复放版本文件。

| 现象 | 检查 |
| --- | --- |
| 尚未配置验签公钥 | 重新构建客户端时传入正确公钥；不能只配置服务器 |
| 签名校验失败 | 核对 CI 私钥、公钥、服务器公钥是否为同一对；不要修改已签名清单 |
| API 503 | 查看服务日志与清单路径、文件权限、公钥；不暴露私钥或发布 token |
| 发布 401 | 服务器与 CI 的发布 token 是否一致，代理是否保留 Authorization |
| 发布 409 | 并发发布或新版本/构建号未递增；若服务在持锁时崩溃，停服务确认没有发布任务后清理该清单旁的 `.lock` 再重启 |
| 发布工具报告下载不可用 | 先完成 CDN 上传，核对路径中的 `v` 标签、HEAD 支持与文件大小 |
| APK 拒绝安装 | 固定签名是否相同、版本码是否更高、是否允许该来源安装；系统确认不能省略 |
| 桌面准备失败 | 完整安装目录是否独立且可写、磁盘空间、系统 PowerShell/tar/codesign 是否可用 |
| 启动失败后回滚 | 新版是否加载音频依赖、是否能渲染界面；检查更新缓存下 `last-transaction` 指向的 `result.json` |

更新验证不通过时继续运行旧版，修复发布配置后重试。

平台资料：[Android 安装确认](https://developer.android.com/reference/android/content/pm/PackageInstaller.SessionParams#setRequireUserAction(int))、[Flutter macOS 发布](https://docs.flutter.dev/deployment/macos)。
