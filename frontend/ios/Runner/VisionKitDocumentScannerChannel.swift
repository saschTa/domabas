import AVFoundation
import CoreImage
import Flutter
import UIKit
import VisionKit

final class VisionKitScannerReply {
  private var callback: FlutterResult?

  init(_ callback: @escaping FlutterResult) {
    self.callback = callback
  }

  func resolve(_ value: Any?) {
    let callback = self.callback
    self.callback = nil
    callback?(value)
  }
}

enum VisionKitScannerFailure: String, Error {
  case invalidResult = "scan_result_invalid"
  case tooLarge = "scan_too_large"
  case readFailed = "scan_read_failed"

  var flutterError: FlutterError {
    FlutterError(code: rawValue, message: "The scanned page could not be prepared.", details: nil)
  }
}

struct VisionKitPageEncoder {
  static let maximumPixels = 50_000_000
  static let maximumBytes = 18 * 1024 * 1024

  static func encode(_ image: UIImage) throws -> Data {
    let dimensions: CGSize
    if let pixels = image.cgImage {
      dimensions = CGSize(width: pixels.width, height: pixels.height)
    } else if let pixels = image.ciImage {
      guard pixels.extent.origin.x.isFinite, pixels.extent.origin.y.isFinite,
            pixels.extent.origin.x.rounded(.down) == pixels.extent.origin.x,
            pixels.extent.origin.y.rounded(.down) == pixels.extent.origin.y else {
        throw VisionKitScannerFailure.invalidResult
      }
      dimensions = pixels.extent.size
    } else {
      throw VisionKitScannerFailure.invalidResult
    }
    try validate(dimensions)
    guard image.scale.isFinite, image.scale > 0 else {
      throw VisionKitScannerFailure.invalidResult
    }

    let source: CGImage
    if let pixels = image.cgImage {
      source = pixels
    } else if let pixels = image.ciImage,
              let converted = CIContext().createCGImage(pixels, from: pixels.extent) {
      source = converted
    } else {
      throw VisionKitScannerFailure.readFailed
    }
    try validate(CGSize(width: source.width, height: source.height))
    let rotated: Bool
    switch image.imageOrientation {
    case .left, .right, .leftMirrored, .rightMirrored:
      rotated = true
    default:
      rotated = false
    }
    let size = CGSize(
      width: rotated ? source.height : source.width,
      height: rotated ? source.width : source.height
    )
    let pixels = UIImage(cgImage: source, scale: 1, orientation: image.imageOrientation)
    let upright: UIImage
    if image.imageOrientation == .up {
      upright = pixels
    } else {
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      format.opaque = true
      format.preferredRange = .standard
      upright = UIGraphicsImageRenderer(size: size, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: size))
        context.cgContext.interpolationQuality = .none
        pixels.draw(in: CGRect(origin: .zero, size: size))
      }
    }
    guard let encoded = upright.jpegData(compressionQuality: 1), !encoded.isEmpty else {
      throw VisionKitScannerFailure.readFailed
    }
    guard encoded.count <= maximumBytes else {
      throw VisionKitScannerFailure.tooLarge
    }
    return encoded
  }

  static func validate(_ size: CGSize) throws {
    guard size.width.isFinite, size.height.isFinite,
          size.width > 0, size.height > 0,
          size.width.rounded(.down) == size.width,
          size.height.rounded(.down) == size.height else {
      throw VisionKitScannerFailure.invalidResult
    }
    guard size.width <= CGFloat(maximumPixels) / size.height else {
      throw VisionKitScannerFailure.tooLarge
    }
  }
}

final class VisionKitDocumentScannerSession {
  let id: String
  let maximumPages: Int
  let scanReply: VisionKitScannerReply
  var scan: VNDocumentCameraScan?
  var controller: VNDocumentCameraViewController?
  var readReply: VisionKitScannerReply?
  var closeReplies: [VisionKitScannerReply] = []
  var activationObservers: [NSObjectProtocol] = []
  var permissionPending = false
  var presenting = false
  var dismissing = false
  var encoding = false
  var terminating = false
  var captured = false

  init(id: String, maximumPages: Int, result: @escaping FlutterResult) {
    self.id = id
    self.maximumPages = maximumPages
    scanReply = VisionKitScannerReply(result)
  }
}

