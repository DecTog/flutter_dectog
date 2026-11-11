import '../../flutter_adto.dart';

/// Extension methods for [AdtoLinkClick]
extension AdtoLinkClickX on AdtoLinkClick {
  /// Get the query parameters from the original URL
  Map<String, String>? get queryParameters =>
      Uri.tryParse(originalUrl)?.queryParameters;

  /// Get a specific query parameter from the original URL
  String? queryParameter(String key) => queryParameters?[key];

  /// Get the path from the original URL
  String? get path => Uri.tryParse(originalUrl)?.path;

  /// Get the host from the original URL
  String? get host => Uri.tryParse(originalUrl)?.host;

  /// Get the scheme from the original URL
  String? get scheme => Uri.tryParse(originalUrl)?.scheme;

  /// Get the fragment from the original URL
  String? get fragment => Uri.tryParse(originalUrl)?.fragment;
}
