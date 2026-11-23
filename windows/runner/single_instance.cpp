#include "single_instance.h"

SingleInstance::~SingleInstance() {
  if (owns_mutex_) ReleaseMutex(mutex_);
  if (mutex_) CloseHandle(mutex_);
  if (activation_event_) CloseHandle(activation_event_);
}

SingleInstance::Result SingleInstance::Acquire() {
  // 先创建激活事件，后续实例即使在窗口创建前启动也能发出激活请求。
  // Local 将对象限制在当前交互会话。
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
    // 将本次用户启动授予的前台窗口权限移交给现有实例。
    if (process_id) AllowSetForegroundWindow(process_id);
  }
  return SetEvent(activation_event_) ? Result::secondary : Result::error;
}
