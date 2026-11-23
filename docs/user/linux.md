# Linux 使用说明

[返回使用指南](https://github.com/Yunmoan/thmr-app/blob/main/docs/user/README.md) · [Linux 构建与验证](https://github.com/Yunmoan/thmr-app/blob/main/docs/development/linux.md)

## 安装与启动

Ubuntu 24.04 x64 是主要兼容目标。其他发行版需要提供兼容的运行库。

```sh
sudo apt install libgtk-3-0t64 libmpv2 libsecret-1-0 libjsoncpp25 \
  libayatana-appindicator3-1

tar -xzf thmr-app-linux-x64.tar.gz
cd bundle
./thmr --check-runtime
./thmr
```

Arch Linux 的对应依赖为 `gtk3 mpv libsecret jsoncpp libayatana-appindicator`。MP3 频谱解码器随应用提供。

保留整个 `bundle/`，使用 `thmr` 启动。启动器检查动态库和 libmpv，缺失时输出安装提示。有 Zenity 或 KDialog 时也会弹出图形提示。自动更新需要程序目录及其父目录均可写，可以把解压目录放在 `~/Applications/THMR/`。

## 应用菜单

在最终安装目录执行 `./install-desktop.sh`。脚本把菜单和图标写入当前用户的 XDG 数据目录，无需 sudo。移动安装目录后重新执行。整目录应用内更新保留原启动路径。

执行 `./uninstall-desktop.sh` 可移除脚本管理的菜单入口和图标，程序文件和个人设置仍可使用。

## 桌面集成

- 使用 GTK 原生标题栏。在「我的 → 关闭按钮」可选择退出、最小化或每次询问。检测不到可用的 AppIndicator 宿主时，应用回退到任务栏最小化并继续播放。Wayland 的窗口唤起、焦点及最小化由合成器决定。
- 通过 MPRIS 提供播放、暂停、停止、音量、曲目信息和唤起窗口。直播流无法跳转或点播上一首、下一首。
- 频谱从应用自己的 MP3 流取样。频谱初始化失败时仍可收听，频谱区提供重试。
- 登录入口打开网页版。客户端个人收藏等需要会话的功能在 Linux 上受限。迷你播放器只在 Windows 上提供。
