import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_adto/flutter_adto.dart';

import 'app.dart';
import 'trails.dart';

/// Onboarding: who sent the user here, and the sign-up that names them.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.app});
  final TrailsApp app;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
        listenable: app, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final verdict = app.verdict;
    final route = verdict?.deepLink ?? verdict?.routing?.deepLink;
    final trail = trailForRoute(route);
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to Trails')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            app.invited
                ? 'A friend invited you.'
                : verdict?.matched == true
                    ? 'You came from a link.'
                    : 'Find a trail, share it, go.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (trail != null) ...[
            const SizedBox(height: 12),
            Text('It opens on ${trail.name} once you are in.'),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: app.status != 'ready'
                ? null
                : () async {
                    await app.signUp();
                    if (!context.mounted) return;
                    Navigator.of(context).pushReplacementNamed('trails');
                  },
            child: const Text('Sign up'),
          ),
          const SizedBox(height: 32),
          // iOS 16+: paste a copied invite link without the system alert;
          // renders nothing elsewhere.
          if (AdtoPasteButton.isSupported) ...[
            const Text('Copied an invite link? Paste it here:'),
            const SizedBox(height: 8),
            const AdtoPasteButton(),
          ],
          const SizedBox(height: 32),
          _Status(app: app),
        ],
      ),
    );
  }
}

class TrailsScreen extends StatelessWidget {
  const TrailsScreen({super.key, required this.app});
  final TrailsApp app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trails'),
        actions: [
          IconButton(
            tooltip: 'Invite friends',
            icon: const Icon(Icons.card_giftcard),
            onPressed: () => Navigator.of(context).pushNamed('invite'),
          ),
          IconButton(
            tooltip: 'Debug',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).pushNamed('debug'),
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final t in trails)
            ListTile(
              title: Text(t.name),
              subtitle: Text('${t.region} · ${t.km} km'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(
                context,
              ).pushNamed('trail', arguments: {'trail_id': t.id}),
            ),
          ListTile(
            leading: const Icon(Icons.workspace_premium_outlined),
            title: const Text('Go Pro'),
            onTap: () => Navigator.of(context).pushNamed('pro'),
          ),
        ],
      ),
    );
  }
}

class TrailScreen extends StatelessWidget {
  const TrailScreen({super.key, required this.app, required this.trail});
  final TrailsApp app;
  final Trail trail;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(trail.name)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('${trail.region} · ${trail.km} km'),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.share),
            label: const Text('Share this trail'),
            onPressed: () => _share(context),
          ),
          const SizedBox(height: 12),
          const Text(
            'The shared URL is your referral link with adto_deeplink: a friend who '
            'installs lands on this trail, and you are credited.',
          ),
        ],
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final link = await app.referralLink();
      // One referral link, any trail: adto_deeplink sets the route per share
      // and survives the trip through the store.
      final url = Uri.parse(link.url).replace(
        queryParameters: {'adto_deeplink': trail.route},
      );
      await Clipboard.setData(ClipboardData(text: url.toString()));
      await app.adto.trackEvent(
        'trail_shared',
        data: {'trail_id': trail.id},
      );
      messenger.showSnackBar(SnackBar(content: Text('Copied $url')));
    } on AdtoError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key, required this.app});
  final TrailsApp app;

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  AdtoLink? _link;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.app
        .referralLink()
        .then((l) => setState(() => _link = l))
        .catchError((Object e) => setState(() => _error = '$e'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite friends')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A friend who installs from your link and signs up earns you a '
              'free month. The server records the referral and fires the '
              'referral.converted webhook, where the reward is granted.',
            ),
            const SizedBox(height: 24),
            if (_link != null) ...[
              SelectableText(_link!.url),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _link!.url)),
              ),
            ] else if (_error != null)
              Text(_error!)
            else
              const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

class ProScreen extends StatelessWidget {
  const ProScreen({super.key, required this.app});
  final TrailsApp app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trails Pro')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Offline maps and elevation profiles, €4.99 a month.'),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                // A real app calls this after the store confirmed the
                // purchase, with the store's transaction id.
                await app.buyPro();
                if (!context.mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Subscribe (demo, no charge)'),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a developer wants to see: the verdict, the last link, consent, setup.
class DebugScreen extends StatelessWidget {
  const DebugScreen({super.key, required this.app});
  final TrailsApp app;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Debug')),
      body: ListenableBuilder(
        listenable: app,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Status(app: app),
            const Divider(),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () async {
                    final report = await app.adto.diagnostics();
                    app.note(
                      report.ok
                          ? 'Setup matches the dashboard'
                          : report.warnings.join('\n'),
                    );
                  },
                  child: const Text('Diagnostics'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final v = await app.adto.getAttributionData();
                    app.note('Attribution: ${v ?? 'none'}');
                  },
                  child: const Text('Attribution'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    final on = await app.adto.isEnabled();
                    await app.adto.setEnabled(!on);
                    app.note('Collection ${on ? 'off' : 'on'}');
                  },
                  child: const Text('Toggle consent'),
                ),
                OutlinedButton(
                  onPressed: () => app.adto.flush(),
                  child: const Text('Flush events'),
                ),
              ],
            ),
            const Divider(),
            for (final line in app.log)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  line,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.app});
  final TrailsApp app;

  @override
  Widget build(BuildContext context) {
    final text = switch (app.status) {
      'no-key' =>
        'No ADTO_API_KEY: run with --dart-define-from-file=env/dev.json.',
      'starting' => 'Starting AdTo…',
      'failed' => 'AdTo failed to start: ${app.error}',
      _ =>
        'AdTo ready · ${app.verdict == null ? 'no verdict yet' : app.verdict!.matched ? 'install credited to /${app.verdict!.slug}' : 'organic install'}',
    };
    return Text(text, style: Theme.of(context).textTheme.bodySmall);
  }
}
