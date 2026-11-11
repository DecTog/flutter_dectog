import 'adto_click_params.dart';

/// App install response model for AdTo
class AdtoAppInstallResponse {
  /// Whether the install was matched to a deferred click — attribution
  /// CREDIT, granted only at `guaranteed` / `high` [matchConfidence].
  final bool matched;

  /// Install type - 'organic' or 'non-organic'
  final String type;

  /// How the match was made: 'referrer' (deterministic), 'clipboard'
  /// (LinkMe-style deterministic) or 'fingerprint' (probabilistic);
  /// null for organic installs.
  final String? matchSource;

  /// Which deterministic referrer won: 'google_play' | 'huawei' | 'samsung'
  /// | 'xiaomi' | 'vivo' | 'meta' | null (only meaningful when matchSource
  /// is 'referrer').
  final String? referrerSource;

  /// Deterministic fraud-rule hits on this install, e.g.
  /// ['emulator', 'impossible_speed', 'stale_clipboard']. Empty when clean. With the app's
  /// strict fraud mode on, a non-empty list also means matched == false.
  final List<String> fraudFlags;

  /// The latest link that opened the already-installed app (re-engagement;
  /// only present on attribution re-pulls).
  final AdtoAppOpen? lastOpen;

  /// Username if matched
  final String? username;

  /// Slug if matched
  final String? slug;

  /// Server install id (stable handle for the stored verdict)
  final String? installId;

  /// When the attributed click happened, if matched
  final DateTime? clickedAt;

  /// Link details if matched and available
  final AdtoAppInstallLink? link;

  /// Metadata
  final Map<String, dynamic>? customParameters;

  /// The `dec_*` params on the attributed click: label, campaign,
  /// adgroup, creative, tracker and deep link. Null when organic or the
  /// clicked URL carried none.
  final AdtoClickParams? clickParams;

  /// In-app route from the clicked URL's `dec_deeplink`, e.g.
  /// `voucher?code=X` — route the user there after a deferred install.
  final String? deepLink;

  // ---- (contract v2) ----

  /// How sure the server is: 'guaranteed' (referrer / Meta / clipboard /
  /// deep-link claim), 'high', 'medium', 'low'; null when organic. Credit
  /// ([matched]) is only given at guaranteed/high; a tie between candidates
  /// yields 'low' and no credit (Branch's `+match_guaranteed`).
  final String? matchConfidence;

  /// The deferred-ROUTING candidate, delivered at ≥ 'medium' confidence even
  /// when [matched] is false (AppsFlyer separates the deferred deep link
  /// from attribution credit the same way). At high/guaranteed it mirrors
  /// the attribution. Null when nothing routable was found.
  final AdtoDeferredRoute? routing;

  /// True when this verdict was replayed for an `install_attempt_id` the
  /// server had already registered (the retried POST minted no second row).
  final bool replayed;

  /// Server-side reinstall detection (same tenant + device id seen before,
  /// or the client classified the install as a reinstall).
  final bool isReinstall;

  /// Client classification echoed back: 'install' | 'reinstall' | 'update'.
  final String? installState;

  /// Late-claim outcome (only on claim responses): 'upgraded' | 'unchanged'
  /// | 'rejected', with [claimReason] ('click_reuse', 'click_not_found',
  /// 'no_signal', 'already_deterministic', 'stale_click').
  final String? claim;
  final String? claimReason;

  /// Apple Search Ads attribution (server-resolved from the AdServices token
  /// the SDK sends with `AdtoCollection.appleSearchAdsToken`): null until a
  /// token was ever sent, then the status of the exchange with Apple and,
  /// once answered, the campaign record. Provenance only — it never changes
  /// [matched], which is about AdTo links.
  final AdtoAppleSearchAds? appleSearchAds;

  const AdtoAppInstallResponse({
    required this.matched,
    required this.type,
    this.matchSource,
    this.referrerSource,
    this.fraudFlags = const [],
    this.lastOpen,
    this.username,
    this.slug,
    this.installId,
    this.clickedAt,
    this.link,
    this.customParameters,
    this.clickParams,
    this.deepLink,
    this.matchConfidence,
    this.routing,
    this.replayed = false,
    this.isReinstall = false,
    this.installState,
    this.claim,
    this.claimReason,
    this.appleSearchAds,
  });

