#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint byb_accessory.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'byb_accessory'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = [
    'Classes/BybAccessoryPlugin.{h,m,mm}',
    'Classes/SpikeRecorder/Audio/*.{h,m,mm}',
    'Classes/SpikeRecorder/Audio/wav/*.{h,m,mm}',
    'Classes/SpikeRecorder/accessory/*.{h,m,mm}',
    'Classes/SpikeRecorder/Model/BB*.{h,m,mm}',
    'Classes/SpikeRecorder/Model/BoardsConfigManager.{h,m}',
    'Classes/SpikeRecorder/Model/ChannelConfig.{h,m}',
    'Classes/SpikeRecorder/Model/ExpansionBoardConfig.{h,m}',
    'Classes/SpikeRecorder/Model/FilterSettings.{h,m}',
    'Classes/SpikeRecorder/Model/InputDevice*.{h,m}',
    'Classes/SpikeRecorder/libs/Novocaine/*.{h,m,mm}',
    'Classes/SpikeRecorder/libs/NVDSP/**/*.{h,m,mm}',
    'Classes/SpikeRecorder/libs/SQLitePersistence/*.{h,m,mm}',
    'Classes/SpikeRecorder/libs/xml/*.{h,m,mm}',
    'Classes/SpikeRecorder/libs/Zip/*.{h,m,mm,c,cpp}',
    'Classes/SpikeRecorder/libs/Zip/minizip/*.{h,m,mm,c,cpp}',
    'Classes/SpikeRecorder/Shims/*.{h,m,mm}'
  ]
  s.exclude_files = 'vendor/**/*'
  s.public_header_files = 'Classes/BybAccessoryPlugin.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.requires_arc = false
  s.frameworks = ['ExternalAccessory', 'AVFoundation', 'AudioToolbox', 'CoreAudio', 'QuartzCore', 'Accelerate']
  s.libraries = 'sqlite3', 'c++', 'z'
  s.resource_bundles = { 'byb_accessory_assets' => ['Resources/board-config.json'] }

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/Audio" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/Audio/wav" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/Model" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/accessory" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/Novocaine" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/NVDSP" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/NVDSP/Filters" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/SQLitePersistence" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/xml" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/Zip" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/libs/Zip/minizip" "$(PODS_TARGET_SRCROOT)/Classes/SpikeRecorder/Shims"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++14',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_LDFLAGS' => '$(inherited) -lc++'
  }
  s.user_target_xcconfig = {
    'OTHER_LDFLAGS' => '$(inherited) -lc++'
  }

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'byb_accessory_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
