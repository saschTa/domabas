import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ShareUploadFile {
  static let byteLimit = 100 * 1024 * 1024
  let url: URL
  let filename: String
  let mediaType: String
  let size: Int
  let hash: String
  var title: String {
    let stem = (filename as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
    return String((stem.isEmpty ? "Uploaded document" : stem).unicodeScalars.prefix(200))
  }

  static func prepare(_ source: URL, name: String, directory: URL) throws -> ShareUploadFile {
    let size = try source.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
    guard size.isRegularFile == true, let count = size.fileSize, count > 0, count <= byteLimit else {
      throw ShareUploadFailure.message("Files must be nonempty and no larger than 100 MiB.")
    }
    let input = try FileHandle(forReadingFrom: source)
    defer { try? input.close() }
    let prefix = try input.read(upToCount: 8) ?? Data()
    let mediaType: String
    let file: URL
    var filename = safeName(name)
    if prefix.starts(with: [37, 80, 68, 70, 45]) {
      mediaType = "application/pdf"
      file = source
    } else if prefix.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) {
      mediaType = "image/png"
      file = source
    } else if prefix.starts(with: [255, 216, 255]) {
      mediaType = "image/jpeg"
      file = source
    } else {
      mediaType = "image/jpeg"
      file = directory.appendingPathComponent("converted.jpg")
      filename = safeName((filename as NSString).deletingPathExtension + ".jpg")
      try convertImage(source, to: file)
    }
    let stream = try FileHandle(forReadingFrom: file)
    defer { try? stream.close() }
    var digest = SHA256()
    var length = 0
    while let chunk = try stream.read(upToCount: 64 * 1024), !chunk.isEmpty {
      length += chunk.count
      guard length <= byteLimit else { throw ShareUploadFailure.message("This file exceeds 100 MiB.") }
      digest.update(data: chunk)
    }
    guard length > 0 else { throw ShareUploadFailure.message("Empty files cannot be uploaded.") }
    return ShareUploadFile(url: file, filename: filename, mediaType: mediaType, size: length,
                           hash: digest.finalize().map { String(format: "%02x", $0) }.joined())
  }

  static func safeName(_ name: String) -> String {
    var value = ""
    for scalar in name.unicodeScalars {
      let n = scalar.value
      let part = n < 32 || (127...159).contains(n) || [34, 47, 92, 0xfffd].contains(n) ? "_" : String(scalar)
      if value.utf8.count + part.utf8.count > 255 { break }
      value += part
    }
    value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty || value == "." || value == ".." ? "document" : value
  }

  private static func convertImage(_ input: URL, to output: URL) throws {
    guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) == 1,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0, width <= 20000, height <= 20000, width * height <= 50_000_000,
          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 4096,
            kCGImageSourceShouldCacheImmediately: true,
          ] as CFDictionary),
          let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
      throw ShareUploadFailure.message("Share a PDF, PNG, JPEG or a single still image up to 50 megapixels.")
    }
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      throw ShareUploadFailure.message("This image could not be prepared for upload.")
    }
  }

  func multipart(in directory: URL, boundary: String) throws -> URL {
    let target = directory.appendingPathComponent("upload.multipart")
    guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
      throw ShareUploadFailure.message("There is not enough space to prepare the upload.")
    }
    let output = try FileHandle(forWritingTo: target)
    defer { try? output.close() }
    let metadata = try JSONSerialization.data(withJSONObject: ["title": title, "kind": "document"])
    try output.write(contentsOf: Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n".utf8))
    try output.write(contentsOf: metadata)
    try output.write(contentsOf: Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mediaType)\r\n\r\n".utf8))
    let input = try FileHandle(forReadingFrom: url)
    defer { try? input.close() }
    var copied = 0
    while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
      copied += chunk.count
      guard copied <= size else { throw ShareUploadFailure.message("The shared file changed during preparation.") }
      try output.write(contentsOf: chunk)
    }
    guard copied == size else { throw ShareUploadFailure.message("The shared file changed during preparation.") }
    try output.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    return target
  }

  func validateReceipt(_ data: Data, userId: String) -> Bool {
    guard let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = value["id"] as? String, UUID(uuidString: id) != nil,
          value["title"] as? String == title,
          let file = value["file"] as? [String: Any],
          file["originalFilename"] as? String == filename,
          file["mediaType"] as? String == mediaType,
          file["size"] as? Int == size, file["sha256"] as? String == hash,
          file["uploaderId"] as? String == userId else { return false }
    return true
  }
}
