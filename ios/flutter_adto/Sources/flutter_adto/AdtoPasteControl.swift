import Flutter
import UIKit

/**
 * Platform view `adto_paste_control`: AdtoPasteTargetView (a system
 * UIPasteControl, iOS 16+) hosted in a Flutter widget — Branch's
 * BranchPasteControl pattern. On paste the URL (or text) is sent to Dart as
 * the method call `onPasteControlUrl` `{url}` on the
 * `adto_device_identifiers` channel; the Dart side validates it as a
 * AdTo link and files a late clipboard claim.
 *
 * creationParams (FlutterStandardMessageCodec map, all optional) are the
 * view's options: displayMode, cornerStyle, backgroundColor and
 * foregroundColor (0xAARRGGBB ints); see AdtoPasteTargetView.swift.
 *
 * Below iOS 16 the factory returns an empty view so the Flutter widget
 * tree never breaks; the Dart side hides the widget there.
 */
final class AdtoPasteControlFactory: NSObject, FlutterPlatformViewFactory {
  private let channel: FlutterMethodChannel

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    if #available(iOS 16.0, *) {
      return AdtoPasteControlPlatformView(frame: frame, arguments: args, channel: channel)
    }
    return AdtoEmptyPlatformView(frame: frame)
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    return FlutterStandardMessageCodec.sharedInstance()
  }
}

/// iOS < 16: nothing to show.
final class AdtoEmptyPlatformView: NSObject, FlutterPlatformView {
  private let empty: UIView

  init(frame: CGRect) {
    empty = UIView(frame: frame)
    empty.backgroundColor = .clear
    empty.isUserInteractionEnabled = false
    super.init()
  }

  func view() -> UIView { return empty }
}

@available(iOS 16.0, *)
final class AdtoPasteControlPlatformView: NSObject, FlutterPlatformView {
  private let container: AdtoPasteTargetView

  init(frame: CGRect, arguments: Any?, channel: FlutterMethodChannel) {
    container = AdtoPasteTargetView(frame: frame, options: arguments as? [String: Any]) { [weak channel] url in
      channel?.invokeMethod("onPasteControlUrl", arguments: ["url": url])
    }
    super.init()
  }

  func view() -> UIView { return container }
}
