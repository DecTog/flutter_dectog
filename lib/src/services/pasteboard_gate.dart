/// What the SDK may do with the pasteboard.
///
/// Only a link that names a click (`dtg_click`) or a link (`dtg_l`) is a
/// signal the server can credit, so only such a link is sent; a bare share
/// link the user copied to paste into a chat is left alone. The pasteboard
/// is cleared only after the server credited the link (`matchSource ==
/// 'clipboard'`, or a claim answered `upgraded`), and only when its change
/// counter still equals the value seen when the link was read, so nothing
/// the user copied since is ever wiped (Grovs' ClipboardHandler rule).
///
/// The gate keeps no state: each read holds its own mark, so two reads in
/// flight (the first-launch read and the paste control, or two taps) never
/// clear against each other's. A read whose link was not credited just
/// drops its mark.
class PasteboardGate {
  PasteboardGate({required this.changeCount, required this.clear});

  /// The pasteboard's change counter (`UIPasteboard.changeCount`, the clip
  /// description timestamp on Android), or null when unavailable.
  final Future<int?> Function() changeCount;

  /// Empty the pasteboard.
  final Future<bool> Function() clear;

  static final RegExp _tag = RegExp(r'[?&](?:dtg_click|dtg_l)=[^&#\s]');

  /// Whether [url] carries `dtg_click=` or `dtg_l=` as a query parameter.
  static bool carriesClickTag(String url) => _tag.hasMatch(url);

  /// The mark of a read: the change counter right after a link was read
  /// from the pasteboard (null when unknown, which never clears).
  Future<int?> remember() async {
    try {
      return await changeCount();
    } catch (_) {
      return null;
    }
  }

  /// After the server credited the link read at [mark]: clear the
  /// pasteboard when nobody copied anything since. True when it was cleared.
  Future<bool> clearIfUnchanged(int? mark) async {
    if (mark == null) return false;
    try {
      final now = await changeCount();
      if (now == null || now != mark) return false;
      return await clear();
    } catch (_) {
      return false;
    }
  }
}
