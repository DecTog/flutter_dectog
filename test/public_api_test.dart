// The public-API tripwire. It compiles only while FlutterAdto's
// surface is exactly what is written here:
//  - _Probe implements every member with the published signature, so a new
//    member or a new parameter on an existing one is a compile error;
//  - surface() takes each member at its exact function type, so a removed or
//    renamed parameter, or a changed type, is a compile error.
// flutter_adto is on pub.dev, so a change here changes the published API:
// a removed, renamed or retyped member is a breaking change and needs a major
// version.
// ignore_for_file: unused_local_variable

import 'package:flutter_adto/flutter_adto.dart';
import 'package:flutter_test/flutter_test.dart';

class _Probe implements FlutterAdto {
  Never get _no => throw UnimplementedError();

  @override
  Future<void> initialize(AdtoConfig config) => _no;
  @override
  Future<AdtoLink> createLink({
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
  Future<AdtoDiagnostics> diagnostics() => _no;
  @override
  Future<AdtoLink> createReferralLink({
    required String customerId,
    String? campaign,
  }) => _no;
  @override
  Future<AdtoLink> updateLink(
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
  Future<AdtoLinkPage> getLinks({int? limit, String? cursor}) => _no;
  @override
  Future<AdtoLink> getLink(String slug) => _no;
  @override
  Future<void> deleteLink(String slug, {bool permanently = false}) => _no;
  @override
  Future<AdtoTempLink> createTempLink({
    String? target,
    String? slug,
    int ttlSeconds = 900,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) => _no;
  @override
  Future<AdtoTempLink> updateTempLink(
    String slug, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  }) => _no;
  @override
  Future<AdtoTempLink> getTempLink(String slug) => _no;
  @override
  Future<void> deleteTempLink(String slug, {bool permanently = false}) => _no;
  @override
  Future<AdtoLinkResolution> resolveLink(String username, String slug) => _no;
  @override
  Stream<AdtoLinkClick> get onLinkClick => _no;
  @override
  Stream<AdtoAppInstallResponse> get onAppInstalled => _no;
  @override
  AdtoAppInstallResponse? get currentAppInstall => _no;
  @override
  Future<AdtoLinkClick?> getInitialLink() => _no;
  @override
  Future<AdtoLinkClick?> handleUrl(String url) => _no;
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
    AdtoStore? store,
    AdtoPurchaseType? purchaseType,
    int? quantity,
    String? appStoreJws,
    AdtoTransactionType transactionType = AdtoTransactionType.purchase,
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
  Future<AdtoAppInstallResponse?> getAttributionData() => _no;
  @override
  Future<bool> willShowPasteboardPrompt({Set<AdtoCollection>? collect}) => _no;
  @override
  Future<void> dispose() => _no;
}

/// Every AdtoConfig parameter by name: a removed or renamed one fails to compile.
const AdtoConfig everyConfigParameter = AdtoConfig(
  apiKey: 'adto_pub_0123456789abcdef0123456789abcdef',
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
  environment: AdtoEnvironment.test,
);

void surface(FlutterAdto d) {
  final Future<void> Function(AdtoConfig) initialize = d.initialize;
  final Future<AdtoLink> Function({
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
  final Future<AdtoLink> Function(
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
  final Future<AdtoLinkPage> Function({int? limit, String? cursor}) getLinks =
      d.getLinks;
  final Future<AdtoLink> Function(String) getLink = d.getLink;
  final Future<void> Function(String, {bool permanently}) deleteLink =
      d.deleteLink;
  final Future<AdtoTempLink> Function({
    String? target,
    String? slug,
    int ttlSeconds,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  })
  createTempLink = d.createTempLink;
  final Future<AdtoTempLink> Function(
    String, {
    String? target,
    String? ogTitle,
    String? ogDescription,
    String? ogImageUrl,
  })
  updateTempLink = d.updateTempLink;
  final Future<AdtoTempLink> Function(String) getTempLink = d.getTempLink;
  final Future<void> Function(String, {bool permanently}) deleteTempLink =
      d.deleteTempLink;
  final Future<AdtoLinkResolution> Function(String, String) resolveLink =
      d.resolveLink;
  final Stream<AdtoLinkClick> onLinkClick = d.onLinkClick;
  final Stream<AdtoAppInstallResponse> onAppInstalled = d.onAppInstalled;
  final AdtoAppInstallResponse? currentAppInstall = d.currentAppInstall;
  final Future<AdtoLinkClick?> Function() getInitialLink = d.getInitialLink;
  final Future<AdtoLinkClick?> Function(String) handleUrl = d.handleUrl;
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
    AdtoStore? store,
    AdtoPurchaseType? purchaseType,
    int? quantity,
    String? appStoreJws,
    AdtoTransactionType transactionType,
    Map<String, dynamic>? metadata,
  })
  trackConversion = d.trackConversion;
  final Future<AdtoDiagnostics> Function() diagnostics = d.diagnostics;
  final Future<AdtoLink> Function({
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
  final Future<AdtoAppInstallResponse?> Function() getAttributionData =
      d.getAttributionData;
  final Future<bool> Function({Set<AdtoCollection>? collect})
  willShowPasteboardPrompt = d.willShowPasteboardPrompt;
  final Future<void> Function() dispose = d.dispose;
}

void main() {
  test('the public FlutterAdto surface is the published one', () {
    // Compiling this file is the test; the probe only proves it ran.
    expect(_Probe(), isA<FlutterAdto>());
    expect(surface, isA<Function>());
  });
}
