import Flutter
import UIKit

/**
 * The SDK's only authored platform channel (`adto_device_identifiers`).
 * Every read lives in the framework-free AdtoDevice, AdtoKeychain,
 * AdtoInstallDates and AdtoPasteTargetView files, shared as source with
 * the React Native SDK; this class only maps channel calls onto them:
 *
 *  - getDeviceId({ persist }) -> String | null
 *  - getCarrierInfo / getWebViewUserAgent / getMetaReferrer -> nil (no
 *    iOS source; Android-only signals)
 *  - getInstallDates -> { executableCtime?, libraryCtime?, documentsCtime?,
 *    keychainFirstInstall?, keychainLatestInstall? } (epoch ms)
 *  - excludeFromBackup({ path }) -> Bool
 *  - getAttributionToken -> String | null (AdServices)
 *  - pasteboardHasUrl -> Bool (no alert) · readPasteboardUrl -> String |
 *    null (iOS 16+ alert) · pasteboardChangeCount -> Int · clearPasteboard
 *    -> Bool
 *  - getUrlSchemes -> [String]
 *  - Platform view `adto_paste_control` (UIPasteControl, iOS 16+), which
 *    delivers `onPasteControlUrl { url }` from native to Dart on this channel.
 *
 * Unknown methods answer FlutterMethodNotImplemented so an older Dart side
 * keeps working.
 */

@objc(AdtoIdentifiersPlugin)
public class AdtoIdentifiersPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "adto_device_identifiers",
      binaryMessenger: registrar.messenger())
    let instance = AdtoIdentifiersPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(AdtoPasteControlFactory(channel: channel), withId: "adto_paste_control")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getDeviceId":
      result(AdtoDevice.deviceId(persist: args?["persist"] as? Bool ?? false))
    case "getCarrierInfo", "getWebViewUserAgent", "getMetaReferrer":
      result(nil)
    case "getInstallDates":
      result(AdtoDevice.installDates())
    case "excludeFromBackup":
      result(AdtoDevice.excludeFromBackup(args?["path"] as? String))
    case "getAttributionToken":
      AdtoDevice.attributionToken { result($0) }
    case "pasteboardHasUrl":
      result(AdtoDevice.pasteboardHasUrl())
    case "readPasteboardUrl":
      result(AdtoDevice.readPasteboardUrl())
    case "clearPasteboard":
      result(AdtoDevice.clearPasteboard())
    case "getUrlSchemes":
      result(AdtoDevice.urlSchemes())
    case "pasteboardChangeCount":
      result(AdtoDevice.pasteboardChangeCount())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
