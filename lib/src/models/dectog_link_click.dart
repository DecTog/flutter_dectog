import 'dectog_click_params.dart';
import 'dectog_error.dart';
import 'dectog_link_resolution.dart';

/// Represents a click on a DecTog link
class DectogLinkClick {
  /// The original URL that was clicked
  final String originalUrl;

  /// The slug from the URL
  final String slug;

  /// The username from the URL
  final String username;

  /// When the link was received
  final DateTime receivedAt;

  /// Error that occurred while processing the link (if any)
  final DectogError? error;

  /// Resolved link details (if resolution was successful)
  final DectogLinkResolution? linkResolution;

  /// The link was tapped inside the app's own UI and passed to
  /// `FlutterDectog.handleUrl`, not opened by the system.
  final bool inApp;

  const DectogLinkClick({
    required this.originalUrl,
    required this.slug,
    required this.username,
    required this.receivedAt,
    this.error,
    this.linkResolution,
    this.inApp = false,
  });

  /// Whether link resolution was successful
  bool get isResolved => linkResolution != null && error == null;

  /// Get the target URL if resolution was successful
  String? get targetUrl => linkResolution?.target;

  /// Get the link type if resolution was successful
  String? get linkType => linkResolution?.type;

  /// The `dec_*` params on the opened URL; null when it has none.
  DectogClickParams? get clickParams {
    final uri = Uri.tryParse(originalUrl);
    return uri == null ? null : DectogClickParams.fromUri(uri);
  }

  @override
  String toString() {
    return 'DectogLinkClick(originalUrl: $originalUrl, slug: $slug, username: $username, resolved: $isResolved, inApp: $inApp, receivedAt: $receivedAt, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DectogLinkClick &&
        other.originalUrl == originalUrl &&
        other.slug == slug &&
        other.username == username &&
        other.receivedAt == receivedAt &&
        other.error == error &&
        other.linkResolution == linkResolution;
  }

  @override
  int get hashCode {
    return originalUrl.hashCode ^
        slug.hashCode ^
        username.hashCode ^
        receivedAt.hashCode ^
        error.hashCode ^
        linkResolution.hashCode;
  }
}
