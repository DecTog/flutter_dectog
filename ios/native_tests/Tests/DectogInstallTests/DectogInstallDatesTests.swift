import XCTest

@testable import DectogInstall

/// DectogInstallDates against a temporary container and an in-memory
/// Keychain — first launch, update, reinstall, the 24 h buffer, a locked
/// Keychain and a lost write race.
final class DectogInstallDatesTests: XCTestCase {
  private let day: Int64 = 24 * 60 * 60 * 1000
  private var root: URL!

  /// The Keychain stand-in: a dictionary, a lock switch and a write log.
  final class FakeStore: DectogInstallStore {
    var values: [String: String] = [:]
    var locked = false
    var refuseAdds = false
    var writes: [String] = []

    func read(_ account: String) -> DectogKeychain.ReadResult {
      if locked { return .locked }
      return values[account].map { .value($0) } ?? .absent
    }

    func add(_ account: String, _ value: String) -> Bool {
      writes.append("add \(account)")
      guard !locked, !refuseAdds, values[account] == nil else { return false }
      values[account] = value
      return true
    }

    func upsert(_ account: String, _ value: String) -> Bool {
      writes.append("upsert \(account)")
      guard !locked else { return false }
      values[account] = value
      return true
    }
  }

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory.appendingPathComponent("dectog-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  /// A container whose three paths were created at the given epoch ms.
  private func container(executable: Int64?, library: Int64?, documents: Int64?) throws -> DectogInstallContainer {
    func make(_ name: String, _ ms: Int64?, directory: Bool) throws -> URL? {
      let url = root.appendingPathComponent(name)
      guard let ms = ms else { return url }  // never created: unreadable
      if directory {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      } else {
        FileManager.default.createFile(atPath: url.path, contents: Data("bin".utf8))
      }
      try FileManager.default.setAttributes(
        [.creationDate: Date(timeIntervalSince1970: TimeInterval(ms) / 1000)], ofItemAtPath: url.path)
      return url
    }
    return DectogInstallContainer(
      executable: try make("Runner", executable, directory: false),
      library: try make("Library", library, directory: true),
      documents: try make("Documents", documents, directory: true))
  }

  private let t0: Int64 = 1_760_000_000_000  // 2025-10-09, a whole millisecond

  func testFirstLaunchSeedsBothDatesFromTheEarliestContainerDate() throws {
    let store = FakeStore()
    let out = DectogInstallDates.collect(
      container: try container(executable: t0 + 5_000, library: t0, documents: t0 + 1_000), store: store)
    XCTAssertEqual(out["executableCtime"] as? Int64, t0 + 5_000)
    XCTAssertEqual(out["libraryCtime"] as? Int64, t0)
    XCTAssertEqual(out["documentsCtime"] as? Int64, t0 + 1_000)
    XCTAssertEqual(out["keychainFirstInstall"] as? Int64, t0)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
    XCTAssertEqual(store.values[DectogInstallDates.firstInstallAccount], String(t0))
    XCTAssertEqual(store.values[DectogInstallDates.latestInstallAccount], String(t0))
  }

  func testABuildMadeBeforeTheInstallDoesNotDateTheFirstInstall() throws {
    // The executable keeps the date the build was made, which can be days
    // before the install (an older build, or one copied in with its file
    // dates). Taken as the install date, it made a fresh install look like a
    // reinstall more than a day old.
    let store = FakeStore()
    let out = DectogInstallDates.collect(
      container: try container(executable: t0 - 3 * day, library: t0, documents: t0 + 1_000), store: store)
    XCTAssertEqual(out["executableCtime"] as? Int64, t0 - 3 * day)
    XCTAssertEqual(out["keychainFirstInstall"] as? Int64, t0)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
    XCTAssertEqual(store.values[DectogInstallDates.firstInstallAccount], String(t0))
  }

  func testAReinstalledOlderBuildMovesTheLatestDateToTheNewContainer() throws {
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: String(t0), DectogInstallDates.latestInstallAccount: String(t0)]
    let reinstalled = t0 + 5 * day
    let out = DectogInstallDates.collect(
      container: try container(executable: t0 + day, library: reinstalled, documents: reinstalled), store: store)
    XCTAssertEqual(out["keychainFirstInstall"] as? Int64, t0)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, reinstalled)
  }

  func testAnUpdateKeepsBothDates() throws {
    // An App Store update replaces the bundle (newer executable) but keeps
    // the container.
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: String(t0), DectogInstallDates.latestInstallAccount: String(t0)]
    let out = DectogInstallDates.collect(
      container: try container(executable: t0 + 10 * day, library: t0, documents: t0), store: store)
    XCTAssertEqual(out["keychainFirstInstall"] as? Int64, t0)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
    XCTAssertEqual(store.writes, [])
  }

  func testAReinstallMovesTheLatestDateOnly() throws {
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: String(t0), DectogInstallDates.latestInstallAccount: String(t0)]
    let reinstalled = t0 + 3 * day
    let out = DectogInstallDates.collect(
      container: try container(executable: reinstalled, library: reinstalled, documents: reinstalled), store: store)
    XCTAssertEqual(out["keychainFirstInstall"] as? Int64, t0)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, reinstalled)
    XCTAssertEqual(store.writes, ["upsert \(DectogInstallDates.latestInstallAccount)"])
  }

  func testANewContainerWithinADayIsTheSameInstall() throws {
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: String(t0), DectogInstallDates.latestInstallAccount: String(t0)]
    let soon = t0 + day - 1
    let out = DectogInstallDates.collect(container: try container(executable: soon, library: soon, documents: soon), store: store)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
    XCTAssertEqual(store.writes, [])
  }

  func testALatestDateIsBackfilledFromTheFirst() throws {
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: String(t0)]
    let out = DectogInstallDates.collect(container: try container(executable: t0, library: t0, documents: t0), store: store)
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
    XCTAssertEqual(store.values[DectogInstallDates.latestInstallAccount], String(t0))
  }

  func testALockedKeychainReportsTheContainerAndWritesNothing() throws {
    let store = FakeStore()
    store.locked = true
    let out = DectogInstallDates.collect(container: try container(executable: t0, library: t0, documents: t0), store: store)
    XCTAssertEqual(out["libraryCtime"] as? Int64, t0)
    XCTAssertNil(out["keychainFirstInstall"])
    XCTAssertNil(out["keychainLatestInstall"])
    XCTAssertEqual(store.writes, [])
  }

  func testAnUnreadableContainerSeedsNothing() throws {
    let store = FakeStore()
    let out = DectogInstallDates.collect(container: try container(executable: nil, library: nil, documents: nil), store: store)
    XCTAssertTrue(out.isEmpty, "\(out)")
    XCTAssertEqual(store.writes, [])
  }

  func testALostAddRaceReportsNoDate() throws {
    // Another writer got there first: add() refuses, so this launch does not
    // claim a value it did not store.
    let store = FakeStore()
    store.refuseAdds = true
    let out = DectogInstallDates.collect(container: try container(executable: t0, library: t0, documents: t0), store: store)
    XCTAssertNil(out["keychainFirstInstall"])
    XCTAssertNil(out["keychainLatestInstall"])
  }

  func testGarbageInTheKeychainIsTreatedAsAbsent() throws {
    let store = FakeStore()
    store.values = [DectogInstallDates.firstInstallAccount: "not-a-number"]
    let out = DectogInstallDates.collect(container: try container(executable: t0, library: t0, documents: t0), store: store)
    // A non-numeric first date reads as absent, and add() will not overwrite
    // the existing item, so no first date is reported.
    XCTAssertNil(out["keychainFirstInstall"])
    XCTAssertEqual(out["keychainLatestInstall"] as? Int64, t0)
  }
}
