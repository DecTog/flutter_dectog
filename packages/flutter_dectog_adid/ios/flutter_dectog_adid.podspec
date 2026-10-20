Pod::Spec.new do |s|
  s.name             = 'flutter_dectog_adid'
  s.version          = '1.0.0'
  s.summary          = 'The IDFA (after App Tracking Transparency) for the DecTog Flutter SDK.'
  s.description      = <<-DESC
  Reads the advertising identifier once App Tracking Transparency allows it
  and asks for that permission on request. The only DecTog package that
  links AdSupport and AppTrackingTransparency.
                       DESC
  s.homepage         = 'https://dectog.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'DecTog' => 'support@dectog.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'flutter_dectog_adid/Sources/flutter_dectog_adid/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks       = 'AdSupport', 'AppTrackingTransparency'
  s.resource_bundles = {'flutter_dectog_adid_privacy' => ['flutter_dectog_adid/Sources/flutter_dectog_adid/PrivacyInfo.xcprivacy']}
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
end
