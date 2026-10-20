import 'package:flutter/material.dart';
import 'package:flutter_dectog/flutter_dectog.dart';

import 'app.dart';
import 'screens.dart';
import 'trails.dart';

/// Trails: a small app built on flutter_dectog. Install from a shared trail
/// or an invite, sign up, share a trail, go Pro; see README.md for the
/// flows and how to try each one.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final app = TrailsApp()..start();
  runApp(TrailsRoot(app: app));
}

class TrailsRoot extends StatefulWidget {
  const TrailsRoot({super.key, required this.app});
  final TrailsApp app;

  @override
  State<TrailsRoot> createState() => _TrailsRootState();
}

class _TrailsRootState extends State<TrailsRoot> {
  final _navigator = GlobalKey<NavigatorState>();
  // Each screen is reported as a screen view; route arguments only
  // when named here, and never personal data.
  final _screens = DectogNavigatorObserver(captureParams: {'trail_id'});

  @override
  void initState() {
    super.initState();
    widget.app.addListener(_followLinks);
  }

  @override
  void dispose() {
    widget.app.removeListener(_followLinks);
    super.dispose();
  }

  /// A link that opened the app (or credited the install) names a trail:
  /// show it, once the user is signed in.
  void _followLinks() {
    if (widget.app.userId == null) return;
    final trail = trailForRoute(widget.app.takePendingRoute());
    if (trail != null) {
      _navigator.currentState?.pushNamed(
        'trail',
        arguments: {'trail_id': trail.id},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    return MaterialApp(
      title: 'Trails',
      navigatorKey: _navigator,
      navigatorObservers: [_screens],
      theme:
          ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.green)),
      initialRoute: 'welcome',
      onGenerateRoute: (settings) {
        final page = switch (settings.name) {
          'trails' => TrailsScreen(app: app),
          'trail' => TrailScreen(
              app: app,
              trail: trails.firstWhere(
                (t) => t.id == (settings.arguments as Map?)?['trail_id'],
                orElse: () => trails.first,
              ),
            ),
          'invite' => InviteScreen(app: app),
          'pro' => ProScreen(app: app),
          'debug' => DebugScreen(app: app),
          _ => WelcomeScreen(app: app),
        };
        return MaterialPageRoute(settings: settings, builder: (_) => page);
      },
    );
  }
}
