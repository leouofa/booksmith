require 'commander'
require 'prawn'
require 'kramdown'
require 'fileutils'

require_relative 'booksmith/version'
require_relative 'booksmith/font_paths'
require_relative 'booksmith/headers'
require_relative 'booksmith/text'
require_relative 'booksmith/lists'
require_relative 'booksmith/blockquotes'
require_relative 'booksmith/images'
require_relative 'booksmith/book_generator'
require_relative 'booksmith/epub_generator'

module Booksmith
  class PDFConverter
    include Headers
    include Text
    include Lists
    include Blockquotes
    include Images

    def initialize(pdf, config, image_flatten_bg: nil)
      @pdf = pdf
      @config = config
      @list_level = 0
      @image_flatten_bg = image_flatten_bg
    end

    def convert(content)
      content = normalize_consecutive_headers(content)
      doc = Kramdown::Document.new(content)
      convert_element(doc.root)
    end

    private

    def convert_element(el, prev: nil, next_el: nil)
      case el.type
      when :header        then render_header(el, prev: prev, next_el: next_el)
      when :xml_comment   then render_xml_comment(el, prev: prev)
      when :p             then render_paragraph(el)
      when :blockquote    then render_blockquote_element(el)
      when :codeblock     then render_codeblock(el)
      when :ul, :ol       then render_list(el)
      when :li            then render_list_item(el)
      when :text          then nil
      else                     render_children(el)
      end
    end

    def render_paragraph(el)
      img_el = image_child(el)
      if img_el
        render_image(img_el)
        @pdf.move_down 10
        return
      end

      @pdf.formatted_text extract_text(el), size: @config[:font_size], leading: @config[:line_height]
      @pdf.move_down 10 unless @list_level > 0
    end

    def render_blockquote_element(el)
      if exercise_blockquote?(el)
        render_exercise_blockquote(el)
      elsif alt_blockquote?(el)
        render_blockquote(el, :alt_blockquote)
      else
        render_blockquote(el, :blockquote)
      end
    end

    def render_codeblock(el)
      @pdf.font('Noto Sans Mono') do
        @pdf.formatted_text_box(
          [{ text: el.value, size: @config[:font_size] - 2 }],
          at: [@pdf.bounds.left + 20, @pdf.cursor],
          width: @pdf.bounds.width - 40
        )
      end
      @pdf.move_down(el.value.lines.count * (@config[:font_size] + 2) + 10)
    end

    def render_children(el)
      el.children.each_with_index do |child, idx|
        prev_idx = idx - 1
        prev_child = nil
        while prev_idx >= 0
          candidate = el.children[prev_idx]
          if candidate.type != :blank
            prev_child = candidate
            break
          end
          prev_idx -= 1
        end

        next_idx = idx + 1
        next_child = nil
        while next_idx < el.children.length
          candidate = el.children[next_idx]
          if candidate.type != :blank
            next_child = candidate
            break
          end
          next_idx += 1
        end

        convert_element(child, prev: prev_child, next_el: next_child)
      end
    end
  end

  class CLI
    include Commander::Methods

    def self.run!
      new.run!
    end

    def run!
      program :name, 'Booksmith'
      program :version, Booksmith::VERSION
      program :description, 'A flexible book publishing tool'

      default_command :help

      command :init do |c|
        c.syntax = 'booksmith init'
        c.description = 'Initialize a new book project'
        c.action do |_args, _options|
          CLI.create_project_structure
        end
      end

      command :build do |c|
        c.syntax = 'booksmith build [options]'
        c.description = 'Generate the book in PDF and/or EPUB format'
        c.option '--no-cover', 'Skip cover page generation'
        c.option '--epub', 'Generate EPUB format'
        c.option '--pdf', 'Generate PDF format'
        c.option '--format FORMAT', String, 'Specify format to build (pdf, epub, or all)'
        c.action do |_args, options|
          formats = CLI.determine_formats(options)
          BookGenerator.new(options).generate if formats.include?(:pdf)
          EpubGenerator.new(options).generate if formats.include?(:epub)
        end
      end

      command :fonts do |c|
        c.syntax = 'booksmith fonts'
        c.description = 'List registered Prawn font families'
        c.action do |_args, _options|
          CLI.list_fonts
        end
      end

      super
    end

    def self.create_project_structure
      dirs = %w[assets chapters config]
      dirs.each { |dir| FileUtils.mkdir_p(dir) }

      templates_dir = File.expand_path('templates', __dir__)

      config_template = File.join(templates_dir, 'book.yml')
      chapter_template = File.join(templates_dir, '01_introduction.md')
      clock_template = File.join(templates_dir, 'clock.png')

      FileUtils.cp(config_template, 'config/book.yml') if File.exist?(config_template)
      FileUtils.cp(chapter_template, 'chapters/01_introduction.md') if File.exist?(chapter_template)
      FileUtils.cp(clock_template, 'assets/clock.png') if File.exist?(clock_template)

      puts '✅ Book project initialized!'
      puts '📁 Created assets/, chapters/, and config/ directories'
      puts '📝 Generated config/book.yml'
      puts '📚 Generated sample chapter chapters/01_introduction.md'
      puts '🖼️  Added default exercise icon assets/clock.png'
      puts ''
      puts 'Next steps:'
      puts '  booksmith build           # generates book.pdf'
      puts '  booksmith build --epub    # generates book.epub'
      puts '  booksmith build --format all'
    end

    def self.determine_formats(options)
      if options.format
        case options.format.to_s.downcase
        when 'all', 'both'
          [:pdf, :epub]
        when 'epub'
          [:epub]
        when 'pdf'
          [:pdf]
        else
          raise ArgumentError, "Unknown format: #{options.format}. Supported formats are: pdf, epub, all"
        end
      elsif options.epub && options.pdf
        [:pdf, :epub]
      elsif options.epub
        [:epub]
      elsif options.pdf
        [:pdf]
      else
        [:pdf]
      end
    end

    def self.list_fonts
      pdf = Prawn::Document.new
      FontPaths.register(pdf)
      puts 'Registered Prawn font families:'
      pdf.font_families.keys.sort.each { |name| puts "- #{name}" }
    end
  end
end
