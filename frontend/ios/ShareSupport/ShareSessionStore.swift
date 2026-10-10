import CryptoKit
import Foundation
import Security

struct ShareSessionContext: Codable, Equatable {
  let endpoint: String
  let credentialKey: String
  let tokenHash: String
  let userId: String
  let accountId: String
}

struct ShareSession {
  let context: ShareSessionContext
  let token: String

  func url(_ path: String) throws -> URL {
    guard let base = URLComponents(string: context.endpoint),
          ["http", "https"].contains(base.scheme), base.host != nil,
          base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
          let url = URL(string: context.endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
      throw ShareUploadFailure.message("Open Domabas and select your server again.")
    }
    return url
  }
}

enum ShareUploadFailure: Error {
  case message(String)
  var message: String {
    switch self { case .message(let value): return value }
  }
}

final class ShareSessionStore {
  private let accessGroup: String
  private let service = "domabas.share-context.v1"
  init(bundle: Bundle = .main) {
    accessGroup = bundle.object(forInfoDictionaryKey: "DomabasKeychainGroup") as? String ?? ""
  }

  func setContext(_ context: ShareSessionContext?) throws {
    if let context, let data = try read(service: service, account: "active"),
       (try? JSONDecoder().decode(ShareSessionContext.self, from: data)) == context { return }
    let query = query(service: service, account: "active")
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw unavailable() }
    guard let context else { return }
    var item = query
    item[kSecValueData as String] = try JSONEncoder().encode(context)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw unavailable() }
  }

  func session() throws -> ShareSession {
    guard let data = try read(service: service, account: "active"),
          let context = try? JSONDecoder().decode(ShareSessionContext.self, from: data),
          let credential = try read(service: "domabas.sessions.v1", account: context.credentialKey),
          let token = String(data: credential, encoding: .utf8),
          token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
          Self.hash(credential) == context.tokenHash else {
      throw ShareUploadFailure.message("Open Domabas, sign in and select a library with upload permission. Then share again.")
    }
    return ShareSession(context: context, token: token)
  }

  static func hash(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func query(service: String, account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: service, kSecAttrAccount as String: account,
     kSecAttrAccessGroup as String: accessGroup, kSecAttrSynchronizable as String: false]
  }

  private func read(service: String, account: String) throws -> Data? {
    var query = query(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var value: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &value)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = value as? Data else { throw unavailable() }
    return data
  }

  private func unavailable() -> ShareUploadFailure {
    .message("Unlock your device and open Domabas before sharing. If this continues, check the app's Keychain Sharing signing configuration.")
  }
}
