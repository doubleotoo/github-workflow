# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require File.expand_path('../lib/github_flow/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = 'github_flow'
  gem.authors       = [ 'Justin Too' ]
  gem.email         = 'doubleotoo@gmail.com'
  gem.homepage      = 'https://github.com/doubleotoo/github-flow'
  gem.summary       = %q{ Ruby wrapper to automate a GitHub workflow (using the GitHub API v3)}
  gem.description   = %q{ need to add description }
  gem.version       = GithubFlow::VERSION::STRING.dup

  gem.files = Dir['Rakefile', '{lib/scripts}/**/*', 'README*', 'LICENSE*']
  gem.require_paths = %w[ lib ]

  gem.add_dependency 'github_api', '~> 0.4'

  gem.add_development_dependency 'guard', '~> 0.8.8'
  gem.add_development_dependency 'guard-rspec', '0.5.7'
  gem.add_development_dependency 'guard-cucumber', '0.7.4'
  gem.add_development_dependency 'rake'
  gem.add_development_dependency 'bundler'
end
