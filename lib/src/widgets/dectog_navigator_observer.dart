import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../flutter_dectog.dart' show FlutterDectog;
import '../services/screen_params.dart';

/// Reports each screen the app's [Navigator] shows as a screen view
/// (`FlutterDectog().trackScreenView`), for the dashboard's "Screens after
/// open" table.
///
/// Add it to `MaterialApp(navigatorObservers: [...])`, or to `GoRouter(
/// observers: [...])`. Only page routes count: dialogs, sheets and menus are
/// not screens. A route is named by [nameOf], else by its
/// `RouteSettings.name`; a route with neither is skipped. Rapid transitions
/// collapse into the screen that settles ([debounce], 350 ms), and the same
/// screen twice in a row is reported once.
///
/// By default only the name is sent. [captureParams] names the route
/// arguments that may go with it, when the arguments are a map: strings (cut
/// to 256 characters), numbers and booleans; everything else is dropped. Keep
/// personal data out of both.
class DectogNavigatorObserver extends NavigatorObserver {
  DectogNavigatorObserver({
    Set<String> captureParams = const {},
    this.nameOf,
    this.debounce = const Duration(milliseconds: 350),
    @visibleForTesting
    Future<void> Function(String name, {Map<String, Object?>? params})? track,
  }) : captureParams = Set.unmodifiable(captureParams),
       _track = track;

  /// Route argument keys whose values may be sent with the screen name.
  final Set<String> captureParams;

  /// The screen name of a route; null skips it. Defaults to
  /// `route.settings.name`.
  final String? Function(Route<dynamic> route)? nameOf;

  /// How long a screen must stay on top before it is reported.
  final Duration debounce;

  final Future<void> Function(String name, {Map<String, Object?>? params})?
  _track;

  Timer? _timer;
  Route<dynamic>? _pending;
  String? _last;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _schedule(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _schedule(previousRoute);

  void _schedule(Route<dynamic>? route) {
    if (route is! PageRoute) return;
    _pending = route;
    _timer?.cancel();
    _timer = Timer(debounce, _report);
  }

  void _report() {
    final route = _pending;
    _pending = null;
    if (route == null) return;
    final name = (nameOf?.call(route) ?? route.settings.name)?.trim();
    if (name == null || name.isEmpty || name == _last) return;
    _last = name;
    final arguments = route.settings.arguments;
    final params =
        captureParams.isEmpty || arguments is! Map
            ? null
            : screenParams(arguments, allow: captureParams);
    final track = _track ?? FlutterDectog().trackScreenView;
    // Before initialize() or after dispose() there is nowhere to send it.
    unawaited(
      Future<void>(() => track(name, params: params)).catchError((_) {}),
    );
  }
}
