import 'package:flutter/material.dart';
import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

/// AdtoNavigatorObserver reports page routes as screen views,
/// debounced, deduplicated, name only unless params are allowed.
void main() {
  late List<(String, Map<String, Object?>?)> seen;
  late GlobalKey<NavigatorState> nav;

  AdtoNavigatorObserver observer({
    Set<String> captureParams = const {},
    String? Function(Route<dynamic>)? nameOf,
  }) => AdtoNavigatorObserver(
    captureParams: captureParams,
    nameOf: nameOf,
    track: (name, {params}) async => seen.add((name, params)),
  );

  Route<void> page(String? name, {Object? arguments}) => MaterialPageRoute(
    settings: RouteSettings(name: name, arguments: arguments),
    builder: (_) => Text(name ?? 'unnamed'),
  );

  Future<void> pumpApp(WidgetTester tester, AdtoNavigatorObserver o) =>
      tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [o],
          onGenerateRoute: (settings) => page(settings.name),
          initialRoute: 'home',
        ),
      );

  setUp(() {
    seen = [];
    nav = GlobalKey<NavigatorState>();
  });

  testWidgets('reports the first screen and each push and pop', (tester) async {
    await pumpApp(tester, observer());
    await tester.pump(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home']);

    nav.currentState!.push(page('product'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    nav.currentState!.pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home', 'product', 'home']);
  });

  testWidgets('rapid transitions collapse into the screen that settles', (
    tester,
  ) async {
    await pumpApp(tester, observer());
    await tester.pump(const Duration(milliseconds: 400));
    nav.currentState!.push(page('a'));
    await tester.pump(const Duration(milliseconds: 100));
    nav.currentState!.push(page('b'));
    await tester.pump(const Duration(milliseconds: 100));
    nav.currentState!.push(page('c'));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home', 'c']);
  });

  testWidgets('dialogs are not screens, and the same screen is sent once', (
    tester,
  ) async {
    await pumpApp(tester, observer());
    await tester.pump(const Duration(milliseconds: 400));
    showDialog<void>(
      context: nav.currentContext!,
      builder: (_) => const Text('dialog'),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    nav.currentState!.pop();
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home']);
  });

  testWidgets('unnamed routes are skipped unless nameOf names them', (
    tester,
  ) async {
    await pumpApp(tester, observer());
    await tester.pump(const Duration(milliseconds: 400));
    nav.currentState!.push(page(null));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home']);

    seen.clear();
    nav = GlobalKey<NavigatorState>();
    await pumpApp(
      tester,
      observer(nameOf: (r) => r.settings.name ?? 'fallback'),
    );
    await tester.pump(const Duration(milliseconds: 400));
    nav.currentState!.push(page(null));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.map((s) => s.$1), ['home', 'fallback']);
  });

  testWidgets('arguments go only when allowed, primitives only', (
    tester,
  ) async {
    await pumpApp(tester, observer(captureParams: {'id', 'tags'}));
    await tester.pump(const Duration(milliseconds: 400));
    nav.currentState!.push(
      page(
        'product',
        arguments: {
          'id': 42,
          'email': 'a@b.c',
          'tags': ['x'],
        },
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(seen.last.$1, 'product');
    expect(seen.last.$2, {'id': 42});
    expect(seen.first.$2, isNull);
  });
}
