/// Per-click link overrides: the `adto_*` query params on an AdTo
/// short link, e.g.
/// `https://you.adto.app/promo?adto_label=2323&adto_campaign=spring&adto_deeplink=myapp%3A%2F%2Fvoucher%3Fcode%3DX`.
///
/// After a deferred install the server returns them on the attribution
/// ([AdtoAppInstallResponse.clickParams]); on a warm open they are read
/// straight from the opened URL ([AdtoLinkClick.clickParams]).
class AdtoClickParams {
  /// In-app route from `adto_deeplink`, in the same shape as a link's
  /// deep-link path (`voucher?code=X`, no scheme). On a warm open this is the
  /// raw `adto_deeplink` value as it appeared in the URL.
  final String? deepLink;

  /// `adto_label` — free-form value for your own reporting.
  final String? label;

  /// `adto_campaign`
  final String? campaign;

  /// `adto_adgroup`
  final String? adgroup;

  /// `adto_creative`
  final String? creative;

  /// `adto_tracker`
  final String? tracker;

  const AdtoClickParams({
    this.deepLink,
    this.label,
    this.campaign,
    this.adgroup,
    this.creative,
    this.tracker,
  });

  /// Whether no value is set at all.
  bool get isEmpty =>
      deepLink == null &&
      label == null &&
      campaign == null &&
      adgroup == null &&
      creative == null &&
      tracker == null;

  /// Server shape (`click_params` on the install/attribution response).
  factory AdtoClickParams.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return AdtoClickParams(
      deepLink: s('deep_link'),
      label: s('label'),
      campaign: s('campaign'),
      adgroup: s('adgroup'),
      creative: s('creative'),
      tracker: s('tracker'),
    );
  }

  /// The `adto_*` query params of an opened link; null when it has none.
  static AdtoClickParams? fromUri(Uri uri) {
    String? q(String key) {
      final v = uri.queryParameters['adto_$key']?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final params = AdtoClickParams(
      deepLink: q('deeplink'),
      label: q('label'),
      campaign: q('campaign'),
      adgroup: q('adgroup'),
      creative: q('creative'),
      tracker: q('tracker'),
    );
    return params.isEmpty ? null : params;
  }

  Map<String, dynamic> toJson() => {
    'deep_link': deepLink,
    'label': label,
    'campaign': campaign,
    'adgroup': adgroup,
    'creative': creative,
    'tracker': tracker,
  };

  @override
  String toString() =>
      'AdtoClickParams{deepLink: $deepLink, label: $label, campaign: $campaign, adgroup: $adgroup, creative: $creative, tracker: $tracker}';
}
