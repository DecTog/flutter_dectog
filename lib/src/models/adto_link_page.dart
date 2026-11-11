import 'adto_link.dart';

/// One page of `getLinks`, newest first: the server's
/// `{"data": [...], "next_cursor": ...}` list envelope.
class AdtoLinkPage {
  const AdtoLinkPage({required this.links, this.nextCursor});

  /// The links on this page.
  final List<AdtoLink> links;

  /// Pass to `getLinks(cursor: ...)` for the next page; null on the last one.
  final String? nextCursor;

  /// Whether another page follows.
  bool get hasMore => nextCursor != null;

  factory AdtoLinkPage.fromJson(Map<String, dynamic> json) => AdtoLinkPage(
    links:
        (json['data'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(AdtoLink.fromJson)
            .toList(),
    nextCursor: json['next_cursor'] as String?,
  );
}
