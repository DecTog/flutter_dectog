import 'package:example/app.dart';
import 'package:example/main.dart';
import 'package:example/trails.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('without a key the app says how to configure it', (
    tester,
  ) async {
    await tester.pumpWidget(TrailsRoot(app: TrailsApp()));
    await tester.pumpAndSettle();
    // The navigator observer reports the screen after 350 ms (and, with no
    // AdTo running, drops it).
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Welcome to Trails'), findsOneWidget);
    expect(find.textContaining('ADTO_API_KEY'), findsOneWidget);
    // Sign up waits for AdTo.
    final signUp = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(signUp.onPressed, isNull);
  });

  test('deep-link routes name trails', () {
    expect(trailForRoute('trails/2')?.name, 'Cedar Falls');
    expect(trailForRoute('/trails/4?from=share')?.name, 'Summit Ascent');
    expect(trailForRoute('trails/99'), isNull);
    expect(trailForRoute('settings'), isNull);
    expect(trailForRoute(null), isNull);
  });
}
