Pod::Spec.new do |s|
  s.name             = 'flutter_adto_adid'
  s.version          = '1.0.0'
  s.summary          = 'The IDFA (after App Tracking Transparency) for the AdTo Flutter SDK.'
  s.description      = <<-DESC
  Reads the advertising identifier once App Tracking Transparency allows it
  and asks for that permission on request. The only AdTo package that
  links AdSupport and AppTrackingTransparency.
                       DESC
  s.homepage         = 'https://adto.app'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AdTo' => 'support@adto.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_adto_adid/Sources/flutter_adto_adid/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks       = 'AdSupport', 'AppTrackingTransparency'
  s.resource_bundles = {'flutter_adto_adid_privacy' => ['flutter_adto_adid/Sources/flutter_adto_adid/PrivacyInfo.xcprivacy']}
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
