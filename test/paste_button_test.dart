import 'package:flutter/material.dart';
import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AdtoPasteButton.debugIsSupportedOverride = null);

  testWidgets('renders nothing where UIPasteControl does not exist', (
    tester,
  ) async {
    AdtoPasteButton.debugIsSupportedOverride = () => false;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AdtoPasteButton(),
      ),
    );
    expect(find.byType(SizedBox), findsOneWidget);
    final box = tester.widget<SizedBox>(find.byType(SizedBox));
    expect(box.width, 0);
    expect(box.height, 0);
  });

  testWidgets('on iOS 16+ it hosts the native view with the creation params', (
    tester,
  ) async {
    AdtoPasteButton.debugIsSupportedOverride = () => true;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: AdtoPasteButton(
          size: Size(220, 48),
          displayMode: AdtoPasteDisplayMode.labelOnly,
          cornerStyle: AdtoPasteCornerStyle.medium,
          backgroundColor: Color(0xFF112233),
        ),
      ),
    );
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, AdtoPasteButton.viewType);
    expect(view.creationParams, {
      'displayMode': 'labelOnly',
      'cornerStyle': 'medium',
      'backgroundColor': 0xFF112233,
    });
    final box = tester.widget<SizedBox>(
      find.ancestor(
        of: find.byType(UiKitView),
        matching: find.byType(SizedBox),
      ),
    );
    expect(box.width, 220);
    expect(box.height, 48);
  });

  test('off-device the support check is false (test host is not iOS)', () {
    expect(AdtoPasteButton.isSupported, isFalse);
  });
}
