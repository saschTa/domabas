import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest

final class ShareUploadTests: XCTestCase {
  private var directory: URL!

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try FileManager.default.removeItem(at: directory)
  }

  func testOriginalBytesAndMultipartArePreservedAndNamesCannotInjectHeaders() throws {
    let bytes = Data("%PDF-1.7\nexample".utf8)
    let original = directory.appendingPathComponent("source.pdf")
    try bytes.write(to: original)
    let file = try ShareUploadFile.prepare(original, name: "../invoice\r\n\".pdf", directory: directory)
    XCTAssertEqual(file.mediaType, "application/pdf")
    XCTAssertEqual(file.size, bytes.count)
    XCTAssertEqual(file.hash, ShareSessionStore.hash(bytes))
    XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    XCTAssertFalse(file.filename.contains("/"))
    XCTAssertFalse(file.filename.contains("\r"))
    XCTAssertFalse(file.filename.contains("\""))
    let body = try file.multipart(in: directory, boundary: "test-boundary")
    let data = try Data(contentsOf: body)
    XCTAssertNotNil(data.range(of: bytes))
    XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("name=\"metadata\"\r\nContent-Type: application/json"))
    XCTAssertTrue(data.suffix(21).elementsEqual(Data("\r\n--test-boundary--\r\n".utf8)))
    XCTAssertLessThanOrEqual(ShareUploadFile.safeName(String(repeating: "😀", count: 100)).utf8.count, 255)
    let spaced = try ShareUploadFile.prepare(original, name: " invoice .pdf", directory: directory)
    XCTAssertEqual(spaced.title, "invoice")
  }

  func testEmptyOversizedAndNonImagesAreRejected() throws {
    let file = directory.appendingPathComponent("empty.pdf")
    try Data().write(to: file)
    XCTAssertThrowsError(try ShareUploadFile.prepare(file, name: "empty.pdf", directory: directory))
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: UInt64(ShareUploadFile.byteLimit + 1))
    try handle.close()
    XCTAssertThrowsError(try ShareUploadFile.prepare(file, name: "huge.pdf", directory: directory))
    try Data("not an image".utf8).write(to: file)
    XCTAssertThrowsError(try ShareUploadFile.prepare(file, name: "spoof.jpg", directory: directory))
  }

  func testPNGAndJPEGOriginalsRemainUnchangedAndOtherStillImagesConvert() throws {
    let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 100)).image { context in
      UIColor.red.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 60, height: 100))
    }
    for (name, bytes, media) in [("a.png", image.pngData()!, "image/png"), ("a.jpg", image.jpegData(compressionQuality: 0.9)!, "image/jpeg")] {
      let input = directory.appendingPathComponent(name)
      try bytes.write(to: input)
      let file = try ShareUploadFile.prepare(input, name: name, directory: directory)
      XCTAssertEqual(file.mediaType, media)
      XCTAssertEqual(try Data(contentsOf: file.url), bytes)
    }
    let input = directory.appendingPathComponent("image.tiff")
    let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(input as CFURL, UTType.tiff.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(writer, image.cgImage!, nil)
    XCTAssertTrue(CGImageDestinationFinalize(writer))
    let converted = try ShareUploadFile.prepare(input, name: "image.tiff", directory: directory)
    XCTAssertEqual(converted.filename, "image.jpg")
    XCTAssertEqual(converted.mediaType, "image/jpeg")
    XCTAssertNotNil(UIImage(data: try Data(contentsOf: converted.url)))
  }

  func testReceiptMustMatchOriginalAndUploader() throws {
    let input = directory.appendingPathComponent("a.pdf")
    try Data("%PDF-1.7\nreceipt".utf8).write(to: input)
    let file = try ShareUploadFile.prepare(input, name: "a.pdf", directory: directory)
    let user = UUID().uuidString
    var original: [String: Any] = ["originalFilename": file.filename, "mediaType": file.mediaType,
                                  "size": file.size, "sha256": file.hash, "uploaderId": user]
    func receipt() throws -> Data {
      try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "title": file.title, "file": original])
    }
    XCTAssertTrue(file.validateReceipt(try receipt(), userId: user))
    XCTAssertFalse(file.validateReceipt(try receipt(), userId: UUID().uuidString))
    original["size"] = file.size + 1
    XCTAssertFalse(file.validateReceipt(try receipt(), userId: user))
    original["size"] = file.size
    original["sha256"] = String(repeating: "0", count: 64)
    XCTAssertFalse(file.validateReceipt(try receipt(), userId: user))
    XCTAssertFalse(file.validateReceipt(Data("{}".utf8), userId: user))
  }

  func testAttachmentReceiverCopiesTemporaryFilesAndRejectsCancelledLoads() async throws {
    let source = directory.appendingPathComponent("upload.multipart")
    let bytes = Data("%PDF-1.7\nprovider-original".utf8)
    try bytes.write(to: source)
    let destination = directory.appendingPathComponent("received")
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let provider = NSItemProvider()
    provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { complete in
      complete(source, false, nil)
      return nil
    }
    let receiver = ShareAttachmentReceiver()
    let received = try await receiver.receive(provider, in: destination)
    XCTAssertTrue(received.name.hasPrefix("upload.multipart"))
    XCTAssertEqual(received.url.lastPathComponent, "original.data")
    try FileManager.default.removeItem(at: source)
    XCTAssertEqual(try Data(contentsOf: received.url), bytes)
    let file = try ShareUploadFile.prepare(received.url, name: "upload.multipart", directory: destination)
    let body = try file.multipart(in: destination, boundary: "test")
    XCTAssertNotNil(try Data(contentsOf: body).range(of: bytes))
    let cancelled = ShareAttachmentReceiver()
    cancelled.cancel()
    do {
      _ = try await cancelled.receive(provider, in: destination)
      XCTFail("Cancelled acquisition must not read the provider")
    } catch is CancellationError { }
  }

  func testEndpointsPreservePathAndRejectCredentialsOrQueries() throws {
    func session(_ endpoint: String) -> ShareSession {
      ShareSession(context: ShareSessionContext(endpoint: endpoint, credentialKey: "key", tokenHash: "hash", userId: "user", accountId: "account"), token: "token")
    }
    XCTAssertEqual(try session("https://example.com/domabas/").url("/api/v1/auth/session").absoluteString,
                   "https://example.com/domabas/api/v1/auth/session")
    for endpoint in ["file:///tmp/server", "https://user:password@example.com", "https://example.com?secret=1", "https://example.com#x"] {
      XCTAssertThrowsError(try session(endpoint).url("/api/v1/auth/session"))
    }
  }

  @MainActor
  func testHTTPBoundsResponsesRejectsRedirectsAndReportsAuthorizationFailures() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ShareTestURLProtocol.self]
    let client = ShareHTTPClient(configuration: configuration)
    defer { client.close() }
    let session = ShareSession(context: ShareSessionContext(endpoint: "https://example.com", credentialKey: "key", tokenHash: "hash", userId: "user", accountId: "account"), token: "token")
    ShareTestURLProtocol.status = 200
    ShareTestURLProtocol.body = try JSONSerialization.data(withJSONObject: [
      "user": ["id": "user", "mustChangePassword": false], "account": ["id": "account", "name": "Library"],
      "permissions": ["documents:upload"],
    ])
    let library = try await ShareUploadAPI(client: client).identity(session)
    XCTAssertEqual(library, "Library")
    ShareTestURLProtocol.status = 403
    do {
      _ = try await ShareUploadAPI(client: client).identity(session)
      XCTFail("Forbidden identity must not be accepted")
    } catch { }
    ShareTestURLProtocol.status = 200
    ShareTestURLProtocol.body = Data(repeating: 32, count: 128 * 1024 + 1)
    do {
      _ = try await client.perform(URLRequest(url: URL(string: "https://example.com/oversize")!))
      XCTFail("Oversized response must not be accepted")
    } catch { }
    let url = URL(string: "https://other.example")!
    client.urlSession(URLSession.shared, task: URLSession.shared.dataTask(with: url),
      willPerformHTTPRedirection: HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil)!,
      newRequest: URLRequest(url: url)) { XCTAssertNil($0) }
  }
}

private final class ShareTestURLProtocol: URLProtocol {
  static var status = 200
  static var body = Data()
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                   headerFields: ["Content-Length": String(Self.body.count)])!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Self.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
