import Flutter
import UIKit

/// 原生 → Flutter 文件打开通道名
private let fileOpenChannel = "hexo/file_open"

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var pendingOpenFilePath: String?
  private var fileChannel: FlutterMethodChannel?
  private var engineReady = false

  /// 冷启动：引擎就绪后注册通道
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.flutterEngine.binaryMessenger
    let channel = FlutterMethodChannel(name: fileOpenChannel, binaryMessenger: messenger)

    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "getPendingOpenFile":
        result(self?.pendingOpenFilePath)
        self?.pendingOpenFilePath = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    fileChannel = channel
    engineReady = true
    flushPendingFile()
  }

  /// 外部文件打开（冷启动/热启动均触发）
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    handleFileURL(url)
    return true
  }

  /// 处理文件 URL：复制到缓存目录，记录路径
  func handleFileURL(_ url: URL) {
    guard url.isFileURL else { return }
    let name = url.lastPathComponent
    let dest = FileManager.default.temporaryDirectory.appendingPathComponent(name)
    try? FileManager.default.copyItem(at: url, to: dest)
    pendingOpenFilePath = dest.path
    flushPendingFile()
  }

  /// 引擎就绪且有缓存路径时主动推送
  private func flushPendingFile() {
    guard engineReady, let path = pendingOpenFilePath else { return }
    fileChannel?.invokeMethod("onOpenFile", arguments: path)
    pendingOpenFilePath = nil
  }
}