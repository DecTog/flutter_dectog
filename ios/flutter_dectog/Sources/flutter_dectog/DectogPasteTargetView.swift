import UIKit
import UniformTypeIdentifiers

/**
 * A system UIPasteControl (iOS 16+) wired to a callback, free of any
 * framework: the Flutter platform view and the React Native view both host
 * it (shared as source). The system button reads the
 * pasteboard WITHOUT the iOS 16 paste alert because the user tapped it, and
 * it only enables itself when the pasteboard holds a URL or text, which the
 * OS checks from metadata — no read, no prompt.
 *
 * On paste the URL (or text, ≤ 2048 characters) goes to `onPaste` on the
 * main thread; the SDK validates it as a DecTog link and files a late claim.
 * Nothing is validated or stored here.
 *
 * Options (all optional): displayMode "iconAndLabel" (default) | "iconOnly" |
 * "labelOnly"; cornerStyle "capsule" (default) | "dynamic" | "fixed" |
 * "large" | "medium" | "small"; backgroundColor and foregroundColor as
 * 0xAARRGGBB integers. `apply(options:)` rebuilds the control.
 *
 * A UIView (hence a UIResponder) so UIPasteControl's `target` gets a real
 * `UIPasteConfigurationSupporting`: the system calls `paste(itemProviders:)`
 * after the tap, with access already granted.
 */
@available(iOS 16.0, *)
final class DectogPasteTargetView: UIView {
  var onPaste: ((String) -> Void)?
  private var control: UIPasteControl?

  init(frame: CGRect, options: [String: Any]? = nil, onPaste: ((String) -> Void)? = nil) {
    self.onPaste = onPaste
    super.init(frame: frame)
    backgroundColor = .clear

    // Only URLs and plain text light the button up; images etc. keep it
    // disabled (the OS evaluates this from pasteboard metadata).
    pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
      UTType.url.identifier,
      UTType.text.identifier,
    ])
    apply(options: options)
  }

  required init?(coder: NSCoder) {
    return nil
  }

  /// (Re)build the control: its configuration is fixed at creation.
  func apply(options: [String: Any]?) {
    control?.removeFromSuperview()

    // UIPasteControl.Configuration is a class: mutate in place.
    let config = UIPasteControl.Configuration()
    config.displayMode = Self.displayMode(options?["displayMode"] as? String)
    config.cornerStyle = Self.cornerStyle(options?["cornerStyle"] as? String)
    if let bg = Self.color(options?["backgroundColor"]) { config.baseBackgroundColor = bg }
    if let fg = Self.color(options?["foregroundColor"]) { config.baseForegroundColor = fg }

    let control = UIPasteControl(configuration: config)
    control.target = self
    control.translatesAutoresizingMaskIntoConstraints = false
    addSubview(control)
    // Fill the frame the host gives; the host decides the footprint.
    NSLayoutConstraint.activate([
      control.leadingAnchor.constraint(equalTo: leadingAnchor),
      control.trailingAnchor.constraint(equalTo: trailingAnchor),
      control.topAnchor.constraint(equalTo: topAnchor),
      control.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
    self.control = control
  }

  // MARK: - UIPasteConfigurationSupporting

  override func paste(itemProviders: [NSItemProvider]) {
    // First URL wins; a plain-text item is the fallback (a copied link
    // that landed as text rather than a URL item).
    if let urlProvider = itemProviders.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }) {
      urlProvider.loadObject(ofClass: NSURL.self) { [weak self] object, _ in
        if let url = (object as? NSURL)?.absoluteString, !url.isEmpty {
          self?.deliver(url)
        } else {
          self?.loadText(itemProviders)
        }
      }
      return
    }
    loadText(itemProviders)
  }

  private func loadText(_ itemProviders: [NSItemProvider]) {
    guard let textProvider = itemProviders.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return }
    textProvider.loadObject(ofClass: NSString.self) { [weak self] object, _ in
      guard let text = (object as? NSString)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
      self?.deliver(text)
    }
  }

  private func deliver(_ value: String) {
    // Same ceiling as the pasteboard read: nothing pathological goes on.
    guard value.count <= DectogDevice.pasteboardMaxLength else { return }
    DispatchQueue.main.async { [weak self] in
      self?.onPaste?(value)
    }
  }

  // MARK: - Options

  private static func displayMode(_ raw: String?) -> UIPasteControl.DisplayMode {
    switch raw {
    case "iconOnly": return .iconOnly
    case "labelOnly": return .labelOnly
    default: return .iconAndLabel
    }
  }

  private static func cornerStyle(_ raw: String?) -> UIButton.Configuration.CornerStyle {
    switch raw {
    case "dynamic": return .dynamic
    case "fixed": return .fixed
    case "large": return .large
    case "medium": return .medium
    case "small": return .small
    default: return .capsule
    }
  }

  /// 0xAARRGGBB, as Flutter's Color.value and React Native's processColor
  /// encode a color.
  static func color(_ raw: Any?) -> UIColor? {
    let value: UInt32
    if let n = raw as? Int, n >= Int(Int32.min), n <= Int(UInt32.max) {
      // React Native's processColor can hand a negative Int32 for alpha ≥ 0x80.
      value = UInt32(truncatingIfNeeded: n)
    } else if let n = raw as? UInt32 {
      value = n
    } else if let n = raw as? NSNumber {
      value = UInt32(truncatingIfNeeded: n.int64Value)
    } else {
      return nil
    }
    let a = CGFloat((value >> 24) & 0xff) / 255
    let r = CGFloat((value >> 16) & 0xff) / 255
    let g = CGFloat((value >> 8) & 0xff) / 255
    let b = CGFloat(value & 0xff) / 255
    return UIColor(red: r, green: g, blue: b, alpha: a)
  }
}