  /// Create from JSON response
  factory AdtoAppInstallResponse.fromJson(Map<String, dynamic> json) {
    return AdtoAppInstallResponse(
      matched: json['matched'] == true,
      type:
          json['type'] as String? ??
          (json['matched'] == true ? 'non-organic' : 'organic'),
      matchSource: json['match_source'] as String?,
      referrerSource: json['referrer_source'] as String?,
      fraudFlags:
          (json['fraud_flags'] as List<dynamic>? ?? const [])
              .whereType<String>()
              .toList(),
      lastOpen:
          json['last_open'] is Map<String, dynamic>
              ? AdtoAppOpen.fromJson(json['last_open'] as Map<String, dynamic>)
              : null,
      username: json['username'] as String?,
      slug: json['slug'] as String?,
      installId: json['install_id'] as String?,
      clickedAt:
          json['clicked_at'] is String
              ? DateTime.tryParse(json['clicked_at'] as String)
              : null,
      customParameters: json['custom_params'] as Map<String, dynamic>?,
      clickParams:
          json['click_params'] is Map<String, dynamic>
              ? AdtoClickParams.fromJson(
                json['click_params'] as Map<String, dynamic>,
              )
              : null,
      deepLink: json['deep_link'] as String?,
      link:
          json['link'] is Map<String, dynamic>
              ? AdtoAppInstallLink.fromJson(
                json['link'] as Map<String, dynamic>,
              )
              : null,
      matchConfidence: json['match_confidence'] as String?,
      routing:
          json['routing'] is Map<String, dynamic>
              ? AdtoDeferredRoute.fromJson(
                json['routing'] as Map<String, dynamic>,
              )
              : null,
      replayed: json['replayed'] == true,
      isReinstall: json['is_reinstall'] == true,
      installState: json['install_state'] as String?,
      claim: json['claim'] as String?,
      claimReason: json['claim_reason'] as String?,
      appleSearchAds:
          json['apple_search_ads'] is Map<String, dynamic>
              ? AdtoAppleSearchAds.fromJson(
                json['apple_search_ads'] as Map<String, dynamic>,
              )
              : null,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'matched': matched,
      'type': type,
      if (matchSource != null) 'match_source': matchSource,
      if (referrerSource != null) 'referrer_source': referrerSource,
      if (fraudFlags.isNotEmpty) 'fraud_flags': fraudFlags,
      if (lastOpen != null) 'last_open': lastOpen!.toJson(),
      if (username != null) 'username': username,
      if (slug != null) 'slug': slug,
      if (installId != null) 'install_id': installId,
      if (clickedAt != null) 'clicked_at': clickedAt!.toIso8601String(),
      if (link != null) 'link': link!.toJson(),
      if (customParameters != null) 'custom_params': customParameters,
      if (clickParams != null) 'click_params': clickParams!.toJson(),
      if (deepLink != null) 'deep_link': deepLink,
      if (matchConfidence != null) 'match_confidence': matchConfidence,
      if (routing != null) 'routing': routing!.toJson(),
      if (replayed) 'replayed': true,
      if (isReinstall) 'is_reinstall': true,
      if (installState != null) 'install_state': installState,
      if (claim != null) 'claim': claim,
      if (claimReason != null) 'claim_reason': claimReason,
      if (appleSearchAds != null) 'apple_search_ads': appleSearchAds!.toJson(),
    };
  }

  @override
  String toString() {
    // Every field, same shape as the onAppInstalled payload.
    return 'AdtoAppInstallResponse${toJson()}';
  }
}

/// The deferred-routing candidate on an install verdict: where to
/// send a new user, separate from attribution credit.
/// Apple Search Ads attribution for an install, resolved server-side from the
/// AdServices token. [status] is `pending` while the server still
/// retries Apple, then `resolved` (attributed — the campaign fields are set),
/// `no_attribution` (Apple found no record, or the ad group uses age/gender
/// targeting), `invalid`, `expired` (the token's 24 h TTL passed before Apple
/// answered). The ids match the Apple Ads campaign, ad group,
/// keyword and ad reports; names are not part of Apple's payload.
class AdtoAppleSearchAds {
  const AdtoAppleSearchAds({
    required this.status,
    this.attribution,
    this.resolvedAt,
    this.orgId,
    this.campaignId,
    this.adGroupId,
    this.keywordId,
    this.adId,
    this.conversionType,
    this.claimType,
    this.clickDate,
    this.impressionDate,
    this.countryOrRegion,
    this.supplyPlacement,
  });

  final String status;

  /// Apple's verdict once answered: true = attributed, false = no record.
  final bool? attribution;
  final DateTime? resolvedAt;
  final int? orgId;
  final int? campaignId;
  final int? adGroupId;
  final int? keywordId;
  final int? adId;

  /// `Download`, `Redownload` or `PreOrder`.
  final String? conversionType;

  /// `Click` (tap-through, 30-day window) or `Impression` (view-through, 24 h).
  final String? claimType;

  /// Apple's timestamps as sent (e.g. `2026-10-08T17:17Z`).
  final String? clickDate;
  final String? impressionDate;
  final String? countryOrRegion;
  final String? supplyPlacement;

  bool get isPending => status == 'pending';
  bool get isAttributed => attribution == true;

  factory AdtoAppleSearchAds.fromJson(Map<String, dynamic> json) {
    int? i(Object? v) =>
        v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    String? s(Object? v) => v is String && v.isNotEmpty ? v : null;
    return AdtoAppleSearchAds(
      status: json['status'] as String? ?? 'pending',
      attribution: json['attribution'] as bool?,
      resolvedAt:
          json['resolved_at'] is String
              ? DateTime.tryParse(json['resolved_at'] as String)
              : null,
      orgId: i(json['org_id']),
      campaignId: i(json['campaign_id']),
      adGroupId: i(json['ad_group_id']),
      keywordId: i(json['keyword_id']),
      adId: i(json['ad_id']),
      conversionType: s(json['conversion_type']),
      claimType: s(json['claim_type']),
      clickDate: s(json['click_date']),
      impressionDate: s(json['impression_date']),
      countryOrRegion: s(json['country_or_region']),
      supplyPlacement: s(json['supply_placement']),
    );
  }

