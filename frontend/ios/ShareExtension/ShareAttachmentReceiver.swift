import Foundation
import UniformTypeIdentifiers

final class ShareAttachmentReceiver {
  private let lock = NSLock()
  private var reply: CheckedContinuation<(url: URL, name: String), Error>?
  private var ended = false
  private var progress: Progress?
  private var deadline: DispatchWorkItem?

  func receive(_ provider: NSItemProvider, in directory: URL) async throws -> (url: URL, name: String) {
    guard let type = [UTType.pdf, .png, .jpeg, .image].first(where: {
      provider.hasItemConformingToTypeIdentifier($0.identifier)
    }) else { throw ShareUploadFailure.message("Share a PDF or an image.") }
    return try await withCheckedThrowingContinuation { continuation in
      lock.lock()
      if ended {
        lock.unlock()
        continuation.resume(throwing: CancellationError())
        return
      }
      reply = continuation
      lock.unlock()
      let timeout = DispatchWorkItem { [weak self] in
        self?.cancel(ShareUploadFailure.message("The source app stopped responding. Download the file there and share again."))
      }
      lock.lock()
      deadline = timeout
      let cancelled = ended
      lock.unlock()
      if cancelled { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: timeout)
      let loading = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { [self] source, error in
        do {
          try checkPending()
          guard let source, error == nil else {
            throw ShareUploadFailure.message("The source app could not provide this file. Download it there and share again.")
          }
          let access = source.startAccessingSecurityScopedResource()
          defer { if access { source.stopAccessingSecurityScopedResource() } }
          let info = try source.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
          guard info.isRegularFile == true, (info.fileSize ?? 0) <= ShareUploadFile.byteLimit else {
            throw ShareUploadFailure.message("Share a regular file no larger than 100 MiB.")
          }
          let target = directory.appendingPathComponent("original.data")
          let input = try FileHandle(forReadingFrom: source)
          defer { try? input.close() }
          try checkPending()
          guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw ShareUploadFailure.message("The shared file could not be saved.")
          }
          let output = try FileHandle(forWritingTo: target)
          defer { try? output.close() }
          var length = 0
          while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
            try checkPending()
            length += chunk.count
            guard length <= ShareUploadFile.byteLimit else { throw ShareUploadFailure.message("This file exceeds 100 MiB.") }
            try output.write(contentsOf: chunk)
          }
          finish(.success((target, source.lastPathComponent)))
        } catch { finish(.failure(error)) }
      }
      lock.lock()
      progress = loading
      let completed = ended
      lock.unlock()
      if completed { loading.cancel() }
    }
  }

  func cancel(_ error: Error = CancellationError()) {
    finish(.failure(error))
    lock.lock()
    let loading = progress
    lock.unlock()
    loading?.cancel()
  }

  private func checkPending() throws {
    lock.lock()
    defer { lock.unlock() }
    if ended { throw CancellationError() }
  }

  private func finish(_ result: Result<(url: URL, name: String), Error>) {
    lock.lock()
    guard !ended else { lock.unlock(); return }
    ended = true
    let pending = reply
    let timeout = deadline
    reply = nil
    lock.unlock()
    timeout?.cancel()
    pending?.resume(with: result)
  }
}
