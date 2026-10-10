import Flutter
import Foundation

final class MobileShareChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let store = ShareSessionStore()
    let channel = FlutterMethodChannel(name: "dev.domabas/mobile_share", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setSession" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let context: ShareSessionContext?
        if call.arguments == nil || call.arguments is NSNull {
          context = nil
        } else {
          let data = try JSONSerialization.data(withJSONObject: call.arguments as Any)
          context = try JSONDecoder().decode(ShareSessionContext.self, from: data)
        }
        try store.setContext(context)
        result(nil)
      } catch {
        result(FlutterError(code: "share_session_unavailable", message: "Sharing session is unavailable.", details: nil))
      }
    }
  }
}
