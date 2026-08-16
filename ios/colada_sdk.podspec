#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint colada_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'colada_sdk'
  s.version          = '0.1.1'
  s.summary          = 'Flutter SDK for Colada mobile attribution and event tracking.'
  s.description      = <<-DESC
A Flutter bridge over the native Colada iOS SDK for mobile attribution and event tracking.
                       DESC
  s.homepage         = 'https://github.com/3laween/colada-sdk-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Colada' => 'engineering@coladaapp.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.9'
  # Flutter plugin convention; also required so the binary Colada pod (added in
  # Phase 9) links cleanly under use_frameworks!.
  s.static_framework = true

  # The native Colada pod ('Colada', 0.1.1) is added in Phase 9.

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
