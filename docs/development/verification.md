# 验证与手动检查

[返回开发指南](README.md)

从仓库根目录运行。平台集成测试所需的系统组件见对应平台开发页。

```sh
flutter analyze --no-pub
flutter test --no-pub
python -m unittest discover -s tool -p 'test_*.py' -v
node --test tool/test_update_release.cjs
```

| 改动 | 对应检查 |
| --- | --- |
| 后端接口 | [Radio 请求测试](../../test/radio_api_test.dart)、[账号请求测试](../../test/thmr_api_test.dart)、[线路测试](../../test/radio_source_test.dart) 使用本地服务和模拟数据。 |
| 焦点、读屏、手柄 | [无障碍测试](../../test/accessibility_test.dart)、[输入分发测试](../../test/app_input_test.dart)、[手柄导航测试](../../test/gamepad_navigation_test.dart)。发版前在 NVDA 或讲述人、VoiceOver、TalkBack 与实物手柄上检查收听、搜索、收藏、登录和反馈。 |
| 大屏幕、迷你窗口 | [大屏幕测试](../../test/large_screen_test.dart)、[大屏设置测试](../../test/large_screen_settings_test.dart)、[迷你窗口切换测试](../../test/mini_mode_transition_test.dart) 覆盖布局、焦点与页面状态保留。 |
| 频谱、播放资源 | [频谱验证](spectrum.md#验证) 和 [退出测试](../../test/application_exit_test.dart)。变更 macOS 渲染或退出流程时在真实设备上检查切页、滚动、缩放、托盘恢复与播放中退出。macOS 的渲染配置见 [`Info.plist`](../../macos/Runner/Info.plist)。 |
| 安装辅助程序 | [更新辅助程序测试](../../tool/test_update_helpers.py) 在临时目录验证成功替换和失败回滚。Windows 用系统 C# 编译器创建假应用，Linux 用 shell 假应用。 |
| 发布安装包 | [Linux 测试](linux.md#自动化验证) · [iOS 真机验证](ios.md#真机验证) · [发布验收](../release/client-builds.md#产物与验收)。 |

## 手动检查

| 用途 | 命令 |
| --- | --- |
| 检查真实服务连接并生成本地报告 | `dart tool/manual/diagnostics_smoke.dart`，写入 `build/diagnostics-smoke.txt`。 |
| 预览键盘与手柄帮助的截图 | `flutter test tool/manual/input_help_preview_test.dart`，图片写入 `build/`。 |
| 验证 Windows 大屏幕的原生窗口与绘制切换 | `flutter run -d windows -t tool/manual/large_screen_smoke.dart --no-pub`。 |
| 验证 Windows 迷你播放器的原生窗口过渡 | `flutter run -d windows -t tool/manual/window_transition_smoke.dart --no-pub`。 |

Windows 两项检查使用真实窗口。先关闭正在运行的 THMR。脚本使用模拟播放状态，省略网络、音频和应用偏好写入。
