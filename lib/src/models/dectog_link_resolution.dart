import 'dart:io';

import 'dectog_link.dart';
import 'dectog_temp_link.dart';

/// Represents the resolution of a DecTog link (permanent or temporary)
class DectogLinkResolution {
  /// Unique identifier
  final String id;

  /// Link slug
  final String slug;

  /// Fallback URL; null = inherits the app's fallback URL
  final String? target;

  /// Full clickable URL
  final String url;

  /// Type of link: 'permanent' or 'temporary'
  final String type;

  /// When the link was created
  final DateTime createdAt;

  /// Click count (only available for permanent links)
  final int? clickCount;

  /// When the link expires (a temporary link always, a permanent one when
  /// it was given an expiry). Only a live link resolves: a paused or
  /// expired one throws [DectogError] with code `link_paused` or
  /// `link_expired`.
  final DateTime? expiresAt;

  /// TTL in seconds (only for temporary links)
  final int? ttlSeconds;

  /// Link metadata (only for permanent links)
  final Map<String, dynamic>? metadata;

  /// The link's in-app route per platform (permanent links only), e.g.
  /// `products/42` — route a warm open with [deepLinkPath].
  final String? iosDeepLinkPath;
  final String? androidDeepLinkPath;

  const DectogLinkResolution({
    required this.id,
    required this.slug,
    required this.target,
    required this.url,
    required this.type,
    required this.createdAt,
    this.clickCount,
    this.expiresAt,
    this.ttlSeconds,
    this.metadata,
    this.iosDeepLinkPath,
    this.androidDeepLinkPath,
  });

  /// Create from JSON response
  factory DectogLinkResolution.fromJson(Map<String, dynamic> json) {
    return DectogLinkResolution(
      id: json['id'] as String,
      slug: json['slug'] as String,
      target: json['target'] as String?,
      url: json['url'] as String,
      type: json['type'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      clickCount: (json['click_count'] as num?)?.toInt(),
      expiresAt:
          json['expires_at'] != null
              ? DateTime.parse(json['expires_at'] as String)
              : null,
      ttlSeconds: (json['ttl_seconds'] as num?)?.toInt(),
      metadata: json['metadata'] as Map<String, dynamic>?,
      iosDeepLinkPath: json['ios_deep_link_path'] as String?,
      androidDeepLinkPath: json['android_deep_link_path'] as String?,
    );
  }

  /// The deep-link path for the running platform: the iOS path on iOS,
  /// elsewhere the Android path, each falling back to the other.
  String? get deepLinkPath =>
      Platform.isIOS
          ? (iosDeepLinkPath ?? androidDeepLinkPath)
          : (androidDeepLinkPath ?? iosDeepLinkPath);

  /// Whether this is a permanent link
  bool get isPermanent => type == 'permanent';

  /// Whether this is a temporary link
  bool get isTemporary => type == 'temporary';

  /// Get remaining time until expiration (for temporary links)
  Duration? get timeUntilExpiration {
    if (expiresAt == null) return null;

    final now = DateTime.now();
    if (now.isAfter(expiresAt!)) {
      return Duration.zero;
    }
    return expiresAt!.difference(now);
  }

  /// Convert to DectogLink (for permanent links)
  DectogLink? toDectogLink() {
    if (!isPermanent) return null;

    return DectogLink(
      id: id,
      slug: slug,
      target: target,
      url: url,
      clickCount: clickCount ?? 0,
      createdAt: createdAt,
      metadata: metadata,
      iosDeepLinkPath: iosDeepLinkPath,
      androidDeepLinkPath: androidDeepLinkPath,
    );
  }

  /// Convert to DectogTempLink (for temporary links)
  DectogTempLink? toDectogTempLink() {
    if (!isTemporary || expiresAt == null) return null;

    return DectogTempLink(
      id: id,
      slug: slug,
      target: target,
      url: url,
      expiresAt: expiresAt!,
      createdAt: createdAt,
      ttlSeconds: ttlSeconds,
    );
  }

  @override
  String toString() {
    return 'DectogLinkResolution(slug: $slug, type: $type, target: $target)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DectogLinkResolution &&
        other.id == id &&
        other.slug == slug &&
        other.type == type;
  }

  @override
  int get hashCode => id.hashCode ^ slug.hashCode ^ type.hashCode;
}
