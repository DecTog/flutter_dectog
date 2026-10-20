/// Major iOS version from `Platform.operatingSystemVersion` ("Version 17.5
/// (Build 21F79)"); 0 when it cannot be parsed. Pure, for the pasteboard
/// gates (iOS 15+ reads, iOS 16+ system alert, iOS 16+ UIPasteControl).
int iosMajorVersion(String operatingSystemVersion) {
  final m = RegExp(
    r'(?:Version\s+)?(\d{1,3})(?:\.\d+)*',
  ).firstMatch(operatingSystemVersion.trim());
  if (m == null) return 0;
  return int.tryParse(m.group(1)!) ?? 0;
}
