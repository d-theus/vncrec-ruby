# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vncrec/version'

Gem::Specification.new do |spec|
  spec.name          = 'vncrec'
  spec.version       = VNCRec::VERSION
  spec.authors       = ['d-theus']
  spec.email         = ['slma0x02@gmail.com']
  spec.summary       = 'VNC session recording'
  spec.description   = 'Connect to/receive reverse-connect
  from VNC server and record session as raw video or any video
  format FFmpeg supports'
  spec.homepage      = ""
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.extensions = 'ext/enchex_c/extconf.rb'

  spec.add_development_dependency 'bundler', '~> 1.7'
  spec.add_development_dependency 'rake', '~> 10.0'
  spec.add_development_dependency 'rake-compiler'
  spec.add_development_dependency 'rspec'
  spec.add_development_dependency 'rspec-its'
  spec.add_development_dependency 'activesupport'

  spec.requirements << 'ffmpeg'
  spec.requirements << 'x11vnc'
end
