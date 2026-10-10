import AVFoundation
import CoreImage
import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {
  func testPageEncoderPreservesPixelDimensionsAndEveryOrientation() throws {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let original = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).image { context in
      for (index, color) in [UIColor.red, UIColor.green, UIColor.blue, UIColor.yellow].enumerated() {
        color.setFill()
        context.fill(CGRect(x: (index % 2) * 40, y: (index / 2) * 60, width: 40, height: 60))
      }
    }
    let source = try XCTUnwrap(original.cgImage)
    let orientations: [(UIImage.Orientation, [Int])] = [
      (.up, [0, 1, 2, 3]),
      (.down, [3, 2, 1, 0]),
      (.left, [1, 3, 0, 2]),
      (.right, [2, 0, 3, 1]),
      (.upMirrored, [1, 0, 3, 2]),
      (.downMirrored, [2, 3, 0, 1]),
      (.leftMirrored, [0, 2, 1, 3]),
      (.rightMirrored, [3, 1, 2, 0]),
    ]
    for (orientation, expectedColors) in orientations {
      let image = UIImage(cgImage: source, scale: 3, orientation: orientation)
      let bytes = try VisionKitPageEncoder.encode(image)
      let decoded = try XCTUnwrap(UIImage(data: bytes))
      let pixels = try XCTUnwrap(decoded.cgImage)
      let rotated = [.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
      XCTAssertEqual(pixels.width, rotated ? 120 : 80, "\(orientation)")
      XCTAssertEqual(pixels.height, rotated ? 80 : 120, "\(orientation)")
      XCTAssertEqual(decoded.imageOrientation, .up, "\(orientation)")
      XCTAssertEqual(try quadrantColors(pixels), expectedColors, "\(orientation)")
    }
  }

  func testPageEncoderRejectsDimensionsBeforeRasterizing() throws {
    for size in [CGSize.zero, CGSize(width: CGFloat.infinity, height: 1),
                 CGSize(width: 1, height: CGFloat.nan), CGSize(width: -1, height: 1),
                 CGSize(width: 1.5, height: 2)] {
      XCTAssertThrowsError(try VisionKitPageEncoder.validate(size)) { failure in
        XCTAssertEqual(failure as? VisionKitScannerFailure, .invalidResult)
      }
    }
    try VisionKitPageEncoder.validate(CGSize(width: 10_000, height: 5_000))
    let hugeImage = CIImage(color: CIColor(red: 1, green: 1, blue: 1))
      .cropped(to: CGRect(x: 0, y: 0, width: 10_000, height: 5_001))
    XCTAssertThrowsError(try VisionKitPageEncoder.encode(UIImage(ciImage: hugeImage))) { failure in
      XCTAssertEqual(failure as? VisionKitScannerFailure, .tooLarge)
    }
    XCTAssertThrowsError(try VisionKitPageEncoder.encode(UIImage())) { failure in
      XCTAssertEqual(failure as? VisionKitScannerFailure, .invalidResult)
    }
  }

  func testReplyCompletesExactlyOnceEvenWhenCompletionReenters() {
    var replies = 0
    var reply: VisionKitScannerReply!
    reply = VisionKitScannerReply { _ in
      replies += 1
      reply.resolve(nil)
    }
    reply.resolve(1)
    reply.resolve(2)
    XCTAssertEqual(replies, 1)
  }

  @MainActor
  func testCancellationDrainsPermissionAndRejectsStaleCallbacks() {
    var permissionCallbacks: [(Bool) -> Void] = []
    let channel = VisionKitDocumentScannerChannel(
      presenter: { nil }, isSupported: { true }, authorizationStatus: { .notDetermined },
      requestAccess: { permissionCallbacks.append($0) }
    )
    var scanErrors: [String] = []
    var cancelled = 0
    call(channel, "scan", ["id": "old", "maxPages": 2]) {
      scanErrors.append(($0 as? FlutterError)?.code ?? "unexpected")
    }
    call(channel, "cancel", ["id": "old"]) { _ in cancelled += 1 }
    XCTAssertEqual(scanErrors, ["scan_cancelled"])
    XCTAssertEqual(cancelled, 0)
    call(channel, "scan", ["id": "new", "maxPages": 2]) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "scan_busy")
    }
    permissionCallbacks[0](true)
    flushMainQueue()
    XCTAssertEqual(cancelled, 1)
    XCTAssertEqual(scanErrors, ["scan_cancelled"])

    call(channel, "scan", ["id": "new", "maxPages": 2]) {
      scanErrors.append(($0 as? FlutterError)?.code ?? "unexpected")
    }
    XCTAssertEqual(permissionCallbacks.count, 2)
    call(channel, "cancel", ["id": "old"]) { XCTAssertNil($0) }
    call(channel, "finish", ["id": "old"]) { XCTAssertNil($0) }
    permissionCallbacks[0](false)
    flushMainQueue()
    XCTAssertEqual(scanErrors, ["scan_cancelled"])
    call(channel, "finish", ["id": "new"]) { _ in cancelled += 1 }
    permissionCallbacks[1](false)
    flushMainQueue()
    XCTAssertEqual(cancelled, 2)
    XCTAssertEqual(scanErrors, ["scan_cancelled", "scan_cancelled"])
    call(channel, "finish", ["id": "new"]) { XCTAssertNil($0) }
  }

  @MainActor
  func testScannerRejectsInvalidArgumentsAndUnavailablePresenters() {
    let channel = VisionKitDocumentScannerChannel(
      presenter: { nil }, isSupported: { true }, authorizationStatus: { .authorized }
    )
    for limit: Any in [0, 21, 1.5, true] {
      call(channel, "scan", ["id": "request", "maxPages": limit]) {
        XCTAssertEqual(($0 as? FlutterError)?.code, "scan_result_invalid")
      }
    }
    call(channel, "scan", ["id": "request", "maxPages": 20]) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "scan_activity_unavailable")
    }
    call(channel, "readPage", ["id": "request", "index": 0]) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "scan_cancelled")
    }
    for (authorization, expected) in [
      (AVAuthorizationStatus.denied, "scan_permission_denied"),
      (AVAuthorizationStatus.restricted, "scan_permission_restricted"),
    ] {
      let denied = VisionKitDocumentScannerChannel(
        presenter: { nil }, isSupported: { true }, authorizationStatus: { authorization }
      )
      call(denied, "scan", ["id": "request", "maxPages": 1]) {
        XCTAssertEqual(($0 as? FlutterError)?.code, expected)
      }
    }
    let unsupported = VisionKitDocumentScannerChannel(presenter: { nil }, isSupported: { false })
    call(unsupported, "scan", ["id": "request", "maxPages": 1]) {
      XCTAssertEqual(($0 as? FlutterError)?.code, "scan_unsupported")
    }
  }

  private func call(
    _ channel: VisionKitDocumentScannerChannel,
    _ method: String,
    _ arguments: [String: Any],
    result: @escaping FlutterResult
  ) {
    channel.handle(FlutterMethodCall(methodName: method, arguments: arguments), result: result)
  }

  private func flushMainQueue() {
    let completed = expectation(description: "main queue callbacks")
    DispatchQueue.main.async { completed.fulfill() }
    wait(for: [completed], timeout: 2)
  }

  private func quadrantColors(_ image: CGImage) throws -> [Int] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try XCTUnwrap(CGContext(
      data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8,
      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return (0..<4).map { quadrant in
      let x = image.width * (quadrant % 2 == 0 ? 1 : 3) / 4
      let y = image.height * (quadrant < 2 ? 1 : 3) / 4
      let offset = (y * image.width + x) * 4
      let red = bytes[offset] > 128
      let green = bytes[offset + 1] > 128
      return red ? (green ? 3 : 0) : (green ? 1 : 2)
    }
  }
}
