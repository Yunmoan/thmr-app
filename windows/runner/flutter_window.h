#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  void RequestActivation();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
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
