Pod::Spec.new do |s|
  s.name = 'thmr_mp3'
  s.version = '1.0.0'
  s.summary = 'THMR radio stream MP3 decoder'
  s.homepage = 'https://github.com/Yunmoan/thmr-app'
  s.author = 'THMR'
  s.license = { :type => 'CC0-1.0', :file => 'vendor/minimp3/LICENSE' }
  s.source = { :path => '.' }
  s.source_files = 'mp3_decoder.cc', 'vendor/minimp3/minimp3.h'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.pod_target_xcconfig = {
    'HEADER_SEARCH_PATHS' => '$(inherited) "$(PODS_TARGET_SRCROOT)/vendor/minimp3"',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'DEFINES_MODULE' => 'YES'
  }
end
