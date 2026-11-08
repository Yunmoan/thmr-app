# Linux 客户端

主要兼容目标为 Ubuntu 24.04 x64。保留 GTK 原生标题栏，不提供迷你播放器。
其他发行版需要提供兼容运行库；在更高版本 glibc 系统上自行构建的包不保证能在 Ubuntu 24.04 运行。

## 安装与启动

先安装运行库（Ubuntu 24.04）：

```sh
sudo apt install libgtk-3-0t64 libmpv2 libsecret-1-0 libjsoncpp25 \
  libayatana-appindicator3-1
```

Arch Linux 对应运行库为 `gtk3 mpv libsecret jsoncpp libayatana-appindicator`。
不需要安装 `ffmpeg` 命令；频谱的 MP3 解码器已经随应用提供。

```sh
tar -xzf thmr-app-linux-x64.tar.gz
cd bundle
./thmr --check-runtime
./thmr
```

保留整个 `bundle/`，不要只复制 `thmr_app`。`thmr` 启动器会检查动态库和 libmpv；
运行库缺失时输出安装提示，有 Zenity/KDialog 时也会显示图形提示。
直接运行 `thmr_app` 会跳过启动器检查。

建议先把 `bundle/` 放到当前用户可写、且长期使用的位置，例如 `~/Applications/THMR/`。
程序目录和其父目录都必须可写，自更新才能创建暂存目录并完成替换。

## 应用菜单

在最终安装目录执行：

```sh
./install-desktop.sh
```

脚本只向当前用户的 XDG 数据目录写入菜单入口和图标，无需 sudo，不启用开机自启。
支持空格、中文及常见特殊字符路径；移动安装目录后需要重新执行。
桌面入口始终指向固定安装路径中的 `thmr`，整体目录自更新后仍然有效。

```sh
./uninstall-desktop.sh
```

卸载脚本只移除它管理的菜单入口和图标，保留程序文件与用户设置。

## 功能与异常行为

| 功能 | Linux 行为 |
| --- | --- |
| 收听、音量、码率、自动重连、主题 | 支持 |
| 单实例 | 同一桌面登录会话中重复启动会唤起已有窗口 |
| 托盘 | 使用 StatusNotifier/AppIndicator；菜单提供显示窗口与退出 |
| 关闭窗口 | 默认每次询问，可记住退出或最小化选择 |
| 托盘不可用或消失 | 禁止隐藏到不可用的托盘，回退任务栏最小化并继续播放 |
| 系统媒体控制 | MPRIS：曲名、作者、封面、状态、播放、暂停、停止、音量和唤起窗口 |
| 直播限制 | 不支持 seek、上一曲或下一曲，不把切歌投票映射为系统下一曲 |
| 频谱 | 内置 minimp3 解码本应用 MP3 流，后台 isolate 做 FFT，不采集系统声音或麦克风 |
| 频谱故障 | 收听继续，频谱恢复静态并提供重试；切码率和重连会替换解码任务 |
| 自动更新 | 签名、哈希校验、完整目录替换、重启确认及失败回滚 |
| 客户端登录 | 保留网页版入口；本轮不适配，登录后才能使用的个人收藏等功能仍受限 |
| 迷你播放器 | 不适配 |

GNOME 的托盘是否可用取决于桌面配置，例如是否启用 AppIndicator 扩展；
应用会检测实际的托盘宿主，而不是仅凭图标注册成功就隐藏窗口。
Wayland 下唤起、焦点和最小化仍由合成器决定；系统拒绝最小化时保留可见窗口。
MPRIS 或频谱初始化失败不会阻止收听。

## 构建与自动化验证

Ubuntu 24.04 构建依赖：

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev g++ libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev libmpv-dev mpv \
  python3-gi dbus-x11 xvfb desktop-file-utils
flutter pub get
flutter analyze --no-pub
flutter test --no-pub
flutter build linux --release --no-pub
python3 tool/verify_linux_bundle.py build/linux/x64/release/bundle --max-glibc 2.39
python3 tool/test_linux_mpris.py
python3 -m unittest discover -s tool -p 'test_linux_distribution.py'
```

`tool/test_linux_spectrum.dart` 可以用 SDK 内的 Dart VM 运行；将 PATH 指向一个不存在的
目录，明确验证无需 FFmpeg 命令：

```sh
flutter_sdk=$(dirname "$(dirname "$(readlink -f "$(command -v flutter)")")")
env PATH=/nonexistent "$flutter_sdk/bin/cache/dart-sdk/bin/dart" \
  --packages=.dart_tool/package_config.json tool/test_linux_spectrum.dart \
  "$PWD/build/linux/x64/release/bundle/lib/libthmr_mp3.so"
python3 tool/test_linux_app.py build/linux/x64/release/bundle
```

CI 固定在 Ubuntu 24.04 构建，并检查包内 ELF 的 glibc 需求上限。
自动化包括合成音解码/频率验证、单上游连接、D-Bus 媒体契约、真实 GTK 应用启动和重复启动，
以及桌面入口安装/卸载、特殊字符路径和更新成功/回滚测试。

发布前仍需在真实桌面完成下表；自动化或 Xvfb 不代表这些检查已经通过：

| 环境 | 人工检查 |
| --- | --- |
| Ubuntu 24.04 GNOME X11 / Wayland | 播放、托盘显示/恢复、媒体键、系统封面、关闭询问与记忆、码率切换和断网重连 |
| 无托盘或桌面 Shell 重启 | 关闭回退最小化，宿主消失后窗口可找回，恢复后可继续用托盘 |
| KDE | 托盘菜单、媒体控制、最小化与恢复冒烟验证 |
| 实际旧版更新至新版 | 用户设置保留、安装路径不变、菜单入口有效、失败回滚 |

minimp3 固定来源与哈希在 `native/vendor/minimp3/source.json`，许可证也随包安装在
`data/licenses/minimp3/LICENSE`。
