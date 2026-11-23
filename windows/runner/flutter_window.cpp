#include "flutter_window.h"

#include <dwmapi.h>
#include <shobjidl.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kPresentationFrameTimer = 0x54484D52;
constexpr UINT kPresentationFrameTimeoutMs = 5000;

flutter::EncodableMap EncodePixelRect(const RECT& rect) {
  return {
      {flutter::EncodableValue("left"),
       flutter::EncodableValue(static_cast<int32_t>(rect.left))},
      {flutter::EncodableValue("top"),
       flutter::EncodableValue(static_cast<int32_t>(rect.top))},
      {flutter::EncodableValue("right"),
       flutter::EncodableValue(static_cast<int32_t>(rect.right))},
      {flutter::EncodableValue("bottom"),
       flutter::EncodableValue(static_cast<int32_t>(rect.bottom))},
  };
}

BOOL CALLBACK CollectDisplay(HMONITOR monitor, HDC, LPRECT, LPARAM data) {
  MONITORINFO info{};
  info.cbSize = sizeof(info);
  if (!GetMonitorInfo(monitor, &info)) return FALSE;
  auto* displays = reinterpret_cast<flutter::EncodableList*>(data);
  displays->emplace_back(flutter::EncodableMap{
      {flutter::EncodableValue("bounds"),
       flutter::EncodableValue(EncodePixelRect(info.rcMonitor))},
      {flutter::EncodableValue("workArea"),
       flutter::EncodableValue(EncodePixelRect(info.rcWork))},
  });
  return TRUE;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::RequestActivation() {
  activation_pending_ = true;
  // 保留首帧准备和正在进行的迷你模式切换。
  if (!startup_ready_ || presentation_concealed_ || !GetHandle()) return;
  activation_pending_ = false;
  ShowWindow(GetHandle(), IsIconic(GetHandle()) ? SW_RESTORE : SW_SHOW);
  SetForegroundWindow(GetHandle());
  presentation_channel_->InvokeMethod("activate", nullptr);
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // 控制器初始尺寸需与窗口一致，避免启动时重复创建 Flutter 绘制表面。
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // 控制器必须已创建引擎和视图，才能继续初始化窗口。
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterWindowPresentation();

  // Dart 恢复设置、准备资源并等待首帧光栅化，再通过 window_manager 显示窗口。

  return true;
}

void FlutterWindow::OnDestroy() {
  if (GetHandle()) KillTimer(GetHandle(), kPresentationFrameTimer);
  ++frame_serial_;
  frame_callback_pending_ = false;
  if (frame_result_) {
    frame_result_->Error("window_destroyed", "Window destroyed during presentation");
    frame_result_.reset();
  }
  presentation_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_TIMER && wparam == kPresentationFrameTimer) {
    KillTimer(hwnd, kPresentationFrameTimer);
    ++frame_serial_;
    if (frame_result_) {
      frame_result_->Error("frame_timeout", "Flutter did not rasterize a frame");
      frame_result_.reset();
    }
    return 0;
  }
  // 先让 Flutter 及插件处理窗口消息。
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

void FlutterWindow::RegisterWindowPresentation() {
  presentation_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "thmr/window_presentation",
          &flutter::StandardMethodCodec::GetInstance());
  presentation_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        const auto& method = call.method_name();
        if (method == "fullscreenHint") {
          const auto* full_screen = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
          if (!full_screen) {
            result->Error("invalid_argument", "Expected a fullscreen bool");
            return;
          }
          ITaskbarList2* taskbar = nullptr;
          auto hr = CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER,
                                     IID_PPV_ARGS(&taskbar));
          if (SUCCEEDED(hr)) {
            hr = taskbar->HrInit();
            if (SUCCEEDED(hr)) hr = taskbar->MarkFullscreenWindow(GetHandle(), *full_screen);
            taskbar->Release();
          }
          if (FAILED(hr)) {
            result->Error("fullscreen_hint_failed", "Cannot notify Windows shell");
          } else {
            result->Success();
          }
        } else if (method == "miniWindowGeometry" ||
                   method == "windowBoundsInPixels") {
          RECT bounds{};
          if (!GetWindowRect(GetHandle(), &bounds)) {
            result->Error("window_bounds_failed", "Cannot read window bounds");
            return;
          }
          if (method == "windowBoundsInPixels") {
            result->Success(flutter::EncodableValue(EncodePixelRect(bounds)));
            return;
          }
          flutter::EncodableList displays;
          const auto dpi = GetDpiForWindow(GetHandle());
          if (dpi == 0 ||
              !EnumDisplayMonitors(nullptr, nullptr, CollectDisplay,
                                   reinterpret_cast<LPARAM>(&displays))) {
            result->Error("display_metrics_failed", "Cannot read display layout");
            return;
          }
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("bounds"),
               flutter::EncodableValue(EncodePixelRect(bounds))},
              {flutter::EncodableValue("dpi"),
               flutter::EncodableValue(static_cast<int32_t>(dpi))},
              {flutter::EncodableValue("displays"),
               flutter::EncodableValue(std::move(displays))},
          }));
        } else if (method == "setWindowPositionInPixels") {
          const auto* position = call.arguments()
              ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
          if (!position) {
            result->Error("invalid_argument", "Expected a pixel position");
            return;
          }
          const auto x = position->find(flutter::EncodableValue("x"));
          const auto y = position->find(flutter::EncodableValue("y"));
          const auto* left = x == position->end() ? nullptr
                                                : std::get_if<int32_t>(&x->second);
          const auto* top = y == position->end() ? nullptr
                                               : std::get_if<int32_t>(&y->second);
          if (!left || !top) {
            result->Error("invalid_argument", "Expected integer x and y");
          } else if (!SetWindowPos(GetHandle(), nullptr, *left, *top, 0, 0,
                                   SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE)) {
            result->Error("window_move_failed", "Cannot move the window");
          } else {
            result->Success();
          }
        } else if (method == "workAreaInsets") {
          auto monitor = MONITORINFO{};
          monitor.cbSize = sizeof(monitor);
          RECT client{};
          if (!GetClientRect(GetHandle(), &client) ||
              !GetMonitorInfo(MonitorFromWindow(GetHandle(), MONITOR_DEFAULTTONEAREST), &monitor)) {
            result->Error("display_metrics_failed", "Cannot read window work area");
            return;
          }
          POINT origin{client.left, client.top};
          ClientToScreen(GetHandle(), &origin);
          const double scale = static_cast<double>(GetDpiForWindow(GetHandle())) / 96.0;
          const auto inset = [scale](LONG value) { return value > 0 ? value / scale : 0.0; };
          result->Success(flutter::EncodableValue(flutter::EncodableMap{
              {flutter::EncodableValue("left"), flutter::EncodableValue(inset(monitor.rcWork.left - origin.x))},
              {flutter::EncodableValue("top"), flutter::EncodableValue(inset(monitor.rcWork.top - origin.y))},
              {flutter::EncodableValue("right"), flutter::EncodableValue(inset(origin.x + client.right - monitor.rcWork.right))},
              {flutter::EncodableValue("bottom"), flutter::EncodableValue(inset(origin.y + client.bottom - monitor.rcWork.bottom))},
          }));
        } else if (method == "startupReady") {
          startup_ready_ = true;
          if (activation_pending_) RequestActivation();
          result->Success();
        } else if (method == "conceal") {
          if (presentation_concealed_) {
            result->Error("presentation_busy", "Window is already concealed");
            return;
          }
          DwmGetWindowAttribute(GetHandle(), DWMWA_TRANSITIONS_FORCEDISABLED,
                                &saved_transitions_disabled_, sizeof(BOOL));
          const BOOL enabled = TRUE;
          HRESULT hr = DwmSetWindowAttribute(
              GetHandle(), DWMWA_TRANSITIONS_FORCEDISABLED, &enabled, sizeof(BOOL));
          if (SUCCEEDED(hr)) {
            hr = DwmSetWindowAttribute(GetHandle(), DWMWA_CLOAK, &enabled,
                                       sizeof(BOOL));
          }
          if (SUCCEEDED(hr)) {
            presentation_concealed_ = true;
            // MethodChannel 回复前先同步 DWM 合成，确保原来的客户区内容与窗口装饰完全隐藏，
            // 再允许修改界面。
            hr = DwmFlush();
          }
          if (FAILED(hr)) {
            RevealWindow();
            result->Error("conceal_failed", "DWM could not conceal the window");
          } else {
            result->Success();
          }
        } else if (method == "reveal") {
          const HRESULT hr = RevealWindow();
          if (FAILED(hr)) {
            result->Error("reveal_failed", "DWM could not reveal the window");
          } else {
            result->Success();
          }
        } else if (method == "setMaximized") {
          const auto* maximized = call.arguments()
              ? std::get_if<bool>(call.arguments()) : nullptr;
          if (!presentation_concealed_ || !maximized) {
            result->Error("invalid_presentation", "Expected a concealed window and bool");
            return;
          }
          // window_manager 的 SC_RESTORE / SC_MAXIMIZE 只投递命令。这里同步调用 ShowWindow，
          // 再将窗口切换结果返回给 Dart。
          ShowWindow(GetHandle(), *maximized ? SW_MAXIMIZE : SW_RESTORE);
          if ((IsZoomed(GetHandle()) != FALSE) != *maximized) {
            result->Error("window_state_failed", "Window state did not change");
          } else {
            result->Success();
          }
        } else if (method == "waitForFrame" || method == "flushFrame") {
          if ((method == "waitForFrame" && !presentation_concealed_) ||
              frame_callback_pending_) {
            result->Error("invalid_presentation", "Invalid presentation or fence busy");
            return;
          }
          if (!SetTimer(GetHandle(), kPresentationFrameTimer,
                        kPresentationFrameTimeoutMs, nullptr)) {
            result->Error("timer_failed", "Cannot guard the raster fence");
            return;
          }
          frame_result_ = std::move(result);
          // 引擎只保留一个回调槽。等待超时后继续等在途回调退出，才能登记下一次。
          frame_callback_pending_ = true;
          const auto serial = ++frame_serial_;
          // Dart 已提交目标尺寸的图层树。引擎随后在光栅线程登记回调，
          // 并通过 ForceRedraw 为静止或空白的界面请求重绘。
          flutter_controller_->engine()->SetNextFrameCallback([this, serial] {
            frame_callback_pending_ = false;
            if (serial != frame_serial_ || !frame_result_) return;
            KillTimer(GetHandle(), kPresentationFrameTimer);
            auto result = std::move(frame_result_);
            result->Success();
          });
          flutter_controller_->ForceRedraw();
        } else {
          result->NotImplemented();
        }
      });
}

HRESULT FlutterWindow::RevealWindow() {
  HRESULT hr = S_OK;
  if (presentation_concealed_) {
    // 显示整个 HWND 前先等待目标表面提交到 DWM。
    DwmFlush();
    const BOOL disabled = FALSE;
    hr = DwmSetWindowAttribute(GetHandle(), DWMWA_CLOAK, &disabled, sizeof(BOOL));
    if (SUCCEEDED(hr)) {
      presentation_concealed_ = false;
      DwmFlush();
    }
  }
  DwmSetWindowAttribute(GetHandle(), DWMWA_TRANSITIONS_FORCEDISABLED,
                        &saved_transitions_disabled_, sizeof(BOOL));
  if (activation_pending_ && SUCCEEDED(hr)) RequestActivation();
  return hr;
}
