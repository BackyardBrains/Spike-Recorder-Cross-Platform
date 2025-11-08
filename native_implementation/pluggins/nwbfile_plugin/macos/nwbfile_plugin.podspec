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
  
  # BOOST
  # s.source_files = 'Classes/**/*.{h,m,mm,cpp}', 'src/**/*.{h,cpp}'
  s.source_files = 'Classes/**/*.{h,m,mm,cpp}'
  s.public_header_files = 'Classes/**/*.{h,hpp}'
  
  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17', # Use a modern C++ standard
    'CLANG_CXX_LIBRARY' => 'libc++',          # Use the libc++ standard library
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    # BOOST2
    # 'HEADER_SEARCH_PATHS' => '$(inherited) $(POD_TARGET_SRCROOT)/Classes/src $(POD_TARGET_SRCROOT)/Classes/src/include $(PODS_ROOT)/boost'
    # 'HEADER_SEARCH_PATHS' => '$(inherited) $(POD_TARGET_SRCROOT)/Classes/src $(POD_TARGET_SRCROOT)/Classes/src/include $(PODS_ROOT)/boost'
    'HEADER_SEARCH_PATHS' => '$(inherited) $(POD_TARGET_SRCROOT)/Classes $(POD_TARGET_SRCROOT)/Classes/src $(POD_TARGET_SRCROOT)/Classes/boost $(POD_TARGET_SRCROOT)/Classes/include $(POD_TARGET_SRCROOT)/Classes /opt/homebrew/opt/boost/include $(POD_TARGET_SRCROOT)/Classes/boost',
    'LIBRARY_SEARCH_PATHS' => '$(inherited) /opt/homebrew/opt/boost/lib $(POD_TARGET_SRCROOT)/Classes/lib',
    'OTHER_LDFLAGS' => '$(inherited) -Wl,-all_load'
  }
  # BOOST  
  s.vendored_libraries = 'Classes/lib/libhdf5.a', 'Classes/lib/libhdf5_cpp.a'
  # s.vendored_frameworks = 'Classes/lib/libhdf5.dylib Classes/lib/libhdf5_cpp.dylib'

  s.library = 'c++'
  s.library = 'boost_system'
  s.library = 'boost_date_time'
  s.library = 'z'
  s.library = 'dl'
  # s.library = 'c++'
  # s.library = 'boost_system'
  # s.library = 'boost_date_time'
  # s.library = 'z'
  # s.library = 'dl'

  
  # s.library = 'hdf5'
  # s.library = 'hdf5_cpp'

  # target_link_libraries(nwbfile_plugin PRIVATE Classes/src/lib/libhdf5.a)
    
end
