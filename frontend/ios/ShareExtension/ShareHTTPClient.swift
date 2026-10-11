import Foundation

final class ShareHTTPClient: NSObject, URLSessionDataDelegate {
  private let configuration: URLSessionConfiguration
  init(configuration: URLSessionConfiguration = .ephemeral) {
    self.configuration = configuration
    super.init()
  }
  private var continuation: CheckedContinuation<(Data, Int), Error>?
  private var body = Data()
  private var status = 0
  private lazy var session: URLSession = {
    configuration.timeoutIntervalForRequest = 30
    configuration.timeoutIntervalForResource = 150
    configuration.httpShouldSetCookies = false
    configuration.urlCache = nil
    return URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
  }()

  func perform(_ request: URLRequest, file: URL? = nil) async throws -> (Data, Int) {
    try Task.checkCancellation()
    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      body = Data()
      status = 0
      let task: URLSessionTask
      if let file { task = session.uploadTask(with: request, fromFile: file) }
      else { task = session.dataTask(with: request) }
      task.resume()
    }
  }

  func close() { session.invalidateAndCancel() }

  func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
    completionHandler(nil)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                  completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
    status = (response as? HTTPURLResponse)?.statusCode ?? 0
    completionHandler(response.expectedContentLength > 128 * 1024 ? .cancel : .allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard body.count + data.count <= 128 * 1024 else { dataTask.cancel(); return }
    body.append(data)
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let pending = continuation
    continuation = nil
    if let error { pending?.resume(throwing: error) }
    else { pending?.resume(returning: (body, status)) }
  }
}

struct ShareUploadAPI {
  let client: ShareHTTPClient

  func identity(_ session: ShareSession) async throws -> String {
    var request = URLRequest(url: try session.url("/api/v1/auth/session"))
    request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
    let (data, status) = try await client.perform(request)
    guard status == 200,
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let user = value["user"] as? [String: Any], user["id"] as? String == session.context.userId,
          user["mustChangePassword"] as? Bool == false,
          let account = value["account"] as? [String: Any], account["id"] as? String == session.context.accountId,
          let name = account["name"] as? String,
          let permissions = value["permissions"] as? [String], permissions.contains("documents:upload") else {
      throw ShareUploadFailure.message("Open Domabas and sign in to a library with upload permission. Then share again.")
    }
    return name
  }

  func upload(_ file: ShareUploadFile, body: URL, boundary: String, session: ShareSession) async -> String {
    do {
      var request = URLRequest(url: try session.url("/api/v1/documents/upload"))
      request.httpMethod = "POST"
      request.setValue("Bearer \(session.token)", forHTTPHeaderField: "Authorization")
      request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
      let (data, status) = try await client.perform(request, file: body)
      switch status {
      case 202 where file.validateReceipt(data, userId: session.context.userId): return "Accepted — processing continues."
      case 409: return "Already in this library."
      case 400: return "Not uploaded: the server rejected this file."
      case 401, 403: return "Not uploaded: sign in again with upload permission."
      case 413: return "Not uploaded: the file exceeds the server's size limit."
      case 415: return "Not uploaded: the server does not support this file."
      case 429: return "Not uploaded: the server is busy. Try sharing later."
      default: return "Outcome unknown. Check the library before sharing again."
      }
    } catch { return "Outcome unknown. Check the library before sharing again." }
  }
}
