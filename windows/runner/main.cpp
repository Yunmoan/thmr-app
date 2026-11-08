#pragma execution_character_set("utf-8")
#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  SingleInstance single_instance;
  const auto instance_result = single_instance.Acquire();
  if (instance_result == SingleInstance::Result::secondary) return EXIT_SUCCESS;
  if (instance_result == SingleInstance::Result::error) return EXIT_FAILURE;

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"东方音乐电台 THMR", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  const HANDLE activation_event = single_instance.activation_event();
  bool running = true;
  while (running) {
    const DWORD result = MsgWaitForMultipleObjects(
        1, &activation_event, FALSE, INFINITE, QS_ALLINPUT);
    if (result == WAIT_FAILED) break;
    if (result == WAIT_OBJECT_0) window.RequestActivation();
    ::MSG msg;
    while (::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        running = false;
        break;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
