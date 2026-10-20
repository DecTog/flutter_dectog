import Foundation
import Security
import UIKit
#if canImport(AdServices)
import AdServices
#endif

/**
 * The device reads behind every DecTog SDK's iOS layer, free of any
 * framework: the Flutter plugin and the React Native module both call these
 * and only translate the results. Shared as source: the
 * React Native repository copies these files byte for byte.
 *
 *  - deviceId(persist:) — the IDFV (identifierForVendor). With `persist`
 *    the first IDFV seen is stored in the Keychain (this-device-only,
 *    after-first-unlock) and returned on every later read, so the id
 *    survives reinstall; without it the plain IDFV changes on reinstall. A
 *    locked Keychain (before first unlock) yields the plain IDFV and writes
 *    nothing. No IDFA: the core links neither AdSupport nor
 *    AppTrackingTransparency; the opt-in advertising-id packages read it.
 *  - excludeFromBackup(_:) — NSURLIsExcludedFromBackupKey on the SDK's state
 *    directory, so an iCloud restore never carries a "tracked" install
 *    sentinel onto a fresh install. Creates the directory when missing.
 *  - attributionToken(_:) — AdServices AAAttribution.attributionToken()
 *    (Apple Search Ads); nil on the simulator, on error, or without the
 *    framework. Runs off the main thread, completes on the main thread.
 *  - pasteboardHasUrl() — UIPasteboard.hasURLs, a metadata check that shows
 *    NO paste alert. readPasteboardUrl() — the URL (string fallback) only
 *    when hasURLs; THIS read shows the iOS 16+ paste alert. ≤ 2048 chars.
 *    pasteboardChangeCount() — so the SDK clears only what it read.
 *    clearPasteboard() — after a DecTog link was credited.
 *  - urlSchemes() — Info.plist CFBundleURLTypes, for diagnostics().
 *  - installDates() — see DectogInstallDates.swift.
 *
 * Carrier identity, the WebView UA and Meta's referrer have no iOS source;
 * the SDKs report nil for them.
 */
enum DectogDevice {
  private static let keychainAccount = "device_id"
  static let pasteboardMaxLength = 2048

  // MARK: - Device id

  static func deviceId(persist: Bool) -> String? {
    return persist ? persistedDeviceId() : currentIdfv()
  }

  private static func currentIdfv() -> String? {
    let idfv = UIDevice.current.identifierForVendor?.uuidString ?? ""
    return idfv.isEmpty ? nil : idfv
  }

  /// Keychain value if present, else the current IDFV (stored when the
  /// Keychain is writable). Never fails: any Keychain error degrades to
  /// the plain IDFV.
  private static func persistedDeviceId() -> String? {
    switch DectogKeychain.read(keychainAccount) {
    case .value(let stored):
      return stored
    case .absent:
      guard let idfv = currentIdfv() else { return nil }
      // Only seed when the item is genuinely absent; a locked Keychain
      // (errSecInteractionNotAllowed) must not overwrite a stored id later.
      DectogKeychain.add(keychainAccount, idfv)
      return idfv
    case .locked, .error:
      return currentIdfv()
    }
  }

  // MARK: - Install dates

  static func installDates() -> [String: Any] {
    return DectogInstallDates.collect()
  }

  // MARK: - Backup exclusion

  /// Mark [path] excluded from iCloud/iTunes backup. A missing path is
  /// created as a directory first (the SDK passes its state directory).
  static func excludeFromBackup(_ path: String?) -> Bool {
    guard let path = path, !path.isEmpty else { return false }
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if !fm.fileExists(atPath: path, isDirectory: &isDir) {
      do {
        try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
      } catch {
        return false
      }
    }
    var url = URL(fileURLWithPath: path)
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try url.setResourceValues(values)
      return true
    } catch {
      return false
    }
  }

  // MARK: - Apple Search Ads

  /// AdServices attribution token. Generating it can take a moment (Branch
  /// waits 0.5 s on a group; Adjust retries once after 5 s), so it runs on
  /// a background queue and completes on the main thread. The SDK applies
  /// its own timeout and retries on later launches until obtained.
  static func attributionToken(_ completion: @escaping (String?) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      var token: String? = nil
      #if canImport(AdServices)
      if #available(iOS 14.3, *) {
        #if !targetEnvironment(simulator)
        do {
          let value = try AAAttribution.attributionToken()
          token = value.isEmpty ? nil : value
        } catch {
          token = nil
        }
        #endif
      }
      #endif
      DispatchQueue.main.async { completion(token) }
    }
  }

  // MARK: - Pasteboard

  static func pasteboardHasUrl() -> Bool {
    return UIPasteboard.general.hasURLs
  }

  /// The pasteboard URL, only when the OS says one is there. The `.url`
  /// accessor is the Branch/Adjust read; `.string` covers a link copied as
  /// plain text. Either read is what triggers the iOS 16+ paste alert.
  static func readPasteboardUrl() -> String? {
    let pasteboard = UIPasteboard.general
    guard pasteboard.hasURLs else { return nil }
    let raw = pasteboard.url?.absoluteString ?? pasteboard.string ?? ""
    let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty || value.count > pasteboardMaxLength { return nil }
    return value
  }

  /// Metadata only, no paste alert.
  static func pasteboardChangeCount() -> Int {
    return UIPasteboard.general.changeCount
  }

  static func clearPasteboard() -> Bool {
    UIPasteboard.general.items = []
    return true
  }

  // MARK: - Diagnostics

  /// The schemes in Info.plist CFBundleURLTypes.
  static func urlSchemes() -> [String] {
    let types = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
    return types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
  }
}
