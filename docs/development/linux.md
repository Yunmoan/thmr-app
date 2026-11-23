# Linux 构建与验证

[返回开发指南](README.md) · [Linux 使用说明](../user/linux.md)

## 构建

以 Ubuntu 24.04 x64 为构建基准。工作流和打包依赖见 [`build.yml`](../../.github/workflows/build.yml)。较新的 glibc 环境产出的包可能无法在这个基准环境运行。

```sh
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev \
  liblzma-dev g++ libsecret-1-dev libjsoncpp-dev \
  libayatana-appindicator3-dev libmpv-dev mpv \
  python3-gi dbus-x11 xvfb desktop-file-utils

flutter pub get --enforce-lockfile
flutter build linux --release --no-pub
```

## 自动化验证

```sh
bundle="$PWD/build/linux/x64/release/bundle"
python3 tool/verify_linux_bundle.py "$bundle" --max-glibc 2.39
python3 tool/test_linux_mpris.py
python3 -m unittest discover -s tool -p 'test_linux_distribution.py'
python3 tool/test_linux_app.py "$bundle"
```

这些检查覆盖运行依赖、包内 ELF 的 glibc 要求、MPRIS D-Bus 媒体接口、启动和重复启动、托盘宿主变化、菜单安装及更新后的路径有效性。应用测试先确认 AppIndicator 导出的 D-Bus 对象，再启动模拟 watcher，以避免连接尚未初始化。 [频谱验证](spectrum.md#验证)

## 真机验证

- 在 Ubuntu 24.04 GNOME 的 X11 和 Wayland 分别检查播放、托盘显示与恢复、媒体键、系统封面、关闭行为、码率切换和断网重连。
- 在无托盘和桌面 Shell 重启后检查最小化回退与窗口恢复。在 KDE 上检查托盘菜单、媒体控制和窗口操作。
- 真实更新后核对用户设置、安装路径和菜单入口。模拟新程序启动失败，确认能恢复原安装。
