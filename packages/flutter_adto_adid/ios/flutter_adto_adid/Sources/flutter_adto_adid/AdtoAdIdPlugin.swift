import AdSupport
import AppTrackingTransparency
import Flutter
import UIKit

/**
 * The IDFA for flutter_adto (`adto_adid` channel).
 *
 *  - getAdvertisingId -> { id, limited }: the IDFA only once ATT is
 *      authorized; otherwise { limited: true } and no id.
 *  - trackingStatus -> the ATT status name, without prompting.
 *  - requestTracking -> shows the ATT prompt when the status is still
 *      notDetermined, then answers the status. Needs
 *      NSUserTrackingUsageDescription in the host's Info.plist.
 */
public class AdtoAdIdPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "adto_adid", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AdtoAdIdPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getAdvertisingId":
      result(Self.advertisingId())
    case "trackingStatus":
      result(Self.name(of: ATTrackingManager.trackingAuthorizationStatus))
    case "requestTracking":
      guard Bundle.main.object(forInfoDictionaryKey: "NSUserTrackingUsageDescription") != nil else {
        // iOS terminates an app that asks without the usage string.
        result(Self.name(of: ATTrackingManager.trackingAuthorizationStatus))
        return
      }
      ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async { result(Self.name(of: status)) }
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  static func advertisingId() -> [String: Any] {
    guard ATTrackingManager.trackingAuthorizationStatus == .authorized else {
      return ["limited": true]
    }
    let id = ASIdentifierManager.shared().advertisingIdentifier.uuidString
    return ["id": id, "limited": false]
  }

  static func name(of status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .authorized: return "authorized"
    @unknown default: return "notSupported"
    }
  }
}
