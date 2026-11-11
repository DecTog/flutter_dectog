/// Represents a temporary AdTo link with expiration
class AdtoTempLink {
  /// Server id
  final String id;

  /// Unique slug identifier for the temporary link
  final String slug;

  /// Fallback URL; null = inherits the app's fallback URL
  final String? target;

  /// Full clickable URL (e.g., https://username.adto.app/slug)
  final String url;

  /// When the link expires
  final DateTime expiresAt;

  /// When the link was created
  final DateTime createdAt;

  /// TTL in seconds from creation
  final int? ttlSeconds;

  /// Social preview overrides (null = the app's defaults)
  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;

  /// Lifecycle: where the link sends visitors once expired (null:
  /// a 410 page), paused since (and the owner's note), filed away, deleted.
  final String? expiredUrl;
  final DateTime? disabledAt;
  final String? disabledReason;
  final DateTime? archivedAt;
  final DateTime? deletedAt;

  const AdtoTempLink({
    required this.id,
    required this.slug,
    required this.target,
    required this.url,
    required this.expiresAt,
    required this.createdAt,
    this.ttlSeconds,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
    this.expiredUrl,
    this.disabledAt,
    this.disabledReason,
    this.archivedAt,
    this.deletedAt,
  });

  /// Create from JSON response
  factory AdtoTempLink.fromJson(Map<String, dynamic> json) {
    DateTime? t(String key) =>
        json[key] is String ? DateTime.parse(json[key] as String) : null;
    return AdtoTempLink(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String,
      target: json['target'] as String?,
      url: json['url'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      ttlSeconds: (json['ttl_seconds'] as num?)?.toInt(),
      ogTitle: json['og_title'] as String?,
      ogDescription: json['og_description'] as String?,
      ogImageUrl: json['og_image_url'] as String?,
      expiredUrl: json['expired_url'] as String?,
      disabledAt: t('disabled_at'),
      disabledReason: json['disabled_reason'] as String?,
      archivedAt: t('archived_at'),
      deletedAt: t('deleted_at'),
    );
  }

  /// Check if the link is expired
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Get remaining time until expiration
  Duration get timeUntilExpiration {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) {
      return Duration.zero;
    }
    return expiresAt.difference(now);
  }

  @override
  String toString() {
    return 'AdtoTempLink(slug: $slug, target: $target, url: $url, expires: $expiresAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdtoTempLink &&
        other.id == id &&
        other.slug == slug &&
        other.target == target &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(id, slug, target, url);
}