final class VisionKitDocumentScannerChannel: NSObject, FlutterPlugin,
  VNDocumentCameraViewControllerDelegate, UIAdaptivePresentationControllerDelegate {
  private let encoderQueue = DispatchQueue(label: "dev.domabas.visionkit.encoder", qos: .userInitiated)
  private let presenter: () -> UIViewController?
  private let isSupported: () -> Bool
  private let authorizationStatus: () -> AVAuthorizationStatus
  private let requestAccess: (@escaping (Bool) -> Void) -> Void
  private var session: VisionKitDocumentScannerSession?
  private var attached = true

  init(
    presenter: @escaping () -> UIViewController?,
    isSupported: @escaping () -> Bool = { VNDocumentCameraViewController.isSupported },
    authorizationStatus: @escaping () -> AVAuthorizationStatus = {
      AVCaptureDevice.authorizationStatus(for: .video)
    },
    requestAccess: @escaping (@escaping (Bool) -> Void) -> Void = {
      AVCaptureDevice.requestAccess(for: .video, completionHandler: $0)
    }
  ) {
    self.presenter = presenter
    self.isSupported = isSupported
    self.authorizationStatus = authorizationStatus
    self.requestAccess = requestAccess
  }

  static func register(with registrar: FlutterPluginRegistrar) {
    let scanner = VisionKitDocumentScannerChannel(presenter: { [weak registrar] in
      registrar?.viewController
    })
    let channel = FlutterMethodChannel(
      name: "dev.domabas/visionkit_document_scanner",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(scanner, channel: channel)
    registrar.publish(scanner)
  }

  func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    attached = false
    if let session {
      terminate(session)
    }
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["scan", "readPage", "finish", "cancel"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let arguments = call.arguments as? [String: Any],
          let id = arguments["id"] as? String, !id.isEmpty, id.count <= 128 else {
      result(error("scan_result_invalid"))
      return
    }
    switch call.method {
    case "scan":
      guard let maximum = integer(arguments["maxPages"]), (1...20).contains(maximum) else {
        result(error("scan_result_invalid"))
        return
      }
      begin(id: id, maximumPages: maximum, result: result)
    case "readPage":
      guard let index = integer(arguments["index"]) else {
        result(error("scan_result_invalid"))
        return
      }
      read(id: id, index: index, result: result)
    default:
      guard let session, session.id == id else {
        result(nil)
        return
      }
      session.closeReplies.append(VisionKitScannerReply(result))
      terminate(session)
    }
  }

  private func begin(id: String, maximumPages: Int, result: @escaping FlutterResult) {
    guard attached else {
      result(error("scan_activity_unavailable"))
      return
    }
    guard session == nil else {
      result(error("scan_busy"))
      return
    }
    guard isSupported() else {
      result(error("scan_unsupported"))
      return
    }
    let current = VisionKitDocumentScannerSession(id: id, maximumPages: maximumPages, result: result)
    session = current
    switch authorizationStatus() {
    case .authorized:
      present(current)
    case .notDetermined:
      current.permissionPending = true
      requestAccess { [self, current] granted in
        DispatchQueue.main.async {
          guard self.session === current else { return }
          current.permissionPending = false
          if current.terminating {
            self.settleTermination(current)
          } else if granted {
            self.presentAfterPermission(current)
          } else {
            self.fail(current, code: self.authorizationStatus() == .restricted
              ? "scan_permission_restricted" : "scan_permission_denied")
          }
        }
      }
    case .denied:
      fail(current, code: "scan_permission_denied")
    case .restricted:
      fail(current, code: "scan_permission_restricted")
    @unknown default:
      fail(current, code: "scan_permission_denied")
    }
  }

  private func presentAfterPermission(_ current: VisionKitDocumentScannerSession) {
    guard session === current, !current.terminating else { return }
    guard let scene = presenter()?.viewIfLoaded?.window?.windowScene else {
      fail(current, code: "scan_activity_unavailable")
      return
    }
    if scene.activationState == .foregroundActive {
      present(current)
      return
    }
    guard scene.activationState != .unattached else {
      fail(current, code: "scan_activity_unavailable")
      return
    }
    let center = NotificationCenter.default
    current.activationObservers = [
      center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) {
        [self, current] _ in
        guard self.session === current, !current.terminating else { return }
        self.removeActivationObservers(current)
        self.present(current)
      },
      center.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) {
        [self, current] _ in
        guard self.session === current else { return }
        self.fail(current, code: "scan_activity_unavailable")
      },
    ]
  }

  private func removeActivationObservers(_ current: VisionKitDocumentScannerSession) {
    for observer in current.activationObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    current.activationObservers = []
  }

  private func present(_ current: VisionKitDocumentScannerSession) {
    guard session === current, !current.terminating else { return }
    guard let presenter = presenter(),
          let scene = presenter.viewIfLoaded?.window?.windowScene,
          scene.activationState == .foregroundActive,
          presenter.presentedViewController == nil,
          !presenter.isBeingDismissed, !presenter.isBeingPresented else {
      fail(current, code: "scan_activity_unavailable")
      return
    }
    let controller = VNDocumentCameraViewController()
    controller.delegate = self
    controller.modalPresentationStyle = .fullScreen
    controller.isModalInPresentation = true
    current.controller = controller
    current.presenting = true
    presenter.present(controller, animated: true) { [self, current] in
      guard self.session === current else { return }
      current.presenting = false
      if current.terminating || current.captured {
        self.dismiss(current)
      } else if controller.presentingViewController == nil {
        self.fail(current, code: "scan_activity_unavailable")
      }
    }
    controller.presentationController?.delegate = self
  }

  private func read(id: String, index: Int, result: @escaping FlutterResult) {
    guard let current = session, current.id == id, !current.terminating,
          let scan = current.scan else {
      result(error("scan_cancelled"))
      return
    }
    guard !current.encoding, !current.dismissing, !current.presenting else {
      result(error("scan_busy"))
      return
    }
    guard index >= 0, index < scan.pageCount else {
      result(error("scan_result_invalid"))
      return
    }
    let reply = VisionKitScannerReply(result)
    current.readReply = reply
    current.encoding = true
    let image = scan.imageOfPage(at: index)
    encoderQueue.async { [self, current] in
      let encoded: Result<Data, Error> = autoreleasepool {
        Result { try VisionKitPageEncoder.encode(image) }
      }
      DispatchQueue.main.async {
        guard self.session === current, current.readReply === reply else { return }
        current.encoding = false
        current.readReply = nil
        if current.terminating {
          self.settleTermination(current)
          return
        }
        switch encoded {
        case .success(let bytes):
          reply.resolve(FlutterStandardTypedData(bytes: bytes))
        case .failure(let failure):
          reply.resolve((failure as? VisionKitScannerFailure)?.flutterError
            ?? self.error("scan_read_failed"))
        }
      }
    }
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    guard let current = session, current.controller === controller,
          !current.terminating, !current.captured else { return }
    current.captured = true
    guard scan.pageCount > 0 else {
      fail(current, code: "scan_result_invalid")
      return
    }
    guard scan.pageCount <= current.maximumPages else {
      fail(current, code: "scan_too_many_pages")
      return
    }
    current.scan = scan
    dismiss(current)
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    guard let current = session, current.controller === controller,
          !current.terminating, !current.captured else { return }
    current.scanReply.resolve(nil)
    terminate(current)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError failure: Error
  ) {
    guard let current = session, current.controller === controller,
          !current.terminating, !current.captured else { return }
    fail(current, code: "scan_failed")
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard let current = session,
          current.controller === presentationController.presentedViewController else { return }
    current.controller = nil
    current.presenting = false
    current.dismissing = false
    if !current.captured {
      current.scanReply.resolve(nil)
      terminate(current)
    } else if current.terminating {
      settleTermination(current)
    } else if let scan = current.scan {
      current.scanReply.resolve(scan.pageCount)
    }
  }

  private func fail(_ current: VisionKitDocumentScannerSession, code: String) {
    guard session === current else { return }
    current.scanReply.resolve(error(code))
    terminate(current)
  }

  private func terminate(_ current: VisionKitDocumentScannerSession) {
    guard session === current else { return }
    current.terminating = true
    removeActivationObservers(current)
    current.scan = nil
    current.scanReply.resolve(error("scan_cancelled"))
    current.readReply?.resolve(error("scan_cancelled"))
    dismiss(current)
  }

  private func dismiss(_ current: VisionKitDocumentScannerSession) {
    guard session === current, !current.presenting, !current.dismissing else { return }
    guard let controller = current.controller else {
      settleDismissal(current)
      return
    }
    guard controller.presentingViewController != nil else {
      current.controller = nil
      settleDismissal(current)
      return
    }
    current.dismissing = true
    controller.dismiss(animated: true) { [self, current] in
      guard self.session === current, current.controller === controller else { return }
      current.controller = nil
      current.dismissing = false
      self.settleDismissal(current)
    }
  }

  private func settleDismissal(_ current: VisionKitDocumentScannerSession) {
    guard session === current else { return }
    if current.terminating {
      settleTermination(current)
    } else if let scan = current.scan {
      current.scanReply.resolve(scan.pageCount)
    }
  }

  private func settleTermination(_ current: VisionKitDocumentScannerSession) {
    guard session === current, current.terminating,
          !current.permissionPending, !current.presenting, !current.dismissing,
          !current.encoding, current.controller == nil else { return }
    session = nil
    let replies = current.closeReplies
    current.closeReplies = []
    for reply in replies {
      reply.resolve(nil)
    }
  }

  private func integer(_ value: Any?) -> Int? {
    guard let number = value as? NSNumber,
          CFGetTypeID(number) != CFBooleanGetTypeID(),
          number.doubleValue.isFinite,
          number.doubleValue >= Double(Int32.min),
          number.doubleValue <= Double(Int32.max),
          number.doubleValue == Double(number.intValue) else { return nil }
    return number.intValue
  }

  private func error(_ code: String) -> FlutterError {
    FlutterError(code: code, message: "The document scanner could not complete this request.", details: nil)
  }
}
