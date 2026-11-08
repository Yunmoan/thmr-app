#include "single_instance.h"

SingleInstance::~SingleInstance() {
  if (owns_mutex_) ReleaseMutex(mutex_);
  if (mutex_) CloseHandle(mutex_);
  if (activation_event_) CloseHandle(activation_event_);
}

SingleInstance::Result SingleInstance::Acquire() {
  // Create the event first so even a second launch before window creation can
  // queue activation. Local scopes the objects to the interactive session.
  activation_event_ = CreateEventW(
      nullptr, FALSE, FALSE, L"Local\\cn.yunmoan.thmr.activate");
  mutex_ = CreateMutexW(nullptr, FALSE, L"Local\\cn.yunmoan.thmr.instance");
  if (!activation_event_ || !mutex_) return Result::error;

  const DWORD result = WaitForSingleObject(mutex_, 0);
  if (result == WAIT_OBJECT_0 || result == WAIT_ABANDONED) {
    owns_mutex_ = true;
    return Result::primary;
  }
  if (result != WAIT_TIMEOUT) return Result::error;

  if (const HWND window = FindWindowW(kThmrWindowClass, nullptr)) {
    DWORD process_id = 0;
    GetWindowThreadProcessId(window, &process_id);
    // Transfer the user's launch foreground permission to the existing app.
    if (process_id) AllowSetForegroundWindow(process_id);
  }
  return SetEvent(activation_event_) ? Result::secondary : Result::error;
}
