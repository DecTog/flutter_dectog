import 'dart:ui' show Brightness;

import 'package:flutter_adto/src/services/device_settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final dispatcher = binding.platformDispatcher;
  final service = DeviceSettingsService();

  setUp(() => service.overrideForTest(dispatcher));
  tearDown(() {
    dispatcher.clearAllTestValues();
    service.overrideForTest(null);
  });

  test('every iOS text size comes back as its body size in points', () {
    // The Flutter iOS engine reports each content-size category as its
    // body size / 17, extra small to the largest accessibility size.
    for (final points in [14, 15, 16, 17, 19, 21, 23, 28, 33, 40, 47, 53]) {
      dispatcher.textScaleFactorTestValue = points / 17;
      expect(service.read(isIOS: true).textSize, points);
    }
  });

  test('the text size is iOS only', () {
    dispatcher.textScaleFactorTestValue = 1.3;
    expect(service.read(isIOS: false).textSize, isNull);
  });

  test('dark mode follows the platform brightness', () {
    dispatcher.platformBrightnessTestValue = Brightness.dark;
    expect(service.read(isIOS: true).darkMode, isTrue);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    expect(service.read(isIOS: true).darkMode, isFalse);
  });

  test('high contrast follows the accessibility features on iOS', () {
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      highContrast: true,
    );
    expect(service.read(isIOS: true).highContrast, isTrue);
    dispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    expect(service.read(isIOS: true).highContrast, isFalse);
  });

  test('high contrast is iOS only', () {
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      highContrast: true,
    );
    expect(service.read(isIOS: false).highContrast, isNull);
  });

  test('reduce motion is either Reduce Motion or Remove animations', () {
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      reduceMotion: true,
    );
    expect(service.read(isIOS: true).reduceMotion, isTrue);
    dispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );
    expect(service.read(isIOS: false).reduceMotion, isTrue);
    dispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures();
    expect(service.read(isIOS: true).reduceMotion, isFalse);
  });

  test('a scale that cannot be read as a size is left out', () {
    dispatcher.textScaleFactorTestValue = double.nan;
    final settings = service.read(isIOS: true);
    expect(settings.textSize, isNull);
    expect(settings.darkMode, isNotNull);
  });
}
