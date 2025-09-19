# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "huginn_yandex_gpt_agent"
  spec.version       = '0.3'
  spec.authors       = ["Black Roland"]
  spec.email         = ["mail@roland.black"]

  spec.summary       = %q{Huginn agent for YandexGPT API}
  spec.description   = %q{Agent for Huginn that interacts with YandexGPT API asynchronously}

  spec.homepage      = "https://github.com/black-roland/huginn-yandexgpt-agent"
  spec.license       = "MPL-2.0"

  spec.files         = Dir['LICENSE', 'lib/**/*']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = Dir['spec/**/*.rb'].reject { |f| f[%r{^spec/huginn}] }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 2.1.0"
  spec.add_development_dependency "rake", "~> 12.3.3"

  spec.add_runtime_dependency "huginn_agent"
end
