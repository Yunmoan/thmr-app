import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static var instanceLock: Int32 = -1
  private static var activationObserver: NSObjectProtocol?

  // 在创建 Flutter 引擎前处理单实例，包括直接运行可执行文件等绕过 Launch Services 的情况。
  static func acquireSingleInstance() {
    guard instanceLock == -1 else { return }
    guard let identifier = Bundle.main.bundleIdentifier else { exit(EXIT_FAILURE) }
    let notification = Notification.Name(identifier + ".activate")
    let center = DistributedNotificationCenter.default()
    // 先订阅激活通知再尝试加锁，避免并发启动时漏掉唤醒。
    activationObserver = center.addObserver(
      forName: notification, object: nil, queue: .main
    ) { _ in
      showMainWindow()
    }
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent(identifier + ".instance.lock")
    instanceLock = open(path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard instanceLock >= 0 else { exit(EXIT_FAILURE) }
    if flock(instanceLock, LOCK_EX | LOCK_NB) != 0 {
      guard errno == EWOULDBLOCK else { exit(EXIT_FAILURE) }
      center.postNotificationName(notification, object: nil, userInfo: nil,
                                  deliverImmediately: true)
      NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
        .activate(options: [.activateIgnoringOtherApps])
      exit(EXIT_SUCCESS)
    }
    // 保持文件描述符打开以持有 flock。进程退出或崩溃时由系统释放。
  }

  private static func showMainWindow() {
    guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else { return }
    window.deminiaturize(nil)
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication,
                                              hasVisibleWindows flag: Bool) -> Bool {
    Self.showMainWindow()
    return false
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // 隐藏窗口后，通过菜单栏图标恢复，电台继续播放。显式退出走 Flutter 的异步退出处理。
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
