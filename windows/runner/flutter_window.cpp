#include "flutter_window.h"

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include <optional>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT_PTR kPresentationFrameTimer = 0x54484D52;
constexpr UINT kPresentationFrameTimeoutMs = 5000;
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

void FlutterWindow::RequestActivation() {
  activation_pending_ = true;
  // Preserve first-frame preparation and any in-progress mini-mode transition.
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

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterWindowPresentation();

  // Dart owns startup visibility: it restores settings, prepares visual assets,
  // and waits for the first rasterized frame before window_manager shows us.

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
  // Give Flutter, including plugins, an opportunity to handle window messages.
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
        if (method == "startupReady") {
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
            // A method-channel reply is not a compositor fence. Wait until the
            // old content AND decorations are off screen before any mutation.
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
          // Unlike window_manager's posted SC_RESTORE/SC_MAXIMIZE, ShowWindow
          // completes the state/metrics change before replying to Dart.
          ShowWindow(GetHandle(), *maximized ? SW_MAXIMIZE : SW_RESTORE);
          if ((IsZoomed(GetHandle()) != FALSE) != *maximized) {
            result->Error("window_state_failed", "Window state did not change");
          } else {
            result->Success();
          }
        } else if (method == "waitForFrame") {
          if (!presentation_concealed_ || frame_callback_pending_) {
            result->Error("invalid_presentation", "No concealed presentation or fence busy");
            return;
          }
          if (!SetTimer(GetHandle(), kPresentationFrameTimer,
                        kPresentationFrameTimeoutMs, nullptr)) {
            result->Error("timer_failed", "Cannot guard the raster fence");
            return;
          }
          frame_result_ = std::move(result);
          // After a timeout, let the outstanding engine callback drain before
          // registering another one; the engine owns only one callback slot.
          frame_callback_pending_ = true;
          const auto serial = ++frame_serial_;
          // Dart calls this after submitting its target-size layer tree. The
          // engine queues callback registration on the raster task runner after
          // that submission. ForceRedraw also handles a static/empty target UI.
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
    // Flush the rendered target surface before making the complete HWND visible.
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
