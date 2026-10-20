import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rxdart/rxdart.dart';

import '../flutter_dectog.dart';
import 'services/device_hardware_service.dart';
import 'services/device_identity_service.dart';
import 'services/device_service.dart';
import 'services/device_settings_service.dart';
import 'services/event_queue_service.dart';
import 'services/identifier_channel.dart';
import 'services/install_classifier.dart';
import 'services/install_referrer_service.dart';
import 'services/install_state_store.dart';
import 'services/link_deduper.dart';
import 'services/link_filter.dart';
import 'services/network_service.dart';
import 'services/pasteboard_gate.dart';
import 'services/platform_version.dart';
import 'services/retry_policy.dart';
import 'services/screen_params.dart';
import 'services/sdk_signature.dart';
import 'services/sdk_config_store.dart';
import 'services/sdk_state_store.dart';
import 'version.dart';

/// Implementation of Flutter DecTog plugin
///
/// This class provides functionality similar to Firebase Dynamic Links
/// but uses your own DecTog backend. Dart throughout, with one native
/// touchpoint (the identifier channel): the install-referrer readers, the
/// backup-excluded storage location, package provenance, the pasteboard
/// and the launch intent — everything the install registration needs for
/// deterministic attribution.
final class FlutterDectogImpl implements FlutterDectog {
  static FlutterDectogImpl _instance = FlutterDectogImpl._internal();

  /// Singleton instance
  static FlutterDectogImpl get instance => _instance;

