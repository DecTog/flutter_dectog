/// Sensitive-URL filter for the deep-link open path.
///
/// A URL that opens the app is logged as a click (`POST /api/v1/clicks`)
/// and emitted to the app. OAuth / social-login callbacks must
/// never travel that way — Branch's BNCURLFilter skips `fb<app id>:`,
/// `li<id>:`, `pdk<id>:`, `twitterkit-…` and Google Sign-In's
/// `com.googleusercontent.apps.<id>-…` schemes plus anything carrying an
/// OAuth token; Adjust filters the Facebook/VK callback shapes. These URLs
/// are neither logged nor emitted on [FlutterDectog.onLinkClick].
library;

final List<RegExp> _sensitiveSchemePatterns = [
  RegExp(r'^fb\d+$', caseSensitive: false),
  RegExp(r'^li\d+$', caseSensitive: false),
  RegExp(r'^pdk\d+$', caseSensitive: false),
  RegExp(r'^twitterkit-', caseSensitive: false),
  RegExp(r'^com\.googleusercontent\.apps\.\d+-', caseSensitive: false),
  RegExp(r'oauth', caseSensitive: false),
];

const Set<String> _sensitiveQueryKeys = {
  'access_token',
  'id_token',
  'oauth_token',
};

/// True when [uri] looks like an auth callback rather than a link open.
bool isSensitiveUrl(Uri uri) {
  final scheme = uri.scheme;
  if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
    for (final p in _sensitiveSchemePatterns) {
      if (p.hasMatch(scheme)) return true;
    }
  }
  final keys = uri.queryParametersAll.keys.map((k) => k.toLowerCase());
  for (final k in keys) {
    if (_sensitiveQueryKeys.contains(k)) return true;
  }
  // Tokens can also ride the fragment (implicit OAuth flows).
  final fragment = uri.fragment;
  if (fragment.isNotEmpty) {
    for (final k in _sensitiveQueryKeys) {
      if (RegExp('(^|[&?])$k=').hasMatch(fragment)) return true;
    }
  }
  return false;
}
