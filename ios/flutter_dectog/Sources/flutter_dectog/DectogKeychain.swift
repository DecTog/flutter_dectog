import Foundation
import Security

/**
 * Minimal Keychain string store shared by the device id and the install
 * dates. One generic-password item per account under the SDK's
 * service, this-device-only and readable after the first unlock — the same
 * accessibility Branch and Adjust use for their install-state items, so a
 * value survives reinstall but never migrates to another device via backup.
 *
 * Reads distinguish "absent" from "locked": before the first unlock after a
 * reboot the Keychain answers errSecInteractionNotAllowed, and callers must
 * then neither seed nor overwrite anything (a seed written over a locked
 * store would shadow the real value once it unlocks).
 */
enum DectogKeychain {
  static let service = "app.dectog.sdk"

  enum ReadResult {
    case value(String)
    case absent
    case locked
    case error(OSStatus)
  }

  private static func base(_ account: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read(_ account: String) -> ReadResult {
    var query = base(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      if let data = item as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty {
        return .value(s)
      }
      return .absent
    case errSecItemNotFound:
      return .absent
    case errSecInteractionNotAllowed:
      return .locked
    default:
      return .error(status)
    }
  }

  /// Insert-only: returns false when the item already exists (or the store
  /// is locked) so a racing writer never clobbers a stored value.
  @discardableResult
  static func add(_ account: String, _ value: String) -> Bool {
    var add = base(account)
    add[kSecValueData as String] = Data(value.utf8)
    add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
  }

  /// Update an existing item in place; falls back to add when absent.
  @discardableResult
  static func upsert(_ account: String, _ value: String) -> Bool {
    let update: [String: Any] = [kSecValueData as String: Data(value.utf8)]
    let status = SecItemUpdate(base(account) as CFDictionary, update as CFDictionary)
    if status == errSecSuccess { return true }
    if status == errSecItemNotFound { return add(account, value) }
    return false
  }
}
