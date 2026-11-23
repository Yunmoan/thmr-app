#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// 支持高 DPI 的 Win32 窗口基类，子类可提供自己的绘制和输入处理。
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // 使用 title、origin 和 size 创建窗口。取最靠近 origin 的显示器 DPI，
  // 将位置和尺寸转换为物理像素。窗口初始隐藏，需调用 Show 显示。创建及 OnCreate 成功时返回 true。
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // 显示窗口。返回 ShowWindow 的结果，表示调用前窗口是否可见。
  bool Show();

  // 释放窗口关联的系统资源。
  void Destroy();

  // 将 content 设为子窗口，使其填满客户区并接收焦点。
  void SetChildContent(HWND content);

  // 返回底层 HWND，供调用方设置图标等属性。窗口销毁后返回 nullptr。
  HWND GetHandle();

  // 启用后，销毁窗口时向应用消息循环投递退出消息。
  void SetQuitOnClose(bool quit_on_close);

  // 返回当前客户区的 RECT。
  RECT GetClientArea();

 protected:
  // 处理尺寸、焦点和 DPI 等窗口消息。子类可覆盖此方法继续分派，未处理的消息交给 Win32 默认过程。
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Create 创建 HWND 后调用，供子类初始化窗口资源。初始化失败时返回 false。
  virtual bool OnCreate();

  // Destroy 开始时调用，供子类释放资源。
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // Win32 窗口过程。收到 WM_NCCREATE 时保存实例指针并启用可用的非客户区 DPI 缩放；
  // 其他消息转交实例的 MessageHandler 或默认窗口过程。
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // 从 window 的 GWLP_USERDATA 读取实例指针。
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // 根据系统应用主题偏好更新窗口边框。
  static void UpdateTheme(HWND const window);

  void ResizeChildToClient();

  bool quit_on_close_ = false;
  bool resizing_child_ = false;
  bool child_resize_pending_ = false;

  // 顶层窗口的 HWND。
  HWND window_handle_ = nullptr;

  // 内嵌内容的 HWND。
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
