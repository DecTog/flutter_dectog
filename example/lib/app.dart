import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_adto_adid/flutter_adto_adid.dart';

/// The example's link to AdTo: initialization, the link that opened the
/// app, the install verdict, the signed-up user and the pending route.
///
/// Configure with `flutter run --dart-define-from-file=env/dev.json`
/// (env/*.json is gitignored; see env/dev.json.example).
class TrailsApp extends ChangeNotifier {
  TrailsApp({FlutterAdto? adto}) : adto = adto ?? FlutterAdto();

  final FlutterAdto adto;

  static const String envApiKey = String.fromEnvironment('ADTO_API_KEY');
  static const String envBaseUrl = String.fromEnvironment('ADTO_BASE_URL');
  static const String envLinkRoot = String.fromEnvironment(
    'ADTO_LINK_ROOT_DOMAIN',
  );

  /// A local worker by default: the Android emulator reaches the host at 10.0.2.2.
  static String get baseUrl => envBaseUrl.isNotEmpty
      ? envBaseUrl
      : (!kIsWeb && Platform.isAndroid)
          ? 'http://10.0.2.2:8787'
          : 'http://localhost:8787';

  String status = envApiKey.isEmpty ? 'no-key' : 'starting';
  String? error;
  AdtoAppInstallResponse? verdict;
  AdtoLinkClick? lastClick;

  /// The signed-in user's id: random, never a name or an email (no personal
  /// data rides an event).
  String? userId;

  /// Where a link wants the user to go, taken once the app can navigate.
  String? pendingRoute;
  final List<String> log = [];

  final _subscriptions = <StreamSubscription<Object?>>[];

  void note(String line) {
    log.insert(0, line);
    if (log.length > 30) log.removeLast();
    notifyListeners();
  }

  Future<void> start({bool readAdId = false}) async {
    if (envApiKey.isEmpty) return;
    // Subscribe before initialize: the link that opened the app is
    // reported while it runs.
    _subscriptions.add(adto.onLinkClick.listen(_onLink));
    // Fires again when a late signal (a store referrer that answered after
    // the registration, a link pasted with AdtoPasteButton) upgrades it.
    _subscriptions.add(adto.onAppInstalled.listen(_onVerdict));
    try {
      // iOS: the ATT prompt runs before initialize so the install can carry
      // the IDFA; only when the user turned it on in Debug.
      if (readAdId) await AdtoAdId.requestTracking();
      await adto.initialize(
        AdtoConfig(
          apiKey: envApiKey,
          baseUrl: baseUrl,
          linkRootDomain: envLinkRoot.isEmpty ? null : envLinkRoot,
          enableDebugLogging: kDebugMode,
          advertisingIdProvider: readAdId ? AdtoAdId.provider : null,
        ),
      );
      status = 'ready';
    } on AdtoError catch (e) {
      status = 'failed';
      error = e.message;
    }
    notifyListeners();
  }

  void _onLink(AdtoLinkClick click) {
    lastClick = click;
    // adto_deeplink on the shared URL first, then the link's own route.
    final route = click.clickParams?.deepLink ??
        (!kIsWeb && Platform.isIOS
            ? click.linkResolution?.iosDeepLinkPath
            : click.linkResolution?.androidDeepLinkPath);
    note('Opened by /${click.slug}${route != null ? ' → $route' : ''}');
    if (route != null) pendingRoute = route;
    notifyListeners();
  }

  void _onVerdict(AdtoAppInstallResponse v) {
    verdict = v;
    if (v.matched) {
      note(
        'Install credited to /${v.slug} (${v.matchSource}, ${v.matchConfidence})',
      );
    } else if (v.routing != null) {
      note('Organic, routed to /${v.routing!.slug} (${v.routing!.confidence})');
    } else {
      note('Organic install');
    }
    final route = v.deepLink ?? v.routing?.deepLink;
    if (route != null && userId == null) pendingRoute = route;
    notifyListeners();
  }

  /// Whether the new user arrived through a referral link: the
  /// server names those `r-…` and labels them `referral`.
  bool get invited =>
      verdict?.matched == true &&
      ((verdict?.slug ?? '').startsWith('r-') ||
          verdict?.clickParams?.label == 'referral');

  /// Sign up: a random id, sent with identify. On a fresh install credited
  /// to a referral link the server records the referral and fires
  /// `referral.converted`.
  Future<void> signUp() async {
    final r = Random.secure();
    userId =
        'u_${List.generate(10, (_) => r.nextInt(36).toRadixString(36)).join()}';
    await adto.identify(customerId: userId!);
    note('Signed up as $userId');
  }

  /// The user's referral link, created on first use.
  Future<AdtoLink> referralLink() =>
      adto.createReferralLink(customerId: userId!);

  /// A purchase, counted once even if reported twice (transaction id + store).
  Future<void> buyPro() async {
    final id = 'pro-${DateTime.now().millisecondsSinceEpoch}';
    await adto.trackConversion(
      revenue: 4.99,
      currency: 'EUR',
      eventName: 'pro_monthly',
      productId: 'pro_monthly',
      transactionId: id,
      store: (!kIsWeb && Platform.isIOS) ? AdtoStore.appStore : AdtoStore.play,
      purchaseType: AdtoPurchaseType.subscription,
      metadata: {'plan': 'pro_monthly'},
    );
    note('Pro purchase sent ($id)');
  }

  String? takePendingRoute() {
    final r = pendingRoute;
    pendingRoute = null;
    return r;
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.cancel();
    }
    super.dispose();
  }
}
