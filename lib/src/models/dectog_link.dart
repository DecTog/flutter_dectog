import 'dectog_routing_rule.dart';

/// Represents a permanent DecTog link
class DectogLink {
  /// Server id
  final String id;

  /// Unique slug identifier for the link
  final String slug;

  /// Fallback URL; null = inherits the app's fallback URL (or the branded
  /// QR page when that is unset too)
  final String? target;

  /// Full clickable URL (e.g., https://username.dectog.com/slug)
  final String url;

  /// App the link belongs to (null = the account's first app)
  final String? appId;

  /// Number of times this link has been clicked
  final int clickCount;

  /// When the link was created
  final DateTime createdAt;

  /// When the link was last updated
  final DateTime? updatedAt;

  /// Custom data, returned on attributed installs as `customParameters`
  final Map<String, dynamic>? metadata;

  /// Social preview overrides (null = the app's defaults)
  final String? ogTitle;
  final String? ogDescription;
  final String? ogImageUrl;

  /// In-app route per platform, e.g. `products/42?color=black`
  final String? iosDeepLinkPath;
  final String? androidDeepLinkPath;

  /// Mobile destination when the app isn't installed (null = app stores)
  final String? redirectUrl;

  /// Desktop destination (null = the app's fallback, then the QR page)
  final String? fallbackUrl;

  /// Tracking values stored on every click (a `dec_*` URL param overrides
  /// each one per click) and returned on attribution as `clickParams`.
  final String? label;
  final String? campaign;
  final String? adgroup;
  final String? creative;

  /// On a referral link, the customer it belongs to.
  final String? referrerCustomerId;

  /// This link's iOS tap-to-store page and mobile interstitial;
  /// null follows the app's setting.
  final bool? iosTapToStore;
  final bool? mobileInterstitial;

  /// Whether the link adds `dtg_click` to its web destinations, so
  /// `dectog.js` on that site credits its events to the tap; null is off
  /// (or the template's value).
  final bool? appendClickId;

  /// Geo and language routing rules, first match wins; null when
  /// the link has none.
  final List<DectogRoutingRule>? routingRules;

  /// The template whose defaults fill the fields this link leaves
  /// empty (the fields above are the link's own).
  final String? templateId;

  /// UTM values added to the link's web destinations, and to clicks
  /// whose URL carries none.
  final String? utmSource;
  final String? utmMedium;
  final String? utmCampaign;
  final String? utmTerm;
  final String? utmContent;

  /// Your own id for the link, unique in the account.
  final String? externalId;

  /// Lifecycle. When the link expires; past it taps go to
  /// [expiredUrl], or get a 410 page.
  final DateTime? expiresAt;
  final String? expiredUrl;

  /// Paused since: taps get a 410 page and nothing is recorded.
  /// [disabledReason] is the owner's note, never shown to visitors.
  final DateTime? disabledAt;
  final String? disabledReason;

  /// Filed away in the dashboard; the link keeps working.
  final DateTime? archivedAt;

  /// Deleted (listed only on request); its history stays.
  final DateTime? deletedAt;

  const DectogLink({
    required this.id,
    required this.slug,
    required this.target,
    required this.url,
    required this.clickCount,
    required this.createdAt,
    this.appId,
    this.updatedAt,
    this.metadata,
    this.ogTitle,
    this.ogDescription,
    this.ogImageUrl,
    this.iosDeepLinkPath,
    this.androidDeepLinkPath,
    this.redirectUrl,
    this.fallbackUrl,
    this.label,
    this.campaign,
    this.adgroup,
    this.creative,
    this.referrerCustomerId,
    this.iosTapToStore,
    this.mobileInterstitial,
    this.appendClickId,
    this.routingRules,
    this.templateId,
    this.utmSource,
    this.utmMedium,
    this.utmCampaign,
    this.utmTerm,
    this.utmContent,
    this.externalId,
    this.expiresAt,
    this.expiredUrl,
    this.disabledAt,
    this.disabledReason,
    this.archivedAt,
    this.deletedAt,
  });

  /// Create from JSON response
  factory DectogLink.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key] as String?;
    DateTime? t(String key) =>
        json[key] is String ? DateTime.parse(json[key] as String) : null;
    return DectogLink(
      id: json['id'] as String? ?? '',
      slug: json['slug'] as String,
      target: s('target'),
      url: json['url'] as String,
      appId: s('app_id'),
      clickCount: (json['click_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt:
          json['updated_at'] is String
              ? DateTime.parse(json['updated_at'] as String)
              : null,
      metadata: json['metadata'] as Map<String, dynamic>?,
      ogTitle: s('og_title'),
      ogDescription: s('og_description'),
      ogImageUrl: s('og_image_url'),
      iosDeepLinkPath: s('ios_deep_link_path'),
      androidDeepLinkPath: s('android_deep_link_path'),
      redirectUrl: s('redirect_url'),
      fallbackUrl: s('fallback_url'),
      label: s('label'),
      campaign: s('campaign'),
      adgroup: s('adgroup'),
      creative: s('creative'),
      referrerCustomerId: s('referrer_customer_id'),
      iosTapToStore: json['ios_tap_to_store'] as bool?,
      mobileInterstitial: json['mobile_interstitial'] as bool?,
      appendClickId: json['append_click_id'] as bool?,
      routingRules:
          (json['routing_rules'] as List?)
              ?.map(
                (r) => DectogRoutingRule.fromJson(r as Map<String, dynamic>),
              )
              .toList(),
      templateId: s('template_id'),
      utmSource: s('utm_source'),
      utmMedium: s('utm_medium'),
      utmCampaign: s('utm_campaign'),
      utmTerm: s('utm_term'),
      utmContent: s('utm_content'),
      externalId: s('external_id'),
      expiresAt: t('expires_at'),
      expiredUrl: s('expired_url'),
      disabledAt: t('disabled_at'),
      disabledReason: s('disabled_reason'),
      archivedAt: t('archived_at'),
      deletedAt: t('deleted_at'),
    );
  }

  @override
  String toString() {
    return 'DectogLink(slug: $slug, target: $target, url: $url, clicks: $clickCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DectogLink &&
        other.id == id &&
        other.slug == slug &&
        other.target == target &&
        other.url == url;
  }

  @override
  int get hashCode => Object.hash(id, slug, target, url);
}
