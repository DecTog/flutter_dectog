// The public-API tripwire. It compiles only while FlutterDectog's
// surface is exactly what is written here:
//  - _Probe implements every member with the published signature, so a new
//    member or a new parameter on an existing one is a compile error;
//  - surface() takes each member at its exact function type, so a removed or
//    renamed parameter, or a changed type, is a compile error.
// Pre-release, change this file freely with the API. After the first pub.dev
// release, a change here is a breaking change and needs a major version.
// ignore_for_file: unused_local_variable

import 'package:flutter_dectog/flutter_dectog.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe implements FlutterDectog {
  Never get _no => throw UnimplementedError();

  @override
  Future<void> initialize(DectogConfig config) => _no;
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
  }) => _no;
  @override
  Future<DectogDiagnostics> diagnostics() => _no;
  @override
  Future<DectogLink> createReferralLink({
    required String customerId,
    String? campaign,
  }) => _no;
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
  }) => _no;
  @override
  Future<DectogLinkPage> getLinks({int? limit, String? cursor}) => _no;
  @override
  Future<DectogLink> getLink(String slug) => _no;
  @override
  Future<void> deleteLink(String slug, {bool permanently = false}) => _no;
  @override
  Future<DectogTempLink> createTempLink({
    String? target,
    String? slug,
    int ttlSeconds = 900,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) => _no;
  @override
  Future<DectogTempLink> updateTempLink(
    String slug, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) => _no;
  @override
  Future<DectogTempLink> getTempLink(String slug) => _no;
  @override
  Future<void> deleteTempLink(String slug, {bool permanently = false}) => _no;
  @override
  Future<DectogLinkResolution> resolveLink(String username, String slug) => _no;
  @override
  Stream<DectogLinkClick> get onLinkClick => _no;
  @override
  Stream<DectogAppInstallResponse> get onAppInstalled => _no;
  @override
  DectogAppInstallResponse? get currentAppInstall => _no;
  @override
  Future<DectogLinkClick?> getInitialLink() => _no;
  @override
  Future<DectogLinkClick?> handleUrl(String url) => _no;
  @override
  Future<void> identify({
    required String customerId,
    String? name,
    String? email,
    String? phone,
  }) => _no;
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
  }) => _no;
  @override
  Future<void> trackEvent(String eventName, {Map<String, dynamic>? data}) =>
      _no;
  @override
  Future<void> trackScreenView(String name, {Map<String, Object?>? params}) =>
      _no;
  @override
  Future<void> flush() => _no;
  @override
  Future<void> logout() => _no;
  @override
  Future<void> setEnabled(bool enabled) => _no;
  @override
  Future<bool> isEnabled() => _no;
  @override
  Future<DectogAppInstallResponse?> getAttributionData() => _no;
  @override
  Future<bool> willShowPasteboardPrompt({Set<DectogCollection>? collect}) =>
      _no;
  @override
  Future<void> dispose() => _no;
}

/// Every DectogConfig parameter by name: a removed or renamed one fails to compile.
const DectogConfig everyConfigParameter = DectogConfig(
  apiKey: 'dtg_pub_0123456789abcdef0123456789abcdef',
  baseUrl: null,
  linkRootDomain: null,
  linkDomains: [],
  enableDebugLogging: false,
  installReferrerProvider: null,
  installReferrerTimeout: Duration(seconds: 5),
  collect: null,
  advertisingIdProvider: null,
  fbAppId: null,
  persistDeviceId: true,
  enabled: true,
  environment: DectogEnvironment.test,
);

void surface(FlutterDectog d) {
  final Future<void> Function(DectogConfig) initialize = d.initialize;
  final Future<DectogLink> Function({
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
  })
  createLink = d.createLink;
  final Future<DectogLink> Function(
    String, {
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
  })
  updateLink = d.updateLink;
  final Future<DectogLinkPage> Function({int? limit, String? cursor}) getLinks =
      d.getLinks;
  final Future<DectogLink> Function(String) getLink = d.getLink;
  final Future<void> Function(String, {bool permanently}) deleteLink =
      d.deleteLink;
  final Future<DectogTempLink> Function({
    String? target,
    String? slug,
    int ttlSeconds,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  })
  createTempLink = d.createTempLink;
  final Future<DectogTempLink> Function(
    String, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  })
  updateTempLink = d.updateTempLink;
  final Future<DectogTempLink> Function(String) getTempLink = d.getTempLink;
  final Future<void> Function(String, {bool permanently}) deleteTempLink =
      d.deleteTempLink;
  final Future<DectogLinkResolution> Function(String, String) resolveLink =
      d.resolveLink;
  final Stream<DectogLinkClick> onLinkClick = d.onLinkClick;
  final Stream<DectogAppInstallResponse> onAppInstalled = d.onAppInstalled;
  final DectogAppInstallResponse? currentAppInstall = d.currentAppInstall;
  final Future<DectogLinkClick?> Function() getInitialLink = d.getInitialLink;
  final Future<DectogLinkClick?> Function(String) handleUrl = d.handleUrl;
  final Future<void> Function({
    required String customerId,
    String? name,
    String? email,
    String? phone,
  })
  identify = d.identify;
  final Future<void> Function({
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
    DectogTransactionType transactionType,
    Map<String, dynamic>? metadata,
  })
  trackConversion = d.trackConversion;
  final Future<DectogDiagnostics> Function() diagnostics = d.diagnostics;
  final Future<DectogLink> Function({
    required String customerId,
    String? campaign,
  })
  createReferralLink = d.createReferralLink;
  final Future<void> Function(String, {Map<String, dynamic>? data}) trackEvent =
      d.trackEvent;
  final Future<void> Function(String, {Map<String, Object?>? params})
  trackScreenView = d.trackScreenView;
  final Future<void> Function() flush = d.flush;
  final Future<void> Function() logout = d.logout;
  final Future<void> Function(bool) setEnabled = d.setEnabled;
  final Future<bool> Function() isEnabled = d.isEnabled;
  final Future<DectogAppInstallResponse?> Function() getAttributionData =
      d.getAttributionData;
  final Future<bool> Function({Set<DectogCollection>? collect})
  willShowPasteboardPrompt = d.willShowPasteboardPrompt;
  final Future<void> Function() dispose = d.dispose;
}

void main() {
  test('the public FlutterDectog surface is the published one', () {
    // Compiling this file is the test; the probe only proves it ran.
    expect(_Probe(), isA<FlutterDectog>());
    expect(surface, isA<Function>());
  });
}
