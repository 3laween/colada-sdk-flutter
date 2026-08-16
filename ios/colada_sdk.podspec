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
  # Same sources the Swift Package Manager manifest compiles — see
  # colada_sdk/Package.swift. Both packaging formats must stay in step.
  s.source_files     = 'colada_sdk/Sources/colada_sdk/**/*.swift'
  s.dependency 'Flutter'
  # The native Colada iOS SDK. A BINARY pod: its own podspec has an :http source
  # pointing at Colada.xcframework.zip, so nothing is compiled from source here.
  #
  # Pinned exactly, and it must stay in lockstep with the version in
  # colada_sdk/Package.swift — an app resolving this plugin through Swift Package
  # Manager reads that file instead of this one, and two different native
  # versions across the two packaging formats is a bug nobody would think to
  # look for. Loosen to '~> 0.1' only once a second native version exists and
  # compatibility has actually been proven.
  s.dependency 'Colada', '0.1.1'
  s.platform = :ios, '13.0'
  s.swift_version = '5.9'
  # Flutter plugin convention; also required so the binary Colada pod links
  # cleanly under use_frameworks!.
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
