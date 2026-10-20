import 'package:flutter/material.dart';
import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => DectogPasteButton.debugIsSupportedOverride = null);

  testWidgets('renders nothing where UIPasteControl does not exist', (
    tester,
  ) async {
    DectogPasteButton.debugIsSupportedOverride = () => false;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DectogPasteButton(),
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
    DectogPasteButton.debugIsSupportedOverride = () => true;
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DectogPasteButton(
          size: Size(220, 48),
          displayMode: DectogPasteDisplayMode.labelOnly,
          cornerStyle: DectogPasteCornerStyle.medium,
          backgroundColor: Color(0xFF112233),
        ),
      ),
    );
    final view = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(view.viewType, DectogPasteButton.viewType);
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
    expect(DectogPasteButton.isSupported, isFalse);
  });
}
