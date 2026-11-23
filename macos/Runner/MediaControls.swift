import Cocoa
import FlutterMacOS
import MediaPlayer

/// 将 macOS 曲目信息发布到 MPNowPlayingInfoCenter，供控制中心和 Now Playing 使用，
/// 并将 MPRemoteCommandCenter 的媒体键命令转交给 Dart。
///
/// 与 linux/runner/linux_media.cc 类似，Dart 管理媒体状态，通过 thmr/macos_media 发送快照，
/// 原生侧负责向系统发布。
final class MediaControls: NSObject {
  static let shared = MediaControls()

  private var channel: FlutterMethodChannel?
  private var commandsRegistered = false
  private var isPlaying = false
  private var nowPlayingInfo: [String: Any] = [:]
  private var currentArtworkURL = ""
  private var artworkTask: URLSessionDataTask?
  private var fallbackArtwork: NSImage?

  func attach(messenger: FlutterBinaryMessenger) {
    // 使用 Flutter 引擎的 binary messenger。
    let channel = FlutterMethodChannel(
      name: "thmr/macos_media", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "start":
        self.registerCommands()
        result(nil)
      case "stop":
        self.clear()
        result(nil)
      case "update":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(
            code: "invalid_args", message: "Expected media state",
            details: nil))
          return
        }
        self.applyUpdate(args)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  private func registerCommands() {
    guard !commandsRegistered else { return }
    commandsRegistered = true
    let center = MPRemoteCommandCenter.shared()
    center.playCommand.addTarget { [weak self] _ in
      self?.send("play")
      return .success
    }
    center.pauseCommand.addTarget { [weak self] _ in
      self?.send("pause")
      return .success
    }
    center.stopCommand.addTarget { [weak self] _ in
      self?.send("stop")
      return .success
    }
    // F8 或硬件播放暂停键根据最后收到的播放状态选择操作。
    center.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      self.send(self.isPlaying ? "pause" : "play")
      return .success
    }
    // 直播不支持定位或切换曲目。
    center.changePlaybackPositionCommand.isEnabled = false
    center.nextTrackCommand.isEnabled = false
    center.previousTrackCommand.isEnabled = false
    center.skipBackwardCommand.isEnabled = false
    center.skipForwardCommand.isEnabled = false
    center.changePlaybackRateCommand.isEnabled = false
    center.seekBackwardCommand.isEnabled = false
    center.seekForwardCommand.isEnabled = false
  }

  private func applyUpdate(_ args: [String: Any]) {
    let status = args["status"] as? String ?? "Stopped"
    isPlaying = status == "Playing"
    if status == "Stopped" {
      clear()
      return
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] =
      MPNowPlayingInfoMediaType.audio.rawValue
    if let title = args["title"] as? String {
      nowPlayingInfo[MPMediaItemPropertyTitle] = title
    }
    if let artist = args["artist"] as? String {
      nowPlayingInfo[MPMediaItemPropertyArtist] = artist
    }
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = "东方音乐电台 THMR"
    let durationSec = ((args["duration"] as? NSNumber)?.doubleValue ?? 0)
      / 1_000_000
    let positionSec = ((args["position"] as? NSNumber)?.doubleValue ?? 0)
      / 1_000_000
    if durationSec > 0 {
      nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = durationSec
      nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = positionSec
    } else {
      nowPlayingInfo.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
      nowPlayingInfo.removeValue(
        forKey: MPNowPlayingInfoPropertyElapsedPlaybackTime)
    }
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] =
      isPlaying ? 1.0 : 0.0
    push()
    updateArtwork(urlString: args["artwork"] as? String ?? "")
  }

  private func push() {
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    if #available(macOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState =
        isPlaying ? .playing : .paused
    }
  }

  private func updateArtwork(urlString: String) {
    if urlString.isEmpty {
      currentArtworkURL = ""
      applyArtwork(fallbackImage())
      return
    }
    guard urlString != currentArtworkURL else { return }
    currentArtworkURL = urlString
    artworkTask?.cancel()
    guard let url = URL(string: urlString),
          url.scheme == "http" || url.scheme == "https" else {
      applyArtwork(fallbackImage())
      return
    }
    artworkTask = URLSession.shared.dataTask(with: url) {
      [weak self] data, _, _ in
      guard let self, let data, let image = NSImage(data: data) else { return }
      DispatchQueue.main.async {
        // 封面下载返回时，忽略已经切换走的曲目。
        guard self.currentArtworkURL == urlString else { return }
        self.applyArtwork(image)
      }
    }
    artworkTask?.resume()
  }

  private func applyArtwork(_ image: NSImage?) {
    guard let image else { return }
    nowPlayingInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
      boundsSize: image.size
    ) { _ in image }
    push()
  }

  private func fallbackImage() -> NSImage? {
    if fallbackArtwork == nil {
      fallbackArtwork = NSApp?.applicationIconImage
    }
    return fallbackArtwork
  }

  private func clear() {
    artworkTask?.cancel()
    artworkTask = nil
    currentArtworkURL = ""
    isPlaying = false
    nowPlayingInfo.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    if #available(macOS 13.0, *) {
      MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
  }

  private func send(_ command: String) {
    channel?.invokeMethod("command", arguments: ["command": command])
  }
}
