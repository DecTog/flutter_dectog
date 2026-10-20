import 'package:connectivity_plus/connectivity_plus.dart';

import 'identifier_channel.dart';

/// Network / carrier tier: connectivity type via connectivity_plus and
/// carrier MCC/MNC via the identifier channel (Android only — iOS hides
/// carrier identity, which is exactly Adjust's behaviour too).
class NetworkService {
  NetworkService._internal();
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  final Connectivity _connectivity = Connectivity();
  final IdentifierChannel _identifiers = IdentifierChannel();

  /// Lowercase transport of the active network, e.g. 'wifi' or 'cellular'.
  /// Null when the platform reports nothing usable (desktop, no permission).
  Future<String?> getConnectivityType() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return results.isEmpty ? null : 'none';
      }
      // Report the most specific transport: cellular beats wifi beats the rest.
      if (results.contains(ConnectivityResult.mobile)) return 'cellular';
      if (results.contains(ConnectivityResult.wifi)) return 'wifi';
      if (results.contains(ConnectivityResult.ethernet)) return 'ethernet';
      if (results.contains(ConnectivityResult.vpn)) return 'vpn';
      if (results.contains(ConnectivityResult.bluetooth)) return 'bluetooth';
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<CarrierInfo?> getCarrierInfo() => _identifiers.getCarrierInfo();
}
