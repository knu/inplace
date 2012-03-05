# -*- encoding: utf-8 -*-
require File.expand_path('../lib/inplace/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Akinori MUSHA"]
  gem.email         = ["knu@idaemons.org"]
  gem.description   = %q{A command line utility that edits files in-place through given filter commands}
  gem.summary       = <<-'EOS'
Inplace(1) is a command line utility that edits files in-place through
given filter commands.  e.g. inplace 'sort' file1 file2 file3
  EOS
  gem.homepage      = "https://github.com/knu/inplace"

  gem.files         = `git ls-files`.split("\n")
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "inplace"
  gem.require_paths = ["lib"]
  gem.version       = Inplace::VERSION
end
