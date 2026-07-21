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
  s.source           = { :path => '.' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` and then this podspec's `source_files` path is set to `Classes/`.
  s.source_files = 'Classes/src/**/*.{h,m,mm,c,cpp,hpp}'
  s.public_header_files = 'Classes/src/nwbfile_plugin.h'

  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter FFI plugin does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) AQNWB_CXX_STANDARD=17',
    'USE_HEADERMAP' => 'NO',
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes" "$(PODS_TARGET_SRCROOT)/Classes/src" "$(PODS_TARGET_SRCROOT)/Classes/include"',
    'USER_HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/Classes/src" "$(PODS_TARGET_SRCROOT)/Classes/include"',
    'OTHER_CFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/src" -I"$(PODS_TARGET_SRCROOT)/Classes/include"',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -I"$(PODS_TARGET_SRCROOT)/Classes/src" -I"$(PODS_TARGET_SRCROOT)/Classes/include"',
    'OTHER_LDFLAGS' => '$(inherited) -all_load',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }

  
  # Add vendored libraries
  s.vendored_libraries = 'Classes/lib/libhdf5.a', 'Classes/lib/libhdf5_cpp.a'
  s.libraries = 'c++', 'stdc++', 'z', 'dl'
end
