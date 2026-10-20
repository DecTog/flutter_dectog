import Flutter
import UIKit

/**
 * The SDK's only authored platform channel (`dectog_device_identifiers`).
 * Every read lives in the framework-free DectogDevice, DectogKeychain,
 * DectogInstallDates and DectogPasteTargetView files, shared as source with
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
 *  - Platform view `dectog_paste_control` (UIPasteControl, iOS 16+), which
 *    delivers `onPasteControlUrl { url }` from native to Dart on this channel.
 *
 * Unknown methods answer FlutterMethodNotImplemented so an older Dart side
 * keeps working.
 */

@objc(DectogIdentifiersPlugin)
public class DectogIdentifiersPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "dectog_device_identifiers",
      binaryMessenger: registrar.messenger())
    let instance = DectogIdentifiersPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.register(DectogPasteControlFactory(channel: channel), withId: "dectog_paste_control")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "getDeviceId":
      result(DectogDevice.deviceId(persist: args?["persist"] as? Bool ?? false))
    case "getCarrierInfo", "getWebViewUserAgent", "getMetaReferrer":
      result(nil)
    case "getInstallDates":
      result(DectogDevice.installDates())
    case "excludeFromBackup":
      result(DectogDevice.excludeFromBackup(args?["path"] as? String))
    case "getAttributionToken":
      DectogDevice.attributionToken { result($0) }
    case "pasteboardHasUrl":
      result(DectogDevice.pasteboardHasUrl())
    case "readPasteboardUrl":
      result(DectogDevice.readPasteboardUrl())
    case "clearPasteboard":
      result(DectogDevice.clearPasteboard())
    case "getUrlSchemes":
      result(DectogDevice.urlSchemes())
    case "pasteboardChangeCount":
      result(DectogDevice.pasteboardChangeCount())
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