  /// Private constructor
  FlutterDectogImpl._internal({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  /// Tests: replace the singleton with a fresh SDK object (dispose() closes
  /// its streams for good) that sends every request through [httpClient].
  /// `FlutterDectog()` returns the new instance from then on.
  @visibleForTesting
  static FlutterDectogImpl resetForTest({http.Client? httpClient}) =>
      _instance = FlutterDectogImpl._internal(httpClient: httpClient);

  /// Tests run on the host: true stands in for iOS in the first-launch
  /// pasteboard read and the text size, so the harness can drive them.
  @visibleForTesting
  static bool? debugIsIOS;
  static bool get _isIOS => debugIsIOS ?? Platform.isIOS;

  /// App links instance for handling deep links
  final _appLinks = AppLinks();

  /// Configuration
  DectogConfig? _config;

  /// Stream controller for link clicks
  final _linkClickController = StreamController<DectogLinkClick>.broadcast();

  /// BehaviorSubject for app install events - automatically handles late subscribers
  final _appInstallSubject = BehaviorSubject<DectogAppInstallResponse>();

  /// HTTP client
  final http.Client _httpClient;

  /// Device service for collecting device information
  final _deviceService = DeviceService();

  /// Device data tier, entirely behind DectogCollection.deviceTier
  /// (DectogConfig.collect): first-party identifier, hardware,
  /// network/carrier, display and accessibility settings. All best-effort;
  /// nothing here blocks attribution.
  final _deviceIdentityService = DeviceIdentityService();
  final _deviceHardwareService = DeviceHardwareService();
  final _deviceSettingsService = DeviceSettingsService();
  final _networkService = NetworkService();
  final _identifierChannel = IdentifierChannel();
  final _sdkConfig = SdkConfigStore();

  /// The OEM store referrers: DectogConfig.collect, else the
  /// dashboard, else on.
  bool _oemStoreReferrers(DectogConfig config) =>
      config.oemReferrersSetting ??
      _sdkConfig.config?.oemStoreReferrers ??
      true;

  /// The first-launch pasteboard read: DectogConfig.collect, else the
  /// dashboard, else the platform default.
  bool _readClipboard(DectogConfig config) => DectogConfig.resolveReadClipboard(
    config.pasteboardSetting ?? _sdkConfig.config?.readClipboardOnInstall,
    isIOS: _isIOS,
  );

  /// The advertising id from the host's provider, or null. A limited
  /// id is never sent; only the limited flag is.
  Future<DectogAdvertisingId?> _readAdvertisingId(DectogConfig config) async {
    final provider = config.advertisingIdProvider;
    if (provider == null || !config.collectsAdId) return null;
    return _guard(provider);
  }

  /// One random id per process, stamped on every event.
  final String _sessionId = uuidV4();
  late final _pasteboard = PasteboardGate(
    changeCount: _identifierChannel.pasteboardChangeCount,
    clear: _identifierChannel.clearPasteboard,
  );

  /// install sentinel v2, the multi-store referrer reader and the
  /// link-open deduper.
  final _installState = InstallStateStore();
  final _installReferrerService = InstallReferrerService();
  final _linkDeduper = LinkDeduper();

  /// Hardware info from the install flow, reused by later click logging.
  DeviceHardwareInfo? _cachedHardware;

  bool _initialized = false;
  StreamSubscription<Uri>? _linkSubscription;
  StreamSubscription<String>? _pasteControlSubscription;

  /// In-flight or completed initialize() call. Assigned before the first
  /// await so concurrent initialize() calls share one initialization.
  Future<void>? _initFuture;

  /// In-flight or completed install tracking. Assigned before the first
  /// await so the install POST cannot be issued twice in one process.
  Future<void>? _installTrackingFuture;

  /// Post-install telemetry: durable event queue + persisted SDK
  /// state (customer id / opt-out). Events batch to POST /api/v1/events.
  final _eventQueue = EventQueueService();
  final _sdkState = SdkStateStore();

  /// Anchors stamped onto event batches: the install verdict's id and the
  /// device id (with the device tier). Cached from the install flow.
  String? _lastInstallId;
  String? _lastDeviceId;

  /// The install was registered by THIS process (so in-process late signals
  /// — a referrer or pasteboard value that arrived after the POST — are
  /// delivered by their own futures, not by the launch-time re-read).
  bool _registeredThisProcess = false;

  /// A paste-control link (with its read's mark) that arrived before the
  /// install id existed.
  _PastedLink? _pendingPaste;

  /// Android: the launch came from recents (stale intent data) and the
  /// intent's referrer package.
  bool _launchedFromHistory = false;

  /// Product User-Agent for SDK API calls: "DectogSDK/<version> (android)".
  /// A bare platform name was sent before; the product token makes SDK
  /// traffic identifiable server-side without fingerprinting headers.
  String get _sdkUserAgent =>
      'DectogSDK/$packageVersion (${Platform.operatingSystem})';

  /// Ceiling for SDK telemetry calls: attribution must never hang
  /// the host app on a dead connection.
  static const Duration _httpTimeout = Duration(seconds: 30);

  /// Budgets. Auxiliary reads (device id, hardware, network, WebView
  /// UA, Meta IPC, launch info, install dates) each get 1.5 s and run
  /// concurrently (Branch waits 0.5 s for third-party signals, Adjust caps
  /// the OEM readers at 2–3 s); the AdServices token 0.5 s (Branch's
  /// dispatch_group_wait); the pasteboard read longer because on iOS 16+ it
  /// blocks on the system alert the user has to answer anyway.
  static const Duration _auxTimeout = Duration(milliseconds: 1500);
  static const Duration _asaTimeout = Duration(milliseconds: 500);
  static const Duration _pasteboardTimeout = Duration(seconds: 6);

  /// Install POST: two in-process attempts, 15 s each (Branch 5.5 s × 3,
  /// Adjust 60 s with a persisted queue); a Retry-After longer than this
  /// defers to the next launch instead of blocking initialize().
  static const Duration _installPostTimeout = Duration(seconds: 15);
  static const int _installPostAttempts = 2;
  static const Duration _maxInProcessRetryAfter = Duration(seconds: 10);

  /// Auth + signature headers for any authenticated /api/v1 call.
  /// GETs sign the empty body; POST/PUT bodies must be the exact string
  /// signed here — build the body first, then the headers.
  Map<String, String> _authHeaders(String rawBody, {bool jsonBody = true}) => {
    if (jsonBody) 'Content-Type': 'application/json',
    'Authorization': 'Bearer ${_config!.apiKey}',
    // The SDK build, stored on installs, events and clicks so the operator
    // sees which versions are still in the wild.
    'x-dectog-sdk': sdkIdentity,
    ...sdkSignatureHeaders(_config!.apiKey, rawBody),
  };

  void _log(String message) {
    if (_config?.enableDebugLogging == true) {
      // ignore: avoid_print
      print(message);
    }
  }

  /// One best-effort read with a deadline: null on timeout or any error.
  Future<T?> _guard<T>(
    Future<T?> Function() read, {
    Duration timeout = _auxTimeout,
  }) async {
    try {
      return await read().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  @override
  /// Initialize the plugin with configuration
  Future<void> initialize(DectogConfig config) async {
    if (_initialized) {
      throw DectogError.configError('FlutterDectog is already initialized');
    }

    // A failed initialization (including fast synchronous config errors —
    // the reset inside _doInitialize's catch loses the race with the ??=
    // assignment) must leave _initFuture null so a corrected config can
    // retry without an app restart.
    if (_initFuture == null) {
      _initFuture = _doInitialize(config).then(
        (value) {},
        onError: (Object error) {
          _initFuture = null;
          throw error;
        },
      );
    }
    return _initFuture;
  }

  Future<void> _doInitialize(DectogConfig config) async {
    _config = config;

    try {
      // Persisted customer id / opt-out / install id must be in memory
      // before anything reads them (app-open reports, events, telemetry).
      await _sdkState.load();
      // Until the app chooses with setEnabled, the config decides.
      _sdkState.defaultEnabled = config.enabled;

      // Initialized before the app links are set up: the cold-start link is
      // handled inside _setupAppLinks and must not be rejected as "not
      // initialized" (and must be able to log its click).
      _initialized = true;

      // The app's settings from the dashboard (Facebook App ID, OEM
      // referrers, the pasteboard read) before the install registration
      // reads them. A fresh cache costs nothing; without one the first
      // launch waits at most 1.5 s; a stale one is refreshed in the
      // background.
      await _loadSdkConfig();

      // Post-install telemetry: resume the event queue (unless opted out)
      // and fire the DAU/retention device ping.
      await _startTelemetry();

      // URLs the native UIPasteControl hands us (iOS 16+).
      _pasteControlSubscription ??= _identifierChannel.onPasteControlUrl.listen(
        _onPasteControlUrl,
      );

      // The cold-start link and the install registration run CONCURRENTLY:
      // the install POST used to wait behind getInitialLink + a 30 s
      // resolve. Branch puts the install request at the head of
      // its queue; nothing may delay it.
      await Future.wait([_setupAppLinks(), _trackAppInstallIfNeeded()]);

      // Later launches: re-read a referrer that was not definitive, fetch
      // the AdServices token that was not ready — background, never awaited.
      unawaited(_maybeLateClaim());

      _log('FlutterDectog v$packageVersion initialized successfully');
    } catch (e) {
      // Allow the caller to retry a failed initialize()
      _initialized = false;
      _initFuture = null;
      throw DectogError.configError('Failed to initialize: $e');
    }
  }

  // ============================================================
  // Deep links
  // ============================================================

  /// Set up app links for handling deep links
  Future<void> _setupAppLinks() async {
    // Listen to incoming links when app is already running
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) => _handleIncomingLink(uri, initial: false),
      onError: (error) {
        final linkClick = DectogLinkClick(
          originalUrl: 'unknown',
          slug: 'unknown',
          username: 'unknown',
          error: DectogError.linkError('Failed to process link: $error'),
          receivedAt: DateTime.now(),
        );
        _linkClickController.add(linkClick);
      },
    );

    // Handle initial link if app was opened via a link
    try {
      if (Platform.isAndroid) {
        // Branch's FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY guard: a task
        // re-launched from recents replays the original intent (and its
        // link) — not a new open, so neither logged nor emitted.
        final launch = await _guard(() => _identifierChannel.getLaunchInfo());
        _launchedFromHistory = launch?.fromHistory ?? false;
      }
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        if (_launchedFromHistory) {
          // Consume it so a later getInitialLink() call cannot replay it.
          _linkDeduper.shouldProcess(initialUri.toString(), initial: true);
          _log('Initial link ignored: launched from history');
          return;
        }
        await _handleIncomingLink(initialUri, initial: true);
      }
    } catch (e) {
      _log('No initial link found: $e');
    }
  }

  @override
  Future<DectogLinkClick?> handleUrl(String url) async {
    _ensureInitialized();
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    if (isSensitiveUrl(uri)) {
      _log('handleUrl: ignoring a sensitive URL (auth callback)');
      return null;
    }
    if (_parseDectogUrl(uri) == null) return null;
    final (processing, duplicate) = _processOnce(
      uri,
      initial: false,
      inApp: true,
    );
    final click = await processing;
    if (!duplicate) _linkClickController.add(click);
    return click;
  }

  /// Handle incoming link
  Future<void> _handleIncomingLink(Uri uri, {required bool initial}) async {
    if (!_initialized || _config == null) {
      _linkClickController.add(
        DectogLinkClick(
          originalUrl: uri.toString(),
          slug: 'unknown',
          username: 'unknown',
          error: DectogError.configError('Plugin not initialized'),
          receivedAt: DateTime.now(),
        ),
      );
      return;
    }

    // OAuth / social-login callbacks are never clicks (Branch's URL filter,
    // Adjust's FB/VK callback regexes): not logged, not emitted.
    if (isSensitiveUrl(uri)) {
      _log('Ignoring sensitive URL (auth callback): ${uri.scheme}');
      return;
    }

    try {
      final (linkClick, duplicate) = _processOnce(uri, initial: initial);
      final click = await linkClick;
      if (!duplicate) _linkClickController.add(click);
    } catch (e) {
      _linkClickController.add(
        DectogLinkClick(
          originalUrl: uri.toString(),
          slug: 'unknown',
          username: 'unknown',
          error: DectogError.linkError('Failed to process link: $e'),
          receivedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Results of the links processed in this process, so a repeat delivery
  /// (the cold-start URL on both entry points, a host app calling
  /// [getInitialLink] later) resolves to the same click object.
  final Map<String, Future<DectogLinkClick>> _linkResults = {};
  static const int _maxLinkResults = 50;

  /// The processing of [uri], and whether it was already underway. Cold
  /// starts deliver the same link on both getInitialLink and uriLinkStream
  /// (and again whenever the host app calls [getInitialLink]): the deduper
  /// consumes the cold-start URL once per process and folds echoes inside
  /// a short window (LinkDeduper), so the click and the open are
  /// logged once and [onLinkClick] emits once.
  (Future<DectogLinkClick>, bool) _processOnce(
    Uri uri, {
    required bool initial,
    bool inApp = false,
  }) {
    final key = uri.toString();
    if (!_linkDeduper.shouldProcess(key, initial: initial)) {
      final seen = _linkResults[key];
      if (seen != null) return (seen, true);
      // Consumed earlier but evicted from the result cache — still a repeat.
      final parsed = _parseDectogUrl(uri);
      return (
        Future.value(
          DectogLinkClick(
            originalUrl: key,
            slug: parsed?['slug'] ?? 'unknown',
            username: parsed?['username'] ?? 'unknown',
            receivedAt: DateTime.now(),
            inApp: inApp,
          ),
        ),
        true,
      );
    }
    final processing = _processDectogLink(uri, inApp: inApp);
    _linkResults[key] = processing;
    while (_linkResults.length > _maxLinkResults) {
      _linkResults.remove(_linkResults.keys.first);
    }
    return (processing, false);
  }

  /// Process a DecTog link using pure Dart URL parsing
  Future<DectogLinkClick> _processDectogLink(
    Uri uri, {
    bool inApp = false,
  }) async {
    final originalUrl = uri.toString();
    final receivedAt = DateTime.now();

    // Parse username and slug using pure Dart
    final parseResult = _parseDectogUrl(uri);
    if (parseResult == null) {
      return DectogLinkClick(
        originalUrl: originalUrl,
        slug: 'unknown',
        username: 'unknown',
        error: DectogError.linkError('Invalid DecTog URL format'),
        receivedAt: receivedAt,
      );
    }

    var username = parseResult['username']!;
    final slug = parseResult['slug']!;
    final bouncedClickId = validClickId(uri.queryParameters['dtg_click']);

    // Collection off: the app gets the link as parsed, its click and
    // open wait for setEnabled(true), and nothing is resolved or sent.
    if (!_sdkState.enabled) {
      _parkLink(
        _ParkedLink(
          uri: uri,
          username: username,
          slug: slug,
          clickId: bouncedClickId,
          receivedAt: receivedAt,
          inApp: inApp,
          generation: _consentGeneration,
        ),
      );
      _log('Collection off: link to $slug delivered, its report held');
      return DectogLinkClick(
        originalUrl: originalUrl,
        slug: slug,
        username: username,
        inApp: inApp,
        receivedAt: receivedAt,
      );
    }

    // A custom-domain link before the server named the account. The
    // click and the open still count (the server scopes them by key and
    // slug); only resolving needs the username.
    if (username.isEmpty) username = await _accountUsername() ?? '';

    _log('Processing DecTog link: username=$username, slug=$slug');

    // Log the click and the warm open in the background (fire-and-forget),
    // independent of resolving: the backend checks the slug itself.
    // dtg_click carries the web click id from an intent:// bounce so the
    // backend converts the existing web row instead of inserting a second.
    _reportLink(username, slug, uri, bouncedClickId, receivedAt, inApp: inApp);

    // Try to resolve link details from backend
    DectogLinkResolution? linkResolution;
    try {
      if (username.isEmpty) {
        throw StateError(
          'the account of a custom-domain link is not known yet',
        );
      }
      linkResolution = await resolveLink(username, slug);
      _log(
        'Link resolved: ${linkResolution.type} link targeting ${linkResolution.target}',
      );
    } catch (e) {
      _log('Failed to resolve link details: $e');
      // Continue without link details - not a fatal error
    }

    return DectogLinkClick(
      originalUrl: originalUrl,
      slug: slug,
      username: username,
      linkResolution: linkResolution,
      inApp: inApp,
      receivedAt: receivedAt,
    );
  }

  /// The click (unless tapped inside the app) and the open of a link.
  void _reportLink(
    String username,
    String slug,
    Uri uri,
    String? clickId,
    DateTime receivedAt, {
    required bool inApp,
  }) {
    // A link tapped inside the app counts as an open, not a click.
    if (!inApp) {
      _logMobileClick(
        username,
        slug,
        uri,
        clickId: clickId,
        receivedAt: receivedAt,
      ).catchError((error) {
        _log('Failed to log mobile click: $error');
      });
    }
    unawaited(
      _reportAppOpen(username, slug, clickId: clickId, openedAt: receivedAt),
    );
  }

  /// Link reports held while collection is off, replayed by
  /// setEnabled(true); a setEnabled(false) in between drops them.
  final List<_ParkedLink> _parkedLinks = [];
  int _consentGeneration = 0;
  static const int _maxParkedLinks = 10;

  void _parkLink(_ParkedLink link) {
    _parkedLinks.add(link);
    while (_parkedLinks.length > _maxParkedLinks) {
      _parkedLinks.removeAt(0);
    }
  }

  Future<void> _replayParkedLinks() async {
    final parked = List.of(_parkedLinks);
    _parkedLinks.clear();
    for (final p in parked) {
      if (p.generation != _consentGeneration) continue;
      final username =
          p.username.isEmpty ? await _accountUsername() ?? '' : p.username;
      _reportLink(
        username,
        p.slug,
        p.uri,
        p.clickId,
        p.receivedAt,
        inApp: p.inApp,
      );
    }
  }

  /// Parse DecTog URL using pure Dart
  Map<String, String>? _parseDectogUrl(Uri uri) => parseDectogUrl(
    uri,
    _config!.effectiveBaseUrl,
    linkRootDomain: _config!.effectiveLinkRootDomain,
    // The custom domains the app lists, and the one the server names.
    linkDomains: [..._config!.linkDomains, ...?_sdkConfig.config?.linkHosts],
    username: _sdkConfig.config?.username,
  );

  /// The account a custom-domain link belongs to (this key's own):
  /// from the cached server settings, else fetched now, bounded.
  Future<String?> _accountUsername() async {
    final cached = _sdkConfig.config?.username;
    if (cached != null && cached.isNotEmpty) return cached;
    final fetched = await _fetchSdkConfig(
      timeout: const Duration(milliseconds: 1500),
    );
    return fetched?.username;
  }

  // ============================================================
  // HTTP
  // ============================================================

  /// One v1 API call: JSON in and out, the SDK User-Agent, a timeout, and
  /// errors decoded even when the body isn't JSON (e.g. a Cloudflare 5xx
  /// page). [auth] signs the request with the API key; resolve is public.
  /// A `Retry-After` header on an error rides the DectogError details as
  /// `retry_after_ms` so the install transport can honour it.
  Future<dynamic> _api(
    String method,
    String path, {
    Map<String, dynamic>? body,
    int expect = 200,
    int? orStatus,
    bool auth = true,
    Duration timeout = _httpTimeout,
    required String failure,
  }) async {
    _ensureInitialized();
    final raw = body == null ? '' : jsonEncode(body);
    final uri = Uri.parse('${_config!.effectiveBaseUrl}$path');
    final headers = <String, String>{
      if (auth) ..._authHeaders(raw, jsonBody: body != null),
      if (!auth && body != null) 'Content-Type': 'application/json',
      'User-Agent': _sdkUserAgent,
    };
    final http.Response response;
    try {
      response = await switch (method) {
        'GET' => _httpClient.get(uri, headers: headers),
        'POST' => _httpClient.post(uri, headers: headers, body: raw),
        'PUT' => _httpClient.put(uri, headers: headers, body: raw),
        'DELETE' => _httpClient.delete(uri, headers: headers),
        _ => throw ArgumentError(method),
      }.timeout(timeout);
    } on TimeoutException {
      throw DectogError.networkError('$failure: request timed out');
    } catch (e) {
      throw DectogError.networkError('Network error: $e');
    }
    if (response.statusCode == expect || response.statusCode == orStatus) {
      return response.body.isEmpty ? null : jsonDecode(response.body);
    }
    final retryAfter = parseRetryAfter(response.headers['retry-after']);
    throw DectogError.fromResponse(
      statusCode: response.statusCode,
      body: response.body,
      fallbackMessage: '$failure (HTTP ${response.statusCode})',
      headerRequestId: response.headers['x-request-id'],
      extraDetails: {
        if (retryAfter != null) 'retry_after_ms': retryAfter.inMilliseconds,
      },
    );
  }

  /// Link fields for create/update bodies; null values are left out (on
  /// update: keep the stored value; pass '' to clear a field).
  Map<String, dynamic> _linkFields({
    String? target,
    Map<String, dynamic>? metadata,
    String? appId,
    String? iosDeepLinkPath,
    String? androidDeepLinkPath,
    String? redirectUrl,
    String? fallbackUrl,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? label,
    String? campaign,
    String? adgroup,
    String? creative,
  }) => {
    if (target != null) 'target': target,
    if (metadata != null) 'metadata': metadata,
    if (appId != null) 'app_id': appId,
    if (iosDeepLinkPath != null) 'ios_deep_link_path': iosDeepLinkPath,
    if (androidDeepLinkPath != null)
      'android_deep_link_path': androidDeepLinkPath,
    if (redirectUrl != null) 'redirect_url': redirectUrl,
    if (fallbackUrl != null) 'fallback_url': fallbackUrl,
    if (ogTitle != null) 'og_title': ogTitle,
    if (ogDescription != null) 'og_description': ogDescription,
    if (ogImageUrl != null) 'og_image_url': ogImageUrl,
    if (label != null) 'label': label,
    if (campaign != null) 'campaign': campaign,
    if (adgroup != null) 'adgroup': adgroup,
    if (creative != null) 'creative': creative,
  };

  @override
  Future<DectogLink> createLink({
    required String slug,
    String? target,
    Map<String, dynamic>? metadata,
    String? appId,
    String? iosDeepLinkPath,
    String? androidDeepLinkPath,
    String? redirectUrl,
    String? fallbackUrl,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? label,
    String? campaign,
    String? adgroup,
    String? creative,
  }) async {
    final json = await _api(
      'POST',
      '/api/v1/links',
      body: {
        'slug': slug,
        ..._linkFields(
          target: target,
          metadata: metadata,
          appId: appId,
          iosDeepLinkPath: iosDeepLinkPath,
          androidDeepLinkPath: androidDeepLinkPath,
          redirectUrl: redirectUrl,
          fallbackUrl: fallbackUrl,
          ogTitle: ogTitle,
          ogDescription: ogDescription,
          ogImageUrl: ogImageUrl,
          label: label,
          campaign: campaign,
          adgroup: adgroup,
          creative: creative,
        ),
      },
      expect: 201,
      failure: 'Failed to create link',
    );
    return DectogLink.fromJson(json as Map<String, dynamic>);
  }

  /// Read the cached server settings; fetch when there are none
  /// (bounded) or refresh in the background when they are stale.
  Future<void> _loadSdkConfig() async {
    final cached = await _sdkConfig.load();
    // Collection off: the cached settings only, no request.
    if (!_sdkState.enabled || _sdkConfig.isFresh()) return;
    if (cached == null) {
      await _fetchSdkConfig(timeout: const Duration(milliseconds: 1500));
    } else {
      unawaited(_fetchSdkConfig());
    }
  }

  Future<DectogSdkConfig?> _fetchSdkConfig({Duration? timeout}) async {
    // No request of the SDK's own while collection is off.
    if (!_sdkState.enabled) return null;
    try {
      String? package;
      try {
        package = (await _getAppInfo()).packageName;
      } catch (_) {}
      final json = await _api(
        'GET',
        '/api/v1/sdk-config${package == null ? '' : '?package=${Uri.encodeQueryComponent(package)}'}',
        failure: 'Failed to read the app settings',
        timeout: timeout ?? _httpTimeout,
      );
      final config = DectogSdkConfig.fromJson(json as Map<String, dynamic>);
      await _sdkConfig.save(config);
      return config;
    } catch (e) {
      _log('App settings not refreshed: $e');
      return null;
    }
  }

  @override
  Future<DectogDiagnostics> diagnostics() async {
    _ensureInitialized();
    final warnings = <String>[];
    final server = await _fetchSdkConfig() ?? _sdkConfig.config;
    if (server == null) {
      warnings.add('The app settings could not be read from the server.');
      return DectogDiagnostics(warnings: warnings);
    }
    // A test key where a live one belongs, or the other way round.
    final expected = _config!.environment;
    if (expected != null && expected != server.environment) {
      warnings.add(
        'This build expects a ${expected.name} key, but its key belongs to the ${server.environment.name} environment (${server.username ?? 'unknown'}).',
      );
    } else if (expected == null &&
        kReleaseMode &&
        server.environment == DectogEnvironment.test) {
      warnings.add(
        'A release build with a test environment key (${server.username ?? 'unknown'}): its installs and events stay out of your live numbers.',
      );
    }
    String? package;
    try {
      package = (await _getAppInfo()).packageName;
    } catch (_) {}
    if (Platform.isIOS) {
      if (package != null &&
          server.iosBundleId != null &&
          server.iosBundleId != package) {
        warnings.add(
          'The dashboard has bundle ID ${server.iosBundleId}, this build is $package.',
        );
      }
      final scheme = server.iosAppScheme;
      if (scheme != null) {
        final schemes =
            await _guard(() => _identifierChannel.getUrlSchemes()) ??
            const <String>[];
        if (!schemes
            .map((s) => s.toLowerCase())
            .contains(scheme.toLowerCase())) {
          warnings.add(
            'The URL scheme "$scheme" from the dashboard is not in Info.plist CFBundleURLTypes.',
          );
        }
      }
    } else if (Platform.isAndroid) {
      if (package != null &&
          server.androidPackage != null &&
          server.androidPackage != package) {
        warnings.add(
          'The dashboard has package ${server.androidPackage}, this build is $package.',
        );
      }
      final states = await _guard(
        () => _identifierChannel.getDomainVerification(),
      );
      if (states != null) {
        for (final host in server.linkHosts) {
          final state = states[host];
          if (state != 'verified') {
            warnings.add(
              state == null
                  ? 'Android App Links: $host is not declared in the manifest intent filter.'
                  : 'Android App Links: $host is $state, not verified, so links open the browser.',
            );
          }
        }
      }
    }
    for (final w in warnings) {
      _log('Diagnostics: $w');
    }
    return DectogDiagnostics(serverConfig: server, warnings: warnings);
  }

  @override
  Future<DectogLink> createReferralLink({
    required String customerId,
    String? campaign,
  }) async {
    final json = await _api(
      'POST',
      '/api/v1/referral-links',
      body: {
        'customer_id': customerId,
        if (campaign != null) 'campaign': campaign,
      },
      expect: 201,
      orStatus: 200,
      failure: 'Failed to create the referral link',
    );
    return DectogLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<DectogLink> updateLink(
    String slug, {
    String? target,
    Map<String, dynamic>? metadata,
    String? iosDeepLinkPath,
    String? androidDeepLinkPath,
    String? redirectUrl,
    String? fallbackUrl,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
    String? label,
    String? campaign,
    String? adgroup,
    String? creative,
  }) async {
    final json = await _api(
      'PUT',
      '/api/v1/links/${Uri.encodeComponent(slug)}',
      body: _linkFields(
        target: target,
        metadata: metadata,
        iosDeepLinkPath: iosDeepLinkPath,
        androidDeepLinkPath: androidDeepLinkPath,
        redirectUrl: redirectUrl,
        fallbackUrl: fallbackUrl,
        ogTitle: ogTitle,
        ogDescription: ogDescription,
        ogImageUrl: ogImageUrl,
        label: label,
        campaign: campaign,
        adgroup: adgroup,
        creative: creative,
      ),
      failure: 'Failed to update link',
    );
    return DectogLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<DectogLinkPage> getLinks({int? limit, String? cursor}) async {
    final query = {
      if (limit != null) 'limit': '$limit',
      if (cursor != null) 'cursor': cursor,
    };
    final json = await _api(
      'GET',
      query.isEmpty
          ? '/api/v1/links'
          : '/api/v1/links?${Uri(queryParameters: query).query}',
      failure: 'Failed to fetch links',
    );
    return DectogLinkPage.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<DectogLink> getLink(String slug) async {
    final json = await _api(
      'GET',
      '/api/v1/links/${Uri.encodeComponent(slug)}',
      failure: 'Failed to fetch link',
    );
    return DectogLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<void> deleteLink(String slug, {bool permanently = false}) async {
    await _api(
      'DELETE',
      '/api/v1/links/${Uri.encodeComponent(slug)}${permanently ? '?permanent=true' : ''}',
      failure: 'Failed to delete link',
    );
  }

  @override
  Future<DectogTempLink> createTempLink({
    String? target,
    String? slug,
    int ttlSeconds = 900,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) async {
    final json = await _api(
      'POST',
      '/api/v1/temp-links',
      body: {
        if (slug != null) 'slug': slug,
        'ttlSeconds': ttlSeconds,
        ..._linkFields(
          target: target,
          ogTitle: ogTitle,
          ogDescription: ogDescription,
          ogImageUrl: ogImageUrl,
        ),
      },
      expect: 201,
      failure: 'Failed to create temporary link',
    );
    return DectogTempLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<DectogTempLink> updateTempLink(
    String slug, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) async {
    final json = await _api(
      'PUT',
      '/api/v1/temp-links/${Uri.encodeComponent(slug)}',
      body: _linkFields(
        target: target,
        ogTitle: ogTitle,
        ogDescription: ogDescription,
        ogImageUrl: ogImageUrl,
      ),
      failure: 'Failed to update temporary link',
    );
    return DectogTempLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<DectogTempLink> getTempLink(String slug) async {
    final json = await _api(
      'GET',
      '/api/v1/temp-links/${Uri.encodeComponent(slug)}',
      failure: 'Failed to fetch temporary link',
    );
    return DectogTempLink.fromJson(json as Map<String, dynamic>);
  }

  @override
  Future<void> deleteTempLink(String slug, {bool permanently = false}) async {
    await _api(
      'DELETE',
      '/api/v1/temp-links/${Uri.encodeComponent(slug)}${permanently ? '?permanent=true' : ''}',
      failure: 'Failed to delete temporary link',
    );
  }

  @override
  Future<DectogLinkResolution> resolveLink(String username, String slug) async {
    final json = await _api(
      'GET',
      '/api/v1/resolve/${Uri.encodeComponent(username)}/${Uri.encodeComponent(slug)}',
      auth: false,
      failure: 'Failed to resolve link',
    );
    return DectogLinkResolution.fromJson(json as Map<String, dynamic>);
  }

  @override
  /// Stream of incoming link clicks
  Stream<DectogLinkClick> get onLinkClick => _linkClickController.stream;

  @override
  /// Stream of app install events
  Stream<DectogAppInstallResponse> get onAppInstalled =>
      _appInstallSubject.stream;

  @override
  /// Get the current app install response (if available)
  DectogAppInstallResponse? get currentAppInstall =>
      _appInstallSubject.valueOrNull;

  @override
  /// Get the initial link if app was opened via a link
  Future<DectogLinkClick?> getInitialLink() async {
    _ensureInitialized();

    if (_launchedFromHistory) return null;
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        if (isSensitiveUrl(initialUri)) return null;
        return await _processOnce(initialUri, initial: true).$1;
      }
      return null;
    } catch (e) {
      return DectogLinkClick(
        originalUrl: 'unknown',
        slug: 'unknown',
        username: 'unknown',
        error: DectogError.linkError('Failed to get initial link: $e'),
        receivedAt: DateTime.now(),
      );
    }
  }

  /// Ensure the plugin is initialized
  void _ensureInitialized() {
    if (!_initialized || _config == null) {
      throw DectogError.configError(
        'FlutterDectog not initialized. Call initialize() first.',
      );
    }
  }

  /// Log mobile app click to backend (fire-and-forget)
  Future<void> _logMobileClick(
    String username,
    String slug,
    Uri originalUri, {
    String? clickId,
    DateTime? receivedAt,
  }) async {
    if (_config == null || !_sdkState.enabled) return;

    try {
      // Extract UTM parameters from original URI
      final utmParams = <String, String>{};
      originalUri.queryParameters.forEach((key, value) {
        if (key.startsWith('utm_')) {
          utmParams[key] = value;
        }
      });

      // Device identifiers for the click record, sent only when the
      // device tier is collected (N1 item 1).
      String? deviceId;
      String? deviceModel;
      String? osVersion;
      if (_config?.collectsDeviceTier == true) {
        deviceId = await _deviceIdentityService.getDeviceId(
          persist: _config?.persistDeviceId == true,
        );
        final hardware =
            _cachedHardware ?? await _deviceHardwareService.collect();
        _cachedHardware = hardware;
        deviceModel = hardware.deviceModel;
        osVersion = hardware.osVersion;
      }

      // the launching intent's referrer package (Branch
      // initial_referrer) — Android only, best effort.
      String? launchReferrer;
      if (Platform.isAndroid) {
        launchReferrer =
            (await _guard(() => _identifierChannel.getLaunchInfo()))?.referrer;
      }

      // Collect device information
      final clickData = <String, dynamic>{
        'slug': slug,
        if (clickId != null) 'click_id': clickId,
        'device_type': 'mobile',
        'platform': _deviceService.getPlatform(),
        'is_mobile_app': true,
        'session_id': _generateSessionId(),
        'language': _deviceService.getLanguage(),
        if (osVersion != null) 'os_version': osVersion,
        if (deviceId != null) 'device_id': deviceId,
        if (deviceModel != null) 'device_model': deviceModel,
        // when the link ARRIVED on the device (Adjust click_time) —
        // the server-side insert time lags by the whole launch.
        'client_click_time':
            (receivedAt ?? DateTime.now()).toUtc().toIso8601String(),
        if (launchReferrer != null) 'launch_referrer': launchReferrer,
        // The rest of the opened URL stays on the device; the
        // server keeps only the dec_* and utm_* values below.
        'metadata': {
          'flutter_plugin_version': packageVersion,
          'dart_version': _getDartVersion(),
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        },
      };

      // Add UTM parameters if present
      utmParams.forEach((key, value) {
        clickData[key] = value;
      });

      // dec_* link overrides: the server validates and stores them
      // on the click, like the redirect does for browser taps.
      final linkParams = <String, String>{
        for (final e in originalUri.queryParameters.entries)
          if (e.key.startsWith('dec_')) e.key: e.value,
      };
      if (linkParams.isNotEmpty) clickData['link_params'] = linkParams;

      final body = jsonEncode(clickData);
      final response = await _httpClient
          .post(
            Uri.parse('${_config!.effectiveBaseUrl}/api/v1/clicks'),
            headers: {..._authHeaders(body), 'User-Agent': _sdkUserAgent},
            body: body,
          )
          .timeout(_httpTimeout);

      if (response.statusCode == 200) {
        _log(
          'Mobile click logged successfully: $username/$slug (plugin v$packageVersion)',
        );
      } else {
        _log(
          'Failed to log mobile click: ${response.statusCode} ${response.body}',
        );
      }
    } catch (e) {
      _log('Error logging mobile click: $e');
      // Fail silently - don't break user experience for analytics
    }
  }

  /// POST /api/v1/app-opens: a DecTog link opened the
  /// already-installed app (cold start or warm resume). Fire-and-forget,
  /// signed like every /api/v1 call; carries the intent-bounce dtg_click
  /// when present so the backend ties the open to the web click row.
  Future<void> _reportAppOpen(
    String username,
    String slug, {
    String? clickId,
    DateTime? openedAt,
  }) async {
    if (_config == null || !_sdkState.enabled) return;
    // Later events name this open, so a re-engagement is credited.
    final previous = _sdkState.lastOpen;
    final open = LastOpen(
      slug: slug,
      clickId: clickId,
      openedAt: openedAt ?? DateTime.now(),
    );
    final saved = _sdkState.setLastOpen(open);
    unawaited(saved);
    try {
      String? appVersion;
      try {
        appVersion = (await _getAppInfo()).version;
      } catch (_) {}
      final body = jsonEncode({
        if (clickId != null) 'click_id': clickId,
        'username': username,
        'slug': slug,
        'app_version': appVersion,
        'os': Platform.operatingSystem,
        // device anchors are best-effort; opens are valid without them
        if (_lastDeviceId != null) 'device_id': _lastDeviceId,
        if (_lastInstallId != null) 'install_id': _lastInstallId,
      });
      final response = await _httpClient
          .post(
            Uri.parse('${_config!.effectiveBaseUrl}/api/v1/app-opens'),
            headers: {
              ..._authHeaders(body),
              HttpHeaders.userAgentHeader: _sdkUserAgent,
            },
            body: body,
          )
          .timeout(_httpTimeout);
      if (response.statusCode == 404 || response.statusCode == 410) {
        // Not an open the server counts; the earlier one stands.
        await saved;
        await _sdkState.undoLastOpen(open, previous);
        _log('App open refused (${response.statusCode}): $slug is not live');
      } else if (response.statusCode != 200) {
        _log('Failed to report app open: ${response.statusCode}');
      }
    } catch (_) {}
  }

  /// Get Dart version information
  String _getDartVersion() {
    try {
      // This will return something like "3.2.0 (stable)"
      return Platform.version.split(' ').first;
    } catch (e) {
      return 'unknown';
    }
  }

  /// Generate a session ID for tracking user sessions
  String _generateSessionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = DateTime.now().microsecondsSinceEpoch % 10000;
    return '${timestamp}_$random';
  }

  // ============================================================
  // Install registration
  // ============================================================

  /// Track app install if it hasn't been tracked yet
  Future<void> _trackAppInstallIfNeeded() {
    // Disabled: not memoized, so setEnabled(true) can still register it.
    if (!_sdkState.enabled) {
      _log(
        'Collection disabled - install registration waits for setEnabled(true)',
      );
      return Future.value();
    }
    return _installTrackingFuture ??= _trackAppInstallOnce();
  }

  Future<void> _trackAppInstallOnce() async {
    try {
      // Package provenance first: its first-install time validates the
      // sentinel against a restored backup (InstallStateStore).
      final pkg =
          Platform.isAndroid
              ? await _guard(() => _identifierChannel.getPackageInstallInfo())
              : null;
      final dates =
          Platform.isIOS
              ? await _guard(() => _identifierChannel.getInstallDates())
              : null;
      final packageFirstInstallTs =
          pkg?.firstInstallTime ?? dates?.documentsCtime;

      final decision = await _installState.begin(
        packageFirstInstallTs: packageFirstInstallTs,
      );
      switch (decision.kind) {
        case InstallDecisionKind.alreadyTracked:
          _lastInstallId ??= decision.state?.installId ?? _sdkState.installId;
          _log('App install already tracked - skipping');
          return;
        case InstallDecisionKind.inFlight:
          _log('App install registration already in flight - skipping');
          return;
        case InstallDecisionKind.abandoned:
          _log(
            'App install registration abandoned after ${InstallStateStore.maxAttempts} attempts',
          );
          return;
        case InstallDecisionKind.start:
          break;
      }
      final state = decision.state!;
      _log(
        state.attempt == 1
            ? 'First app launch detected - tracking app install'
            : 'Retrying app install registration (attempt ${state.attempt})',
      );

      try {
        final outcome = await _registerInstall(state, pkg: pkg, dates: dates);
        final response = outcome.response;

        // Emit the app install event to the stream
        _appInstallSubject.add(response);
        _lastInstallId = response.installId;
        final sent = outcome.clipboard;
        if (sent != null && response.matchSource == 'clipboard') {
          unawaited(_pasteboard.clearIfUnchanged(sent.mark));
        }
        // Persist the anchor so later launches can stamp event batches and
        // app-opens without a server round-trip.
        unawaited(_sdkState.setInstallId(response.installId));
        _registeredThisProcess = true;

        // The sentinel records whether the referrer question is settled; a
        // non-definitive read is re-asked on later launches (Adjust).
        await _installState.markTracked(
          installId: response.installId,
          referrerClaimed: outcome.referrer.isDefinitive,
          referrerStatus: outcome.referrer.status,
        );

        _log(
          response.matched
              ? 'App install matched to deferred click: ${response.username}/${response.slug} (${response.matchConfidence})'
              : 'App install tracked as organic${response.routing != null ? ' (routing candidate: ${response.routing!.slug})' : ''}',
        );

        // Signals that were still in flight when the POST left: the native
        // referrer retry, the pasteboard alert the user answered late, the
        // paste-control URL that beat the install id.
        final lateReferrer = outcome.lateReferrer;
        if (lateReferrer != null) unawaited(lateReferrer.then(_claimReferrer));
        final lateClipboard = outcome.lateClipboard;
        if (lateClipboard != null) {
          unawaited(
            lateClipboard.then(
              (link) =>
                  link == null
                      ? null
                      : _claimClipboard(link, source: 'clipboard'),
            ),
          );
        }
        final pendingPaste = _pendingPaste;
        if (pendingPaste != null) {
          _pendingPaste = null;
          unawaited(_claimClipboard(pendingPaste, source: 'paste_control'));
        }
      } catch (e) {
        // Downgrade the claim to a retry marker: the next launch re-POSTs
        // (bounded by the attempt cap) with the SAME install_attempt_id.
        await _installState.markFailed(e.toString());
        _log('Failed to track app install: $e');
      }
    } catch (e) {
      _log('Failed to track app install: $e');
      // Don't throw - this shouldn't break initialization
    }
  }

  Future<AppInfo> _getAppInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();

    return AppInfo(
      appName: packageInfo.appName,
      packageName: packageInfo.packageName,
      version: packageInfo.version, // e.g. "1.0.3"
      buildNumber: packageInfo.buildNumber, // e.g. "42"
      // package_info_plus carries the installer store, signing
      // signature and package-manager install/update timestamps — no
      // custom channel read needed anymore.
      buildSignature: packageInfo.buildSignature,
      installerStore: packageInfo.installerStore,
      installTime: packageInfo.installTime,
      updateTime: packageInfo.updateTime,
    );
  }

  /// Pasteboard-based deterministic attribution (Branch NativeLink / Adjust
  /// LinkMe): on by default on iOS, opt-in on Android. The silent
  /// `hasURLs` check runs first, so the pasteboard is only READ (iOS 16+
  /// system alert, Android 12+ paste notice) when it actually holds a URL.
  /// Only a URL that parses as a DecTog link for this deployment is
  /// returned (and then cleared, like Branch); everything else is discarded
  /// client-side and never reaches the wire. The read may outlive the POST
  /// (the user answering the alert late): [late] then carries the value.
  Future<({_PastedLink? read, Future<_PastedLink?>? late})>
  _readClipboardDecTogUrl() async {
    const none = (read: null, late: null);
    final config = _config;
    if (config == null) return none;
    if (!_isIOS && !Platform.isAndroid) return none;
    if (!_readClipboard(config)) return none;
    try {
      final hasUrl = await _identifierChannel.pasteboardHasUrl().timeout(
        _auxTimeout,
      );
      if (!hasUrl) return none;
      final pending = _identifierChannel.readPasteboardUrl();
      try {
        final text = await pending.timeout(_pasteboardTimeout);
        return (read: await _acceptClipboardText(text), late: null);
      } on TimeoutException {
        return (
          read: null,
          late: pending.then(_acceptClipboardText).catchError((_) => null),
        );
      }
    } catch (_) {
      return none;
    }
  }

  /// The pasteboard text when it is a DecTog URL that names a click, with
  /// the mark of this read, else null. A bare share link is never
  /// sent, and nothing is cleared here; only a verdict that credits the link
  /// clears the pasteboard, against this read's mark.
  Future<_PastedLink?> _acceptClipboardText(String? raw) async {
    final text = raw?.trim() ?? '';
    if (text.isEmpty || text.length > 2048) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) return null;
    if (_config == null || _parseDectogUrl(uri) == null) return null;
    if (!PasteboardGate.carriesClickTag(text)) return null;
    return (url: text, mark: await _pasteboard.remember());
  }

  /// Network + carrier tier for the install payload.
  Future<({String? connectivity, String? mcc, String? mnc})>
  _collectNetworkInfo() async {
    final connectivity = await _networkService.getConnectivityType();
    final carrier = await _networkService.getCarrierInfo();
    return (connectivity: connectivity, mcc: carrier?.mcc, mnc: carrier?.mnc);
  }

  /// Build and POST the install registration for [state].
  Future<_InstallOutcome> _registerInstall(
    InstallState state, {
    PackageInstallInfo? pkg,
    InstallDates? dates,
  }) async {
    final config = _config!;
    final collectDeviceData = config.collectsDeviceTier;
    final persistDeviceId = config.persistDeviceId;
    final deviceInfo = _deviceService.getDeviceInfo();

    // Everything runs concurrently. The referrer read is the only
    // latency-critical piece (installReferrerTimeout, 5 s by default); every
    // other read has a 1.5 s ceiling (six unbounded reads used
    // to be able to hang the registration). All best-effort.
    final appInfoFuture = _guard(
      () => _getAppInfo(),
      timeout: const Duration(seconds: 3),
    );
    final referrerFuture = _installReferrerService.read(
      timeout: config.installReferrerTimeout,
      oemStores: _oemStoreReferrers(config),
      provider: config.installReferrerProvider,
    );
    final deviceIdFuture =
        collectDeviceData
            ? _guard(
              () =>
                  _deviceIdentityService.getDeviceId(persist: persistDeviceId),
            )
            : Future<String?>.value(null);
    final hardwareFuture =
        collectDeviceData
            ? _guard(() => _deviceHardwareService.collect())
            : Future<DeviceHardwareInfo?>.value(null);
    final networkFuture =
        collectDeviceData
            ? _guard(() => _collectNetworkInfo())
            : Future<({String? connectivity, String? mcc, String? mnc})?>.value(
              null,
            );
    final webUaFuture =
        collectDeviceData && Platform.isAndroid
            ? _guard(() => _identifierChannel.getWebViewUserAgent())
            : Future<String?>.value(null);
    final fbAppId = config.fbAppId ?? _sdkConfig.config?.fbAppId;
    final metaReferrerFuture =
        (fbAppId != null && fbAppId.trim().isNotEmpty && Platform.isAndroid)
            ? _guard(() => _identifierChannel.getMetaReferrer(fbAppId))
            : Future<MetaReferrer?>.value(null);
    // A recovery registration happens mid-session; the
    // first-launch read would prompt again, credit whatever link the user
    // copied since and clear it. The server ignores it there anyway.
    final clipboardFuture =
        state.recoveredFrom != null
            ? Future.value((read: null, late: null))
            : _readClipboardDecTogUrl();
    final adIdFuture = _readAdvertisingId(config);
    final asaFuture =
        Platform.isIOS && config.collectsAppleSearchAdsToken
            ? _guard(
              () => _identifierChannel.getAttributionToken(),
              timeout: _asaTimeout,
            )
            : Future<String?>.value(null);

    final appInfo = await appInfoFuture;
    final deviceId = await deviceIdFuture;
    final hardware = await hardwareFuture;
    final network = await networkFuture;
    final referrerRead = await referrerFuture;
    final webUserAgent = await webUaFuture;
    final metaReferrer = await metaReferrerFuture;
    final clipboard = await clipboardFuture;
    final asaToken = await asaFuture;
    final adId = await adIdFuture;
    // Read after the awaits: iOS delivers these settings once the first
    // view appears, which can be after initialize() starts.
    final settings =
        collectDeviceData ? _deviceSettingsService.read(isIOS: _isIOS) : null;
    if (hardware != null) _cachedHardware ??= hardware;
    if (deviceId != null) _lastDeviceId ??= deviceId;
    final referrer = referrerRead.result;
    _log('Install referrer: $referrer');

    // Client install classification (Branch STATE_* + keychain dates): an
    // `update` is an existing user — the server never fingerprints it.
    final installState = classifyInstallState(
      isAndroid: Platform.isAndroid,
      firstInstallTs: pkg?.firstInstallTime ?? appInfo?.installTimeMs,
      lastUpdateTs: pkg?.lastUpdateTime ?? appInfo?.updateTimeMs,
      keychainFirstInstallTs: dates?.keychainFirstInstall,
      documentsCtimeTs: dates?.documentsCtime,
      executableCtimeTs: dates?.executableCtime,
      libraryCtimeTs: dates?.libraryCtime,
    );
    final firstInstallTs =
        Platform.isAndroid
            ? (pkg?.firstInstallTime ?? appInfo?.installTimeMs)
            : (dates?.keychainFirstInstall ??
                dates?.documentsCtime ??
                appInfo?.installTimeMs);

    DectogAppInstallRequest buildRequest() => DectogAppInstallRequest(
      appPlatform: _deviceService.getAppPlatform(),
      appVersion: appInfo?.version,
      appBuildNumber: appInfo?.buildNumber,
      os: deviceInfo['os'] as String?,
      // Prefer device_info_plus's precise version; fall back to the
      // coarse dart:io value.
      osVersion: hardware?.osVersion ?? deviceInfo['os_version'] as String?,
      language: deviceInfo['language'] as String?,
      timezone: deviceInfo['timezone'] as String?,
      utcOffsetMin: deviceInfo['utc_offset_min'] as int?,
      installReferrer: referrer.referrer,
      deviceId: deviceId,
      deviceModel: hardware?.deviceModel,
      deviceManufacturer: hardware?.deviceManufacturer,
      deviceKind: hardware?.deviceKind,
      cpuType: hardware?.cpuType,
      osBuild: hardware?.osBuild,
      screenWidth: hardware?.screenWidth,
      screenHeight: hardware?.screenHeight,
      screenDensity: hardware?.screenDensity,
      connectivityType: network?.connectivity,
      carrierMcc: network?.mcc,
      carrierMnc: network?.mnc,
      textSize: settings?.textSize,
      darkMode: settings?.darkMode,
      highContrast: settings?.highContrast,
      reduceMotion: settings?.reduceMotion,
      packageName: appInfo?.packageName,
      isPhysicalDevice: hardware?.isPhysicalDevice,
      installerPackage: appInfo?.installerStore ?? pkg?.installer,
      installTime: appInfo?.installTimeMs ?? pkg?.firstInstallTime,
      updateTime: appInfo?.updateTimeMs ?? pkg?.lastUpdateTime,
      referrerClickTs: referrer.clickTs,
      installBeginTs: referrer.installBeginTs,
      webUserAgent: webUserAgent,
      metaReferrer: metaReferrer?.referrer,
      metaReferrerTs: metaReferrer?.ts,
      metaReferrerIsCt: metaReferrer?.isCt,
      clipboardUrl: clipboard.read?.url,
      adId: adId == null || adId.limited ? null : adId.id,
      adTrackingLimited: adId?.limited,
      // ---- contract v2 ----
      installAttemptId: state.installAttemptId,
      recoveredFrom: state.recoveredFrom,
      attempt: state.attempt,
      createdAtClient: state.createdAt.toUtc().toIso8601String(),
      sentAtClient: DateTime.now().toUtc().toIso8601String(),
      referrerStatus: referrer.status,
      referrerAttempts: referrer.attempts,
      referrerWaitMs: referrer.waitMs,
      referrerClickServerTs: referrer.clickServerTs,
      installBeginServerTs: referrer.installBeginServerTs,
      installVersion: referrer.installVersion,
      googlePlayInstant: referrer.instant,
      referrerStore: referrer.hasReferrer ? referrer.store : null,
      // A recovery is a reinstall from the server's point of view.
      installState: state.recoveredFrom != null ? 'reinstall' : installState,
      firstInstallTs: firstInstallTs,
      asaToken: asaToken,
      metadata: {
        'flutter_plugin_version': packageVersion,
        'dart_version': deviceInfo['dart_version'],
        'platform': deviceInfo['platform'],
        'is_mobile': deviceInfo['is_mobile'],
        'api_version': 'v1',
        'logged_via': 'flutter_sdk_auto',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        // Android APK signing-key hex ('' elsewhere) — integrity review.
        if (appInfo != null && appInfo.buildSignature.isNotEmpty)
          'build_signature': appInfo.buildSignature,
        // Every store's raw read, for diagnostics (never a match input).
        if (referrer.all.isNotEmpty)
          'referrer_reads': {
            for (final e in referrer.all.entries)
              e.key: {
                'status': e.value.status,
                'attempts': e.value.attempts,
                'wait_ms': e.value.waitMs,
              },
          },
      },
    );

    _log('Logging app install automatically: ${buildRequest()}');
    final response = await _postInstallWithRetry(buildRequest);
    _log('App install logged successfully: $response');

    return _InstallOutcome(
      response: response,
      referrer: referrer,
      lateReferrer: referrerRead.late,
      lateClipboard: clipboard.late,
      clipboard: clipboard.read,
    );
  }

  /// Two in-process attempts with jittered backoff; `Retry-After` honoured
  /// up to [_maxInProcessRetryAfter] (longer waits defer to the next launch,
  /// which retries with the same install_attempt_id). 4xx other than
  /// 408/429 are not retried in-process (Branch drops them, Adjust stops).
  Future<DectogAppInstallResponse> _postInstallWithRetry(
    DectogAppInstallRequest Function() request,
  ) async {
    DectogError? last;
    for (var attempt = 1; attempt <= _installPostAttempts; attempt++) {
      try {
        final json = await _api(
          'POST',
          '/api/v1/app-installs',
          body: request().toJson(),
          failure: 'Failed to log app install',
          timeout: _installPostTimeout,
        );
        return DectogAppInstallResponse.fromJson(json as Map<String, dynamic>);
      } on DectogError catch (e) {
        last = e;
        final decision = installRetryDecision(e.statusCode);
        if (decision != RetryDecision.retryNow ||
            attempt == _installPostAttempts)
          rethrow;
        final retryAfterMs = e.details?['retry_after_ms'];
        final retryAfter =
            retryAfterMs is int ? Duration(milliseconds: retryAfterMs) : null;
        if (retryAfter != null && retryAfter > _maxInProcessRetryAfter) rethrow;
        final delay = retryAfter ?? backoffDelay(attempt);
        _log(
          'Install POST failed (${e.statusCode ?? 'network'}), retrying in ${delay.inMilliseconds} ms',
        );
        await Future<void>.delayed(delay);
      } catch (e) {
        throw DectogError.networkError(
          'Network error while logging app install: $e',
        );
      }
    }
    throw last ?? DectogError.networkError('Failed to log app install');
  }

  // ---- late claims ---------------------------------------------

  /// `POST /api/v1/app-installs/:id/claim`: a deterministic signal that
  /// arrived after the registration. The server upgrades the stored
  /// verdict when the signal names a click (or synthesizes one from a
  /// self-describing referrer); an `upgraded` verdict is re-emitted on
  /// [onAppInstalled]. Returns null on 404 (unknown install — nothing left
  /// to upgrade; callers stop retrying), rethrows other failures.
  Future<DectogAppInstallResponse?> _claim(
    String installId,
    Map<String, dynamic> body,
  ) async {
    try {
      final json = await _api(
        'POST',
        '/api/v1/app-installs/${Uri.encodeComponent(installId)}/claim',
        body: body,
        failure: 'Failed to claim install signal',
        timeout: _installPostTimeout,
      );
      final verdict = DectogAppInstallResponse.fromJson(
        json as Map<String, dynamic>,
      );
      _log(
        'Install claim (${body['claim_source']}): ${verdict.claim} ${verdict.claimReason ?? ''}',
      );
      if (verdict.claim == 'upgraded') {
        _appInstallSubject.add(verdict);
      }
      return verdict;
    } on DectogError catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  String? get _trackedInstallId =>
      _lastInstallId ?? _installState.current?.installId ?? _sdkState.installId;

  /// Send a referrer read that happened after the registration. The
  /// sentinel's `referrer_claimed` flag is written only once the server
  /// acknowledged (Adjust's ack-gated install-referrer flag).
  Future<void> _claimReferrer(ReferrerResult referrer) async {
    final installId = _trackedInstallId;
    if (installId == null || _config == null) return;
    if (_installState.current?.referrerClaimed == true) return;
    if (!(referrer.hasReferrer || referrer.isDefinitive)) return;
    try {
      final verdict = await _claim(installId, {
        'claim_source': 'late_referrer',
        if (referrer.hasReferrer) 'install_referrer': referrer.referrer,
        if (referrer.hasReferrer) 'referrer_store': referrer.store,
        'referrer_status': referrer.status,
        'referrer_attempts': referrer.attempts,
        'referrer_wait_ms': referrer.waitMs,
        if (referrer.clickTs != null) 'referrer_click_ts': referrer.clickTs,
        if (referrer.installBeginTs != null)
          'install_begin_ts': referrer.installBeginTs,
        if (referrer.clickServerTs != null)
          'referrer_click_server_ts': referrer.clickServerTs,
        if (referrer.installBeginServerTs != null)
          'install_begin_server_ts': referrer.installBeginServerTs,
        if (referrer.installVersion != null)
          'install_version': referrer.installVersion,
        if (referrer.instant != null) 'google_play_instant': referrer.instant,
        if (_installState.current != null)
          'attempt': _installState.current!.attempt,
      });
      // 200 or 404: the question is settled either way.
      await _installState.markReferrerClaimed(referrer.status);
      if (verdict == null)
        _log('Install claim: unknown install, referrer retries stopped');
    } catch (e) {
      _log('Late referrer claim failed, will retry next launch: $e');
    }
  }

  /// A DecTog URL from the pasteboard (late alert answer) or the paste
  /// control, sent as a deterministic claim. An upgraded verdict
  /// clears the pasteboard, against the mark of the read that found it.
  Future<void> _claimClipboard(
    _PastedLink link, {
    required String source,
  }) async {
    final installId = _trackedInstallId;
    if (installId == null) {
      _pendingPaste = link;
      return;
    }
    try {
      final verdict = await _claim(installId, {
        'claim_source': source,
        'clipboard_url': link.url,
      });
      if (verdict?.claim == 'upgraded') {
        unawaited(_pasteboard.clearIfUnchanged(link.mark));
      }
    } catch (e) {
      _log('Clipboard claim failed: $e');
    }
  }

  void _onPasteControlUrl(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        _config == null ||
        !_sdkState.enabled) {
      return;
    }
    if (_parseDectogUrl(uri) == null) {
      _log('Paste control: not a DecTog link, ignored');
      return;
    }
    if (!PasteboardGate.carriesClickTag(url)) {
      _log('Paste control: the link names no click, not sent');
      return;
    }
    unawaited(() async {
      final link = (url: url.trim(), mark: await _pasteboard.remember());
      await _claimClipboard(link, source: 'paste_control');
    }());
  }

  /// Launch-time follow-ups for an install registered by an EARLIER launch:
  /// re-read a referrer that was not definitive (Adjust re-reads every
  /// session until it is sent; bounded to five launches), fetch an
  /// AdServices token that was not ready (Branch retries per open).
  Future<void> _maybeLateClaim() async {
    final config = _config;
    if (config == null || _registeredThisProcess || !_sdkState.enabled) return;
    try {
      final state = _installState.current;
      if (state == null || state.status != InstallStatus.tracked) return;
      final installId = state.installId ?? _trackedInstallId;
      if (installId == null) return;

      if (Platform.isAndroid &&
          !state.referrerClaimed &&
          state.referrerLaunches < InstallStateStore.maxReferrerLaunches) {
        await _installState.bumpReferrerLaunches();
        final read = await _installReferrerService.read(
          timeout: config.installReferrerTimeout,
          oemStores: _oemStoreReferrers(config),
          provider: config.installReferrerProvider,
        );
        if (read.result.hasReferrer || read.result.isDefinitive) {
          await _claimReferrer(read.result);
        } else if (read.late != null) {
          unawaited(read.late!.then(_claimReferrer));
        }
      }

      if (Platform.isIOS &&
          config.collectsAppleSearchAdsToken &&
          !state.asaClaimed) {
        final token = await _guard(
          () => _identifierChannel.getAttributionToken(),
          timeout: _asaTimeout,
        );
        if (token != null) {
          try {
            await _claim(installId, {
              'claim_source': 'late_referrer',
              'asa_token': token,
            });
            await _installState.markAsaClaimed();
          } catch (e) {
            _log('AdServices token claim failed, will retry next launch: $e');
          }
        }
      }
    } catch (e) {
      _log('Late claim skipped: $e');
    }
  }

  @override
  Future<bool> willShowPasteboardPrompt({
    Set<DectogCollection>? collect,
  }) async {
    if (!Platform.isIOS) return false;
    final setting =
        collect != null
            ? collect.contains(DectogCollection.pasteboard)
            : _config?.pasteboardSetting;
    final enabled = DectogConfig.resolveReadClipboard(
      setting ?? _sdkConfig.config?.readClipboardOnInstall,
      isIOS: true,
    );
    if (!enabled) return false;
    // iOS 15 shows a passive "pasted from" banner, the alert is iOS 16+.
    if (iosMajorVersion(Platform.operatingSystemVersion) < 16) return false;
    try {
      final state = _installState.current ?? await _installState.load();
      if (state != null && state.status == InstallStatus.tracked) return false;
      return await _identifierChannel.pasteboardHasUrl().timeout(_auxTimeout);
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // Post-install telemetry: identify / conversion / custom
  // events, durable queue, opt-out, attribution re-pull.
  // ============================================================

  /// Resume the event queue (unless disabled) and send the init device
  /// ping (DAU/retention). Both best-effort.
  Future<void> _startTelemetry() async {
    try {
      // Restore the persisted install anchor for this launch.
      _lastInstallId ??= _sdkState.installId;
      // enabled was loaded from the persisted state file in _doInitialize.
      if (_sdkState.enabled) {
        _eventQueue.start(sender: _postEventsBatch);
        // Any events queued by a previous launch flush on the next tick.
        unawaited(_eventQueue.flush());
      }
      if (_config?.collectsDeviceTier == true && _sdkState.enabled) {
        unawaited(_sendDevicePing());
      }
    } catch (e) {
      _log('DecTog telemetry startup skipped: $e');
    }
  }

  /// Device id for telemetry, honoring the device tier: the install-flow
  /// cache first (no second channel read), else a fresh best-effort read.
  Future<String?> _deviceIdForTelemetry() async {
    final cached = _lastDeviceId;
    if (cached != null) return cached;
    if (_config?.collectsDeviceTier != true) return null;
    try {
      final id = await _deviceIdentityService.getDeviceId(
        persist: _config?.persistDeviceId == true,
      );
      if (id != null) _lastDeviceId = id;
      return id;
    } catch (_) {
      return null;
    }
  }

  /// Marks the device active today, for the server's retention read-outs.
  /// It keeps one row per device per UTC day, so the first ping of a day is
  /// sent and the rest are skipped. Fire-and-forget.
  Future<void> _sendDevicePing() async {
    if (!_sdkState.enabled) return;
    final today = _utcDay(DateTime.now());
    if (_sdkState.pingDay == today) return;
    try {
      final deviceId = await _deviceIdForTelemetry();
      if (deviceId == null) return;
      String? appVersion;
      try {
        appVersion = (await _getAppInfo()).version;
      } catch (_) {}
      final body = jsonEncode({
        'device_id': deviceId,
        if (appVersion != null) 'app_version': appVersion,
        'os': Platform.operatingSystem,
      });
      final response = await _httpClient
          .post(
            Uri.parse('${_config!.effectiveBaseUrl}/api/v1/device-ping'),
            headers: {
              ..._authHeaders(body),
              HttpHeaders.userAgentHeader: _sdkUserAgent,
            },
            body: body,
          )
          .timeout(_httpTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        await _sdkState.setPingDay(today);
      }
    } catch (_) {}
  }

  /// The UTC calendar day of [at], as the server counts device days.
  static String _utcDay(DateTime at) =>
      at.toUtc().toIso8601String().substring(0, 10);

  /// Queue sender: one batch to POST /api/v1/events. A 2xx removes the
  /// batch; a 4xx other than 401/408/429 drops it (it can never succeed and
  /// must not wedge the queue head); anything else keeps it
  /// for the next tick.
  Future<EventSendOutcome> _postEventsBatch(
    List<Map<String, Object?>> batch,
  ) async {
    try {
      final deviceId = await _deviceIdForTelemetry();
      final body = jsonEncode({
        if (deviceId != null) 'device_id': deviceId,
        if (_lastInstallId != null) 'install_id': _lastInstallId,
        'events': batch,
      });
      final response = await _httpClient
          .post(
            Uri.parse('${_config!.effectiveBaseUrl}/api/v1/events'),
            headers: {
              ..._authHeaders(body),
              HttpHeaders.userAgentHeader: _sdkUserAgent,
            },
            body: body,
          )
          .timeout(_httpTimeout);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // {accepted, duplicates, rejected: [{index, error}]}. Rejected
        // events never succeed on a resend, so the batch leaves the queue
        // either way; say why in debug builds.
        try {
          final result = jsonDecode(response.body);
          final rejected = result is Map ? result['rejected'] : null;
          if (rejected is List && rejected.isNotEmpty) {
            _log('Events rejected by the server: $rejected');
          }
          // The server no longer knows this install.
          if (result is Map && result['action'] == 'reregister') {
            unawaited(_recoverInstall());
          }
        } catch (_) {}
        return EventSendOutcome.sent;
      }
      if (shouldDropEventBatch(response.statusCode)) {
        _log(
          'Event batch rejected (${response.statusCode}), dropped: ${response.body}',
        );
        return EventSendOutcome.drop;
      }
      return EventSendOutcome.retry;
    } catch (_) {
      return EventSendOutcome.retry;
    }
  }

  /// Shared enqueue path: persist, and flush at the threshold. While
  /// collection is off the queue is stopped, so events wait on the device
  /// (up to the queue's 7-day limit) for setEnabled(true).
  Future<void> _enqueueEvent(Map<String, Object?> event) async {
    _ensureInitialized();
    final customerId = _sdkState.customerId;
    final lastOpen = _sdkState.lastOpen;
    await _eventQueue.enqueue({
      ...event,
      if (customerId != null && event['customer_id'] == null)
        'customer_id': customerId,
      // UTC with its Z: the server compares it with its own clock (to drop events queued before an erasure).
      'client_timestamp': DateTime.now().toUtc().toIso8601String(),
      // The re-engagement context and this process's session.
      if (lastOpen != null) ...{
        'open_slug': lastOpen.slug,
        if (lastOpen.clickId != null) 'open_click_id': lastOpen.clickId,
        'open_at': lastOpen.openedAt.toUtc().toIso8601String(),
      },
      'session_id': _sessionId,
    });
  }

  @override
  Future<void> identify({
    required String customerId,
    String? name,
    String? email,
    String? phone,
  }) async {
    _ensureInitialized();
    // Skip the event when the customer and fields match the last identify,
    // so apps can call this on every launch without duplicate rows.
    final identifyKey = jsonEncode([customerId, name, email, phone]);
    if (identifyKey == _sdkState.lastIdentify) return;
    await _sdkState.setCustomerId(
      customerId,
      identifyKey: _sdkState.enabled ? identifyKey : null,
    );
    await _enqueueEvent({
      'type': 'identify',
      'customer_id': customerId,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
    });
  }

  @override
  Future<void> trackConversion({
    required double revenue,
    String? currency,
    String? eventName,
    String? productId,
    String? transactionId,
    String? originalTransactionId,
    DectogStore? store,
    DectogPurchaseType? purchaseType,
    int? quantity,
    String? appStoreJws,
    DectogTransactionType transactionType = DectogTransactionType.purchase,
    Map<String, dynamic>? metadata,
  }) async {
    await _enqueueEvent({
      'type': 'conversion',
      'event_name':
          eventName ??
          (transactionType == DectogTransactionType.purchase
              ? 'purchase'
              : transactionType.wire),
      'revenue': revenue,
      if (currency != null) 'currency': currency,
      if (productId != null) 'product_id': productId,
      if (transactionId != null) 'transaction_id': transactionId,
      if (originalTransactionId != null)
        'original_transaction_id': originalTransactionId,
      if (store != null) 'store': store.wire,
      if (purchaseType != null) 'purchase_type': purchaseType.wire,
      if (quantity != null) 'quantity': quantity,
      if (appStoreJws != null) 'app_store_jws': appStoreJws,
      'transaction_type': transactionType.wire,
      if (metadata != null) 'metadata': metadata,
    });
  }

  @override
  Future<void> trackEvent(
    String eventName, {
    Map<String, dynamic>? data,
  }) async {
    await _enqueueEvent({
      'type': 'custom',
      'event_name': eventName,
      if (data != null) 'metadata': data,
    });
  }

  /// The last screen reported, sent as the next one's previous_screen.
  String? _lastScreen;

  @override
  Future<void> trackScreenView(
    String name, {
    Map<String, Object?>? params,
  }) async {
    var screen = name.trim();
    if (screen.isEmpty) {
      _log('trackScreenView: an empty screen name is not reported');
      return;
    }
    if (screen.length > maxScreenNameLength) {
      screen = screen.substring(0, maxScreenNameLength);
    }
    final kept = screenParams(params);
    final previous = _lastScreen;
    await _enqueueEvent({
      'type': 'screen_view',
      'event_name': screen,
      if (previous != null || kept != null)
        'metadata': {
          if (previous != null) 'previous_screen': previous,
          if (kept != null) 'params': kept,
        },
    });
    _lastScreen = screen;
  }

  @override
  Future<void> flush() async {
    _ensureInitialized();
    await _eventQueue.flush();
  }

  @override
  Future<void> logout() async {
    _ensureInitialized();
    await _eventQueue.flush();
    await _sdkState.setCustomerId(null);
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _ensureInitialized();
    final was = _sdkState.enabled;
    await _sdkState.setEnabled(enabled);
    if (!enabled) {
      // Stop sending; queued events stay on the device, held link
      // reports are dropped (a later consent must not report them).
      _consentGeneration++;
      _parkedLinks.clear();
      _eventQueue.stop();
      return;
    }
    if (was) return;
    _eventQueue.start(sender: _postEventsBatch);
    unawaited(_eventQueue.flush());
    unawaited(_loadSdkConfig());
    // A launch that started disabled never registered the install: do it now.
    unawaited(
      _trackAppInstallIfNeeded().catchError((Object e) {
        _log('Install registration after setEnabled(true) failed: $e');
      }),
    );
    unawaited(_replayParkedLinks());
    if (_config?.collectsDeviceTier == true) unawaited(_sendDevicePing());
  }

  @override
  Future<bool> isEnabled() async {
    _ensureInitialized();
    return _sdkState.enabled;
  }

  @override
  Future<DectogAppInstallResponse?> getAttributionData() async {
    _ensureInitialized();
    final cached = _appInstallSubject.valueOrNull;
    if (cached != null) return cached;
    // Collection off: no request.
    if (!_sdkState.enabled) return null;
    // By device when device data is on, else by the install id persisted
    // from the first-launch verdict.
    final deviceId = await _deviceIdForTelemetry();
    final installId = _trackedInstallId;
    final String query;
    if (deviceId != null) {
      query = 'device_id=${Uri.encodeQueryComponent(deviceId)}';
    } else if (installId != null) {
      query = 'install_id=${Uri.encodeQueryComponent(installId)}';
    } else {
      return null;
    }
    try {
      final json = await _api(
        'GET',
        '/api/v1/attribution?$query',
        failure: 'Failed to fetch attribution',
      );
      // organic installs are a 200 with matched:false —
      // the app can tell "organic" from "unknown".
      final verdict = DectogAppInstallResponse.fromJson(
        json as Map<String, dynamic>,
      );
      _lastInstallId ??= verdict.installId;
      unawaited(_sdkState.setInstallId(verdict.installId));
      return verdict;
    } on DectogError catch (e) {
      if (e.statusCode == 404) {
        // An install id the server lost: register again.
        if (e.code == 'install_not_found') unawaited(_recoverInstall());
        return null; // no install known for this device
      }
      rethrow;
    }
  }

  bool _recovering = false;

  /// The server answered `install_not_found` for the install id this
  /// SDK holds (a database restore, a retention purge, a build pointed at a
  /// fresh database). Reset the sentinel and register again with
  /// `recovered_from`; the server never fingerprints that registration.
  Future<void> _recoverInstall() async {
    final lost = _trackedInstallId;
    if (lost == null || _recovering || !_sdkState.enabled) return;
    _recovering = true;
    try {
      if (!await _installState.beginRecovery(lost)) return;
      _log('The server no longer knows install $lost - registering again');
      _lastInstallId = null;
      await _sdkState.setInstallId(null);
      _installTrackingFuture = null;
      await _trackAppInstallIfNeeded();
    } catch (e) {
      _log('Install recovery failed: $e');
    } finally {
      _recovering = false;
    }
  }

  @override
  /// Dispose resources
  Future<void> dispose() async {
    await _linkSubscription?.cancel();
    await _pasteControlSubscription?.cancel();
    _pasteControlSubscription = null;
    await _linkClickController.close();
    await _appInstallSubject.close();
    // Best-effort final flush, then stop the timer — queued events persist
    // on disk for the next launch.
    await _eventQueue.flush();
    _eventQueue.stop();
    _httpClient.close();
    _initialized = false;
    _config = null;
    _initFuture = null;
    _installTrackingFuture = null;
  }
}

/// What one install registration produced, plus the signals still in
/// flight when the POST left.
class _InstallOutcome {
  const _InstallOutcome({
    required this.response,
    required this.referrer,
    this.lateReferrer,
    this.lateClipboard,
    this.clipboard,
  });

  final DectogAppInstallResponse response;
  final ReferrerResult referrer;
  final Future<ReferrerResult>? lateReferrer;
  final Future<_PastedLink?>? lateClipboard;

  /// The pasteboard link that rode on the registration, with its read's
  /// mark (cleared only if the verdict credited it).
  final _PastedLink? clipboard;
}

/// A link read from the pasteboard, with the pasteboard's change
/// counter at that read: the mark only this read's verdict clears against.
typedef _PastedLink = ({String url, int? mark});

/// Parses a DecTog link URL into {username, slug}.
///
/// Supported forms (public so it is unit-testable):
///  - https://<username>.<linkRoot>/<slug>       production subdomain mode
///    (linkRoot defaults to the API host; set `linkRootDomain` when links
///    live on a different root than the API, e.g. API `app.example.com`
///    with links `{username}.example.com`)
///  - <baseHost>/r/<username>/<slug>             path mode (self-hosted)
///  - https://localhost:3000?user=<u>/<s>        development query mode
///  - <scheme>://<anything>?…dtg_l=<u>/<s>        custom scheme: every scheme
///    URI the server builds names its link in dtg_l, because with a deep-link
///    path the host and path are the app's own route (myapp://products/42)
///  - dectog://<username>/<slug>                 development scheme, untagged
Map<String, String>? parseDectogUrl(
  Uri uri,
  String baseUrl, {
  String? linkRootDomain,
  List<String> linkDomains = const [],
  String? username,
}) {
  final host = uri.host;
  final pathSegments = uri.pathSegments;

  // Development URL: localhost:3000?user=username/slug
  if (host.contains('localhost') && uri.queryParameters.containsKey('user')) {
    final userParam = uri.queryParameters['user']!;
    final parts = userParam.split('/');
    if (parts.length != 2) {
      return null;
    }
    return {'username': parts[0], 'slug': parts[1]};
  }

  // Custom scheme: the link is named by dtg_l, never by the URI's shape, so
  // an app's own route (myapp://products/42) is not mistaken for a link.
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    final tagged = uri.queryParameters['dtg_l'];
    if (tagged != null) return _parseLinkTag(tagged);
    // Development convenience only: dectog://username/slug, no tag.
    if (uri.scheme == 'dectog' && host.isNotEmpty && pathSegments.isNotEmpty) {
      return {'username': host, 'slug': pathSegments[0]};
    }
    return null;
  }

  final baseHost = Uri.parse(baseUrl).host;
  // Links may hang off a different root than the API (split deployment).
  final linkRoot =
      (linkRootDomain == null || linkRootDomain.isEmpty)
          ? baseHost
          : linkRootDomain;

  // The account's custom link domain: <domain>/<slug>, or the path
  // form <domain>/r/<username>/<slug>. The username is this key's own
  // account ('' until the server named it). Hosts that are the API host or
  // under the link root are not custom domains, whatever the list says.
  final custom = linkDomains
      .map((d) => d.trim().toLowerCase().replaceAll(RegExp(r'[.]+$'), ''))
      .where((d) => d.isNotEmpty && d != baseHost && !d.endsWith('.$linkRoot'));
  if (custom.contains(host.toLowerCase())) {
    if (pathSegments.length >= 3 && pathSegments.first == 'r') {
      return {'username': pathSegments[1], 'slug': pathSegments[2]};
    }
    if (pathSegments.isEmpty) return null;
    return {'username': username ?? '', 'slug': pathSegments[0]};
  }

  // Subdomain mode: username.<linkRoot>/slug
  if (host != baseHost && host.endsWith('.$linkRoot')) {
    final username = host.substring(0, host.length - linkRoot.length - 1);
    if (username.isEmpty || username.contains('.') || pathSegments.isEmpty) {
      return null;
    }
    return {'username': username, 'slug': pathSegments[0]};
  }

  // Path mode on the backend host: only the explicit /r/<u>/<s> form
  if (host == baseHost &&
      pathSegments.length >= 3 &&
      pathSegments.first == 'r') {
    return {'username': pathSegments[1], 'slug': pathSegments[2]};
  }

  return null;
}

final RegExp _linkTagRe = RegExp(
  r'^([A-Za-z0-9][A-Za-z0-9._-]*)/([A-Za-z0-9_-]{1,128})$',
);

/// `dtg_l=<username>/<slug>` (query-decoded, so `%2F` arrives as `/`).
Map<String, String>? _parseLinkTag(String value) {
  final m = _linkTagRe.firstMatch(value.trim());
  if (m == null) return null;
  return {'username': m.group(1)!, 'slug': m.group(2)!};
}

/// A link that arrived while collection was off: its click and open
/// wait for setEnabled(true) in the same consent generation.
class _ParkedLink {
  const _ParkedLink({
    required this.uri,
    required this.username,
    required this.slug,
    required this.clickId,
    required this.receivedAt,
    required this.inApp,
    required this.generation,
  });

  final Uri uri;
  final String username;
  final String slug;
  final String? clickId;
  final DateTime receivedAt;
  final bool inApp;
  final int generation;
}
