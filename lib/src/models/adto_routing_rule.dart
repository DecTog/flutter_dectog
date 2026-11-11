/// One geo or language routing rule of a link. A tap from one of
/// [countries] (ISO 3166 alpha-2) and/or with one of [languages] (primary
/// browser language tags) takes the fields the rule sets instead of the
/// link's; the first matching rule wins, and a tap no rule matches is routed
/// as usual. Set them from the dashboard, the REST API or the MCP server.
///
/// A rule can also hold for a time ([startsAt] to [endsAt]: scheduled
/// routing) or for a share of visitors ([percent]: an A/B split, shares
/// stacking in rule order); its [name] is recorded on each click it routes.
class AdtoRoutingRule {
  final String? name;
  final List<String>? countries;
  final List<String>? languages;
  final int? percent;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? target;
  final String? redirectUrl;
  final String? fallbackUrl;
  final String? iosDeepLinkPath;
  final String? androidDeepLinkPath;

  const AdtoRoutingRule({
    this.name,
    this.countries,
    this.languages,
    this.percent,
    this.startsAt,
    this.endsAt,
    this.target,
    this.redirectUrl,
    this.fallbackUrl,
    this.iosDeepLinkPath,
    this.androidDeepLinkPath,
  });

  factory AdtoRoutingRule.fromJson(Map<String, dynamic> json) {
    List<String>? list(String key) =>
        (json[key] as List?)?.map((e) => e as String).toList();
    DateTime? time(String key) =>
        json[key] == null ? null : DateTime.tryParse(json[key] as String);
    return AdtoRoutingRule(
      name: json['name'] as String?,
      countries: list('countries'),
      languages: list('languages'),
      percent: (json['percent'] as num?)?.toInt(),
      startsAt: time('starts_at'),
      endsAt: time('ends_at'),
      target: json['target'] as String?,
      redirectUrl: json['redirect_url'] as String?,
      fallbackUrl: json['fallback_url'] as String?,
      iosDeepLinkPath: json['ios_deep_link_path'] as String?,
      androidDeepLinkPath: json['android_deep_link_path'] as String?,
    );
  }
}
