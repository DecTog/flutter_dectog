/// The example's catalog: a few trails, addressed by the deep-link route
/// `trails/<id>` (a link's deep-link path, or `dec_deeplink=trails/<id>` on
/// a shared URL).
class Trail {
  const Trail(this.id, this.name, this.region, this.km);
  final int id;
  final String name;
  final String region;
  final double km;

  String get route => 'trails/$id';
}

const trails = [
  Trail(1, 'Ridge Loop', 'Highlands', 12.4),
  Trail(2, 'Cedar Falls', 'River valley', 6.1),
  Trail(3, 'Old Mill Path', 'Lowlands', 4.8),
  Trail(4, 'Summit Ascent', 'Highlands', 18.9),
  Trail(5, 'Coastal Cliffs', 'Coast', 9.3),
];

/// The trail a deep-link route names (`trails/3`, `/trails/3?x=1`), or null.
Trail? trailForRoute(String? route) {
  final m = RegExp(r'^/?trails/(\d+)').firstMatch(route ?? '');
  if (m == null) return null;
  final id = int.parse(m.group(1)!);
  for (final t in trails) {
    if (t.id == id) return t;
  }
  return null;
}
