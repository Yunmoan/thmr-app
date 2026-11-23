#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

inline constexpr wchar_t kThmrWindowClass[] = L"THMR_RUNNER_WIN32_WINDOW";

// 最后一个句柄关闭后，系统会回收内核对象，进程崩溃也会释放锁。
// 激活事件可保留尚未建好窗口时收到的请求。
class SingleInstance {
 public:
  enum class Result { primary, secondary, error };

  SingleInstance() = default;
  ~SingleInstance();
  SingleInstance(const SingleInstance&) = delete;
  SingleInstance& operator=(const SingleInstance&) = delete;

  Result Acquire();
  HANDLE activation_event() const { return activation_event_; }

 private:
  HANDLE mutex_ = nullptr;
  HANDLE activation_event_ = nullptr;
  bool owns_mutex_ = false;
};

#endif  // RUNNER_SINGLE_INSTANCE_H_
