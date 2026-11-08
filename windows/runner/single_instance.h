#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

inline constexpr wchar_t kThmrWindowClass[] = L"THMR_RUNNER_WIN32_WINDOW";

// Kernel objects live only while a process holds them; crashes cannot leave a
// stale lock. The activation event also survives requests made during startup.
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
