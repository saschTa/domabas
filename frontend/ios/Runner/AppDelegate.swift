import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "VisionKitDocumentScannerChannel") {
      VisionKitDocumentScannerChannel.register(with: registrar)
    }
    let channel = FlutterMethodChannel(
      name: "dev.domabas/scanner_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "excludeFromBackup",
            let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String,
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        result(FlutterMethodNotImplemented)
        return
      }
      var directory = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
      let expected = support.appendingPathComponent("scanner-v1", isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
      guard directory == expected else {
        result(FlutterError(code: "invalid_path", message: "Invalid scanner storage path", details: nil))
        return
      }
      do {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        result(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
      } catch {
        result(FlutterError(code: "backup_exclusion", message: "Scanner backup exclusion failed", details: nil))
      }
    }
  }
}
