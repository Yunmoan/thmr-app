#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// 承载 Flutter 视图的 Win32 窗口。
class FlutterWindow : public Win32Window {
 public:
  // 创建运行 project 的 FlutterWindow。
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void RequestActivation();

 protected:
  // Win32Window 的子类实现。
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // 要启动的 Dart 项目。
  flutter::DartProject project_;

  // 此窗口承载的 Flutter 视图控制器。
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  void RegisterWindowPresentation();
  HRESULT RevealWindow();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      presentation_channel_;
  std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> frame_result_;
  uint64_t frame_serial_ = 0;
  bool frame_callback_pending_ = false;
  bool presentation_concealed_ = false;
  bool startup_ready_ = false;
  bool activation_pending_ = false;
  BOOL saved_transitions_disabled_ = FALSE;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
