#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint nwbfile_plugin.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'nwbfile_plugin'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter FFI plugin project.'
  s.description      = <<-DESC
A new Flutter FFI plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  # s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  # s.dependency 'boost'
  # s.dependency 'boost', :path => 'Classes/boost'
  # s.dependency 'boost-iosx'
  # s.dependency 'boost-iosx', :git => 'https://github.com/apotocki/boost-iosx'

  s.platform = :osx, '10.15'
  # s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
  
  # AqNWB 0.4.0 sources (Boost no longer required).
  # Only expose the FFI C header publicly to avoid CocoaPods flattening AqNWB paths.
  s.source_files = 'Classes/**/*.{h,m,mm,cpp,hpp}'
  s.public_header_files = 'Classes/src/nwbfile_plugin.h'

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) AQNWB_CXX_STANDARD=17',
    # CocoaPods defines PODS_TARGET_SRCROOT (not POD_TARGET_SRCROOT).
    # Disable header maps — they break quoted includes like "Types.hpp" / "nwb/...".
    'USE_HEADERMAP' => 'NO',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes" "$(PODS_TARGET_SRCROOT)/Classes/src" "$(PODS_TARGET_SRCROOT)/Classes/include"',
    'USER_HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes/src" "$(PODS_TARGET_SRCROOT)/Classes/include"',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes/lib"',
    'OTHER_CFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/src" -I"$(PODS_TARGET_SRCROOT)/Classes/include"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/src" -I"$(PODS_TARGET_SRCROOT)/Classes/include"',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-all_load'
  }

  s.vendored_libraries = 'Classes/lib/libhdf5.a', 'Classes/lib/libhdf5_cpp.a'

  s.library = 'c++'
  s.library = 'z'
  s.library = 'dl'
end
