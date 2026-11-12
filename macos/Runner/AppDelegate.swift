import Cocoa
import Darwin
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private static var instanceLock: Int32 = -1
  private static var activationObserver: NSObjectProtocol?

  // Called before creating the Flutter engine, including launches that bypass
  // Launch Services (for example running the executable directly).
  static func acquireSingleInstance() {
    guard instanceLock == -1 else { return }
    guard let identifier = Bundle.main.bundleIdentifier else { exit(EXIT_FAILURE) }
    let notification = Notification.Name(identifier + ".activate")
    let center = DistributedNotificationCenter.default()
    // Subscribe before locking so simultaneous launches cannot lose a wakeup.
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
    // Keep the descriptor open. The OS releases flock on exit, including crashes.
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
    // The menu-bar item owns a recovery path while the radio keeps playing.
    // Explicit Quit still goes through Flutter's asynchronous exit handler.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
