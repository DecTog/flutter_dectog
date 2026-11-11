import 'dart:convert';

/// Represents errors that can occur in Flutter AdTo operations
class AdtoError implements Exception {
  /// Error message
  final String message;

  /// HTTP status code if this is an API error
  final int? statusCode;

  /// Error type for categorization
  final AdtoErrorType type;

  /// Additional error details: every field of the server's error object
  /// (e.g. `slug` on a 409), plus `retry_after_ms` when the server asked
  /// for a back-off.
  final Map<String, dynamic>? details;

  /// The server's machine-readable reason for an API error, e.g.
  /// `invalid_request`, `conflict`, `rate_limited`, `invalid_signature`.
  /// Null for network, configuration and link errors.
  final String? code;

  /// The server's request id for an API error. Quote it when reporting a
  /// problem: it finds the request in the server's logs.
  final String? requestId;

  const AdtoError({
    required this.message,
    this.statusCode,
    required this.type,
    this.details,
    this.code,
    this.requestId,
  });

  /// Create an API error from HTTP response
  factory AdtoError.apiError({
    required String message,
    required int statusCode,
    Map<String, dynamic>? details,
    String? code,
    String? requestId,
  }) {
    return AdtoError(
      message: message,
      statusCode: statusCode,
      type: AdtoErrorType.api,
      details: details,
      code: code,
      requestId: requestId,
    );
  }

  /// An API error from a non-success response. Reads the server's error
  /// envelope, `{"error": {"code", "message", "request_id", ...}}`; a body
  /// that is not one (a proxy's HTML page, an empty body) falls back to
  /// [fallbackMessage] and the `x-request-id` header.
  factory AdtoError.fromResponse({
    required int statusCode,
    required String body,
    required String fallbackMessage,
    String? headerRequestId,
    Map<String, dynamic> extraDetails = const {},
  }) {
    Map<String, dynamic>? error;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic> &&
          decoded['error'] is Map<String, dynamic>) {
        error = decoded['error'] as Map<String, dynamic>;
      }
    } catch (_) {}
    final message = error?['message'];
    final code = error?['code'];
    final requestId = error?['request_id'];
    return AdtoError.apiError(
      message: message is String ? message : fallbackMessage,
      statusCode: statusCode,
      code: code is String ? code : null,
      requestId: requestId is String ? requestId : headerRequestId,
      details: {...?error, ...extraDetails},
    );
  }

  /// Create a network error
  factory AdtoError.networkError(String message) {
    return AdtoError(message: message, type: AdtoErrorType.network);
  }

  /// Create a configuration error
  factory AdtoError.configError(String message) {
    return AdtoError(message: message, type: AdtoErrorType.configuration);
  }

  /// Create a link resolution error
  factory AdtoError.linkError(String message) {
    return AdtoError(message: message, type: AdtoErrorType.linkResolution);
  }

  @override
  String toString() {
    final buffer = StringBuffer('AdtoError: $message');
    if (statusCode != null) {
      buffer.write(' (Status: $statusCode');
      if (code != null) buffer.write(', $code');
      buffer.write(')');
    }
    if (requestId != null) {
      buffer.write(' [request $requestId]');
    }
    if (details != null) {
      buffer.write(' Details: $details');
    }
    return buffer.toString();
  }
}

/// Types of errors that can occur
enum AdtoErrorType {
  /// API-related errors (HTTP errors, server errors)
  api,

  /// Network connectivity errors
  network,

  /// Configuration or initialization errors
  configuration,

  /// Link resolution errors
  linkResolution,

  /// Unknown errors
  unknown,
}
