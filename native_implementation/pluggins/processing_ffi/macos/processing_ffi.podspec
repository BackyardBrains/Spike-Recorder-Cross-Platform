#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint processing_ffi.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'processing_ffi'
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
  # Include all source files from Classes and src directories
  s.source_files = [
    'Classes/**/*.{h,cpp,c,m,mm}',
    '../src/**/*.{h,cpp,c}',
    '../src/internal/**/*.h'
  ]
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.14'
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) DART_SHARED_LIB=1',
    'OTHER_CFLAGS' => '$(inherited) -fvisibility=default',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -fvisibility=default',
    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '$(PODS_TARGET_SRCROOT)/../src',
      '$(PODS_TARGET_SRCROOT)/../src/internal',
      '$(PODS_TARGET_SRCROOT)/Classes',
      '$(PODS_TARGET_SRCROOT)/Classes/internal'
    ].join(' ')
  }
  s.swift_version = '5.0'
end