  Map<String, dynamic> toJson() => {
    'status': status,
    'attribution': attribution,
    if (resolvedAt != null) 'resolved_at': resolvedAt!.toIso8601String(),
    if (orgId != null) 'org_id': orgId,
    if (campaignId != null) 'campaign_id': campaignId,
    if (adGroupId != null) 'ad_group_id': adGroupId,
    if (keywordId != null) 'keyword_id': keywordId,
    if (adId != null) 'ad_id': adId,
    if (conversionType != null) 'conversion_type': conversionType,
    if (claimType != null) 'claim_type': claimType,
    if (clickDate != null) 'click_date': clickDate,
    if (impressionDate != null) 'impression_date': impressionDate,
    if (countryOrRegion != null) 'country_or_region': countryOrRegion,
    if (supplyPlacement != null) 'supply_placement': supplyPlacement,
  };
}

class AdtoDeferredRoute {
  final String? username;
  final String? slug;

  /// `dec_deeplink` of the candidate click, e.g. `voucher?code=X`.
  final String? deepLink;
  final AdtoClickParams? clickParams;

  /// 'guaranteed' | 'high' | 'medium'
  final String? confidence;
  final DateTime? clickedAt;

  const AdtoDeferredRoute({
    this.username,
    this.slug,
    this.deepLink,
    this.clickParams,
    this.confidence,
    this.clickedAt,
  });

  factory AdtoDeferredRoute.fromJson(Map<String, dynamic> json) {
    return AdtoDeferredRoute(
      username: json['username'] as String?,
      slug: json['slug'] as String?,
      deepLink: json['deep_link'] as String?,
      clickParams:
          json['click_params'] is Map<String, dynamic>
              ? AdtoClickParams.fromJson(
                json['click_params'] as Map<String, dynamic>,
              )
              : null,
      confidence: json['confidence'] as String?,
      clickedAt:
          json['clicked_at'] is String
              ? DateTime.tryParse(json['clicked_at'] as String)
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    if (username != null) 'username': username,
    if (slug != null) 'slug': slug,
    if (deepLink != null) 'deep_link': deepLink,
    if (clickParams != null) 'click_params': clickParams!.toJson(),
    if (confidence != null) 'confidence': confidence,
    if (clickedAt != null) 'clicked_at': clickedAt!.toIso8601String(),
  };

  @override
  String toString() => 'AdtoDeferredRoute${toJson()}';
}

/// A link that re-opened the already-installed app (attribution re-pull).
class AdtoAppOpen {
  final String username;
  final String slug;
  final String? clickId;
  final DateTime openedAt;

  const AdtoAppOpen({
    required this.username,
    required this.slug,
    this.clickId,
    required this.openedAt,
  });

  factory AdtoAppOpen.fromJson(Map<String, dynamic> json) {
    return AdtoAppOpen(
      username: json['username'] as String,
      slug: json['slug'] as String,
      clickId: json['click_id'] as String?,
      openedAt:
          DateTime.tryParse(json['opened_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() => {
    'username': username,
    'slug': slug,
    if (clickId != null) 'click_id': clickId,
    'opened_at': openedAt.toIso8601String(),
  };
}

/// Link details in app install response
class AdtoAppInstallLink {
  /// Link slug
  final String slug;

  /// Target URL
  final String? target;

  /// Full clickable URL
  final String url;

  /// Creation timestamp
  final DateTime createdAt;

  /// Link metadata
  final Map<String, dynamic>? metadata;

  /// The customer who referred this install: the id passed to
  /// `createReferralLink` for a referral link (read from the link, so nothing
  /// in the tapped URL can change it), else the tap's `dec_referrer` URL
  /// parameter, else null. Use it for screens such as "Invited by …"; grant
  /// rewards from the `referral.converted` webhook.
  final String? referrerCustomerId;

  const AdtoAppInstallLink({
    required this.slug,
    required this.target,
    required this.url,
    required this.createdAt,
    this.metadata,
    this.referrerCustomerId,
  });

  /// Create from JSON
  factory AdtoAppInstallLink.fromJson(Map<String, dynamic> json) {
    return AdtoAppInstallLink(
      slug: json['slug'] as String,
      target: json['target'] as String?,
      url: json['url'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      metadata: json['metadata'] as Map<String, dynamic>?,
      referrerCustomerId: json['referrer_customer_id'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'slug': slug,
      'target': target,
      'url': url,
      'created_at': createdAt.toIso8601String(),
      if (metadata != null) 'metadata': metadata,
      'referrer_customer_id': referrerCustomerId,
    };
  }

  @override
  String toString() {
    return 'AdtoAppInstallLink{slug: $slug, target: $target, url: $url, createdAt: $createdAt, metadata: $metadata, referrerCustomerId: $referrerCustomerId }';
  }
}
