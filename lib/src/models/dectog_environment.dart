/// Which of an account's two environments a key belongs to.
///
/// A test environment is a second account, `t-<username>`, with the same
/// apps and link templates (dashboard Settings → Test environment). Its SDK
/// keys go in debug builds: their installs, events and links stay out of the
/// live numbers, and its links live on `t-<username>.<root>`.
enum DectogEnvironment {
  /// The account itself: what release builds report to.
  live,

  /// The account's test environment.
  test,
}
