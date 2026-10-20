Pod::Spec.new do |s|
  s.name             = 'flutter_dectog'
  s.version         = '1.0.0'
  s.summary          = 'Device identifier, install-state and pasteboard channel for the DecTog Flutter SDK.'
  s.description      = <<-DESC
  First-party device identifier (plain IDFV), install/update/reinstall
  dates, backup exclusion, pasteboard reads, the UIPasteControl platform
  view and the Apple Search Ads attribution token for flutter_dectog. It
  reads no advertising identifier and links neither AdSupport nor
  AppTrackingTransparency.
                       DESC
  s.homepage         = 'https://dectog.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'DecTog' => 'support@dectog.com' }
  s.source           = { :path => '.' }
  # Sources live in the Swift package (ios/flutter_dectog); CocoaPods
  # builds the same files for hosts that disabled Swift Package Manager.
  s.source_files     = 'flutter_dectog/Sources/flutter_dectog/**/*.swift'
  s.dependency 'Flutter'

  # Apple Search Ads attribution token (AAAttribution, iOS 14.3+). Weak so
  # the symbol is resolved lazily; the Swift side guards with canImport +
  # #available and returns nil on the simulator.
  s.weak_frameworks  = 'AdServices'

  # Apple privacy manifest (required for third-party SDKs): shipped as a
  # resource bundle so it lands in the host app. Without this the file sits
  # unbundled in the repo and App Store submission has nothing to read.
  s.resource_bundles   = {'flutter_dectog_privacy' => ['flutter_dectog/Sources/flutter_dectog/PrivacyInfo.xcprivacy']}

  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
