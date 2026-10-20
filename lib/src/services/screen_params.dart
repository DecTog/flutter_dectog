/// Longest string a screen view's params keep.
const int maxScreenParamLength = 256;

/// Longest screen name the server stores (`event_name`).
const int maxScreenNameLength = 200;

/// The params a screen view may carry: strings, cut to
/// [maxScreenParamLength] characters, finite numbers and booleans. Anything
/// else (maps, lists, objects, null) is dropped, and with [allow] only those
/// keys are kept. Null when nothing is left.
Map<String, Object>? screenParams(
  Map<Object?, Object?>? params, {
  Set<String>? allow,
}) {
  if (params == null || params.isEmpty) return null;
  final out = <String, Object>{};
  params.forEach((key, value) {
    if (key is! String || (allow != null && !allow.contains(key))) return;
    if (value is String) {
      out[key] =
          value.length > maxScreenParamLength
              ? value.substring(0, maxScreenParamLength)
              : value;
    } else if (value is bool) {
      out[key] = value;
    } else if (value is num && value.isFinite) {
      out[key] = value;
    }
  });
  return out.isEmpty ? null : out;
}
