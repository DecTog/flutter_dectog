/// Decides whether an incoming link URL is a NEW open or a repeat delivery
///. Replaces the earlier 10 s window for the cold-start link.
///
/// Two repeat shapes exist:
///  - the cold-start URL: delivered by `getInitialLink` AND `uriLinkStream`
///    on Android, and returned by `getInitialLink()` for the whole process
///    (so a host app calling it on a later screen must not re-log the
///    click). Branch marks the intent `branch_used`, AppsFlyer sets
///    `af_consumed`: once per process, no window.
///  - an identical URL delivered twice within seconds by the two iOS entry
///    points (UIScene vs AppDelegate) or the Android double delivery: a
///    short window.
///
/// Pure (clock injectable) so the rules are unit-testable.
class LinkDeduper {
  LinkDeduper({this.window = const Duration(seconds: 10)});

  /// How long an identical stream delivery counts as the same open.
  final Duration window;

  final Set<String> _consumedInitial = <String>{};
  final Map<String, DateTime> _recent = <String, DateTime>{};

  /// Whether [key] (the URL) should be processed. [initial] marks the
  /// cold-start delivery (`getInitialLink`).
  bool shouldProcess(String key, {required bool initial, DateTime? now}) {
    final t = now ?? DateTime.now();
    _recent.removeWhere((_, seen) => t.difference(seen) > window);
    if (initial) {
      if (!_consumedInitial.add(key)) return false; // once per process
      _recent[key] = t;
      return true;
    }
    if (_recent.containsKey(key)) return false; // echo inside the window
    _recent[key] = t;
    return true;
  }

  /// Whether [key] was already consumed as the cold-start link.
  bool wasConsumedInitial(String key) => _consumedInitial.contains(key);
}
