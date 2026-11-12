import 'adto_click_params.dart';
import 'adto_error.dart';
import 'adto_link_resolution.dart';

/// Represents a click on an AdTo link
class AdtoLinkClick {
  /// The original URL that was clicked
  final String originalUrl;

  /// The slug from the URL
  final String slug;

  /// The username from the URL
  final String username;

  /// When the link was received
  final DateTime receivedAt;

  /// Error that occurred while processing the link (if any)
  final AdtoError? error;

  /// Resolved link details (if resolution was successful)
  final AdtoLinkResolution? linkResolution;

  /// The link was tapped inside the app's own UI and passed to
  /// `FlutterAdto.handleUrl`, not opened by the system.
  final bool inApp;

  const AdtoLinkClick({
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

  /// The `adto_*` params on the opened URL; null when it has none.
  AdtoClickParams? get clickParams {
    final uri = Uri.tryParse(originalUrl);
    return uri == null ? null : AdtoClickParams.fromUri(uri);
  }

  @override
  String toString() {
    return 'AdtoLinkClick(originalUrl: $originalUrl, slug: $slug, username: $username, resolved: $isResolved, inApp: $inApp, receivedAt: $receivedAt, error: $error)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdtoLinkClick &&
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
