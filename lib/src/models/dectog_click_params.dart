/// Per-click link overrides: the `dec_*` query params on a DecTog
/// short link, e.g.
/// `https://you.dectog.com/promo?dec_label=2323&dec_campaign=spring&dec_deeplink=myapp%3A%2F%2Fvoucher%3Fcode%3DX`.
///
/// After a deferred install the server returns them on the attribution
/// ([DectogAppInstallResponse.clickParams]); on a warm open they are read
/// straight from the opened URL ([DectogLinkClick.clickParams]).
class DectogClickParams {
  /// In-app route from `dec_deeplink`, in the same shape as a link's
  /// deep-link path (`voucher?code=X`, no scheme). On a warm open this is the
  /// raw `dec_deeplink` value as it appeared in the URL.
  final String? deepLink;

  /// `dec_label` — free-form value for your own reporting.
  final String? label;

  /// `dec_campaign`
  final String? campaign;

  /// `dec_adgroup`
  final String? adgroup;

  /// `dec_creative`
  final String? creative;

  /// `dec_tracker`
  final String? tracker;

  const DectogClickParams({
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
  factory DectogClickParams.fromJson(Map<String, dynamic> json) {
    String? s(String key) => json[key] is String ? json[key] as String : null;
    return DectogClickParams(
      deepLink: s('deep_link'),
      label: s('label'),
      campaign: s('campaign'),
      adgroup: s('adgroup'),
      creative: s('creative'),
      tracker: s('tracker'),
    );
  }

  /// The `dec_*` query params of an opened link; null when it has none.
  static DectogClickParams? fromUri(Uri uri) {
    String? q(String key) {
      final v = uri.queryParameters['dec_$key']?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final params = DectogClickParams(
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
      'DectogClickParams{deepLink: $deepLink, label: $label, campaign: $campaign, adgroup: $adgroup, creative: $creative, tracker: $tracker}';
}
