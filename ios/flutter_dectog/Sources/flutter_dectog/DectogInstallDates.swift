import Foundation

/// Where collect() keeps the two dates: the Keychain in the app, an
/// in-memory fake in ios/native_tests.
protocol DectogInstallStore {
  func read(_ account: String) -> DectogKeychain.ReadResult
  func add(_ account: String, _ value: String) -> Bool
  func upsert(_ account: String, _ value: String) -> Bool
}

struct DectogKeychainStore: DectogInstallStore {
  func read(_ account: String) -> DectogKeychain.ReadResult { DectogKeychain.read(account) }
  func add(_ account: String, _ value: String) -> Bool { DectogKeychain.add(account, value) }
  func upsert(_ account: String, _ value: String) -> Bool { DectogKeychain.upsert(account, value) }
}

/// The three paths whose creation dates date the install.
struct DectogInstallContainer {
  var executable: URL?
  var library: URL?
  var documents: URL?

  static var current: DectogInstallContainer {
    let fm = FileManager.default
    return DectogInstallContainer(
      executable: Bundle.main.executableURL,
      library: fm.urls(for: .libraryDirectory, in: .userDomainMask).first,
      documents: fm.urls(for: .documentDirectory, in: .userDomainMask).first)
  }
}

/**
 * Install / update / reinstall evidence, the Branch BNCApplication
 * recipe: three container timestamps plus two Keychain-held dates.
 *
 *  - executableCtime  creation date of the main executable — moves on every
 *                     App Store update (the bundle is replaced)
 *  - libraryCtime     creation date of the app's Library directory — the
 *                     container, created at install and kept across updates
 *  - documentsCtime   creation date of the Documents directory — same
 *                     lifetime as Library (package_info_plus reports this
 *                     one as installTime)
 *  - keychainFirstInstall   first time this app was ever installed on this
 *                     device (survives uninstall/reinstall; written once)
 *  - keychainLatestInstall  the latest container the SDK has seen; bumped
 *                     when the container is newer than the stored value by
 *                     more than 24 h (a new container = a reinstall)
 *
 * The SDK classifies from these (install / reinstall / update) and
 * sends first_install_ts. All values are epoch milliseconds. A locked
 * Keychain (before first unlock) yields the container dates only — nothing
 * is seeded, nothing is overwritten.
 */
enum DectogInstallDates {
  static let firstInstallAccount = "first_install_time"
  static let latestInstallAccount = "latest_install_time"

  /// 24 h buffer (Branch ServerRequestInitSession): an update that lands
  /// within a day of the container's creation is still the same install.
  private static let reinstallGapMs: Int64 = 24 * 60 * 60 * 1000

  static func collect(
    container paths: DectogInstallContainer = .current,
    store: DectogInstallStore = DectogKeychainStore()
  ) -> [String: Any] {
    var out: [String: Any] = [:]

    let executable = creationMs(paths.executable)
    let library = creationMs(paths.library)
    let documents = creationMs(paths.documents)
    if let v = executable { out["executableCtime"] = v }
    if let v = library { out["libraryCtime"] = v }
    if let v = documents { out["documentsCtime"] = v }

    // Keychain dates. Any locked read short-circuits: report what the
    // container says and leave the store untouched.
    let firstRead = store.read(firstInstallAccount)
    let latestRead = store.read(latestInstallAccount)
    if case .locked = firstRead { return out }
    if case .locked = latestRead { return out }

    var first = ms(firstRead)
    var latest = ms(latestRead)
    // Container creation: Library and Documents are created together at
    // install. Never the executable: it keeps the date its build was made,
    // which can be days before the install and would date a fresh install
    // as a reinstall (Branch dates the install by its Library directory too).
    let container = [library, documents].compactMap { $0 }.min()

    if first == nil {
      // First sight on this device: seed both dates from the container.
      if let seed = container {
        if store.add(firstInstallAccount, String(seed)) { first = seed }
        if store.add(latestInstallAccount, String(seed)) { latest = seed }
      }
    } else {
      if latest == nil, let f = first {
        // A first-install date without a latest one (older SDK state):
        // backfill rather than leave the reinstall check without a baseline.
        if store.add(latestInstallAccount, String(f)) { latest = f }
      }
      if let c = container, let l = latest, c > l + reinstallGapMs {
        // The container is newer than the last one we saw: reinstall. Never
        // touch first_install_time.
        if store.upsert(latestInstallAccount, String(c)) { latest = c }
      }
    }

    if let v = first { out["keychainFirstInstall"] = v }
    if let v = latest { out["keychainLatestInstall"] = v }
    return out
  }

  private static func ms(_ r: DectogKeychain.ReadResult) -> Int64? {
    if case .value(let s) = r, let n = Int64(s), n > 0 { return n }
    return nil
  }

  /// Creation date of a file/directory as epoch ms, nil when unreadable.
  private static func creationMs(_ url: URL?) -> Int64? {
    guard let url = url else { return nil }
    do {
      let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
      guard let date = attrs[.creationDate] as? Date else { return nil }
      let value = Int64((date.timeIntervalSince1970 * 1000).rounded())
      return value > 0 ? value : nil
    } catch {
      return nil
    }
  }
}
