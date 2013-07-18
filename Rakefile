#!/usr/bin/env rake
require "bundler/gem_tasks"

task :default => :test

task :test do
  sh 'test/test.sh'
end

task :tarball do
  gemspec = Bundler::GemHelper.gemspec
  sh <<-'EOF' % [gemspec.name, gemspec.version.to_s]
git archive --format=tar --prefix=%1$s-%2$s/ v%2$s | bzip2 -9c > %1$s-%2$s.tar.bz2
  EOF
end
