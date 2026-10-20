import 'dectog_link.dart';

/// One page of `getLinks`, newest first: the server's
/// `{"data": [...], "next_cursor": ...}` list envelope.
class DectogLinkPage {
  const DectogLinkPage({required this.links, this.nextCursor});

  /// The links on this page.
  final List<DectogLink> links;

  /// Pass to `getLinks(cursor: ...)` for the next page; null on the last one.
  final String? nextCursor;

  /// Whether another page follows.
  bool get hasMore => nextCursor != null;

  factory DectogLinkPage.fromJson(Map<String, dynamic> json) => DectogLinkPage(
    links:
        (json['data'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(DectogLink.fromJson)
            .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}
