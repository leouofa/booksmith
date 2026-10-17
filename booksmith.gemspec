# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'booksmith/version'

Gem::Specification.new do |spec|
  spec.name          = 'booksmith'
  spec.version       = Booksmith::VERSION
  spec.authors       = ['Leonid Medovyy']
  spec.email         = ['leonid@storypro.io']

  spec.summary       = 'A flexible Markdown-to-PDF and EPUB book publishing tool'
  spec.description   = 'Converts Markdown chapters into a styled PDF or EPUB book using Prawn, GEPUB, and Kramdown.'
  spec.homepage      = 'https://github.com/leouofa/booksmith'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir.chdir(__dir__) do
    Dir.glob('{bin,lib}/**/*').select { |f| File.file?(f) } +
      %w[LICENSE.txt README.md Rakefile Gemfile booksmith.gemspec].select { |f| File.file?(f) }
  end
  spec.bindir        = 'bin'
  spec.executables   = ['booksmith']
  spec.require_paths = ['lib']

  spec.add_dependency 'commander', '>= 4.6'
  spec.add_dependency 'gepub', '>= 1.0'
  spec.add_dependency 'kramdown', '>= 2.4'
  spec.add_dependency 'ostruct'
  spec.add_dependency 'prawn', '>= 2.4'

  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'rake', '>= 12.3.3'
end
