require 'yaml'
require 'fileutils'
require 'stringio'

module Booksmith
  class BookGenerator
    SUBTITLE_COMMENT = /\A<!--\s*subtitle:\s*(.*?)\s*-->\z/i

    def initialize(options)
      @options = options
    end

    def generate
      config = load_config
      margins = [50, 60, 50, 60]
      chapters = Dir.glob('chapters/*.md').sort
      toc_enabled = config.fetch(:table_of_contents, false) && !skip_cover?

      if toc_enabled
        @chapters_info = collect_chapters(chapters, config)

        pdf = Prawn::Document.new(page_size: 'A4', margin: margins)
        FontPaths.register(pdf)
        pdf.font config[:body_font]
        render_cover_and_blank(pdf, config)

        pre_chapter_pages = pdf.page_number
        @chapters_info.each do |ch|
          pdf.start_new_page
          ch[:page] = pdf.page_number - pre_chapter_pages
          content = File.read(ch[:file])
          render_chapter_content(pdf, content, config)
        end
        render_page_numbers(pdf, config)

        toc_page_count = estimate_toc_page_count

        Prawn::Document.generate('book.pdf', page_size: 'A4', margin: margins) do |pdf|
          FontPaths.register(pdf)
          pdf.font config[:body_font]
          render_cover_and_blank(pdf, config)
          generate_toc_page(pdf, config)
          generate_chapters(pdf, chapters, config, toc_offset: toc_page_count)
          render_page_numbers(pdf, config, toc_offset: toc_page_count)
        end
      else
        Prawn::Document.generate('book.pdf', page_size: 'A4', margin: margins) do |pdf|
          FontPaths.register(pdf)
          pdf.font config[:body_font]
          render_cover_and_blank(pdf, config)
          generate_chapters(pdf, chapters, config)
          render_page_numbers(pdf, config)
        end
      end

      puts '✅ Book generated successfully!'
    end

    def self.default_config
      template_path = File.expand_path('../templates/book.yml', __dir__)
      return File.read(template_path) if File.exist?(template_path)

      {
        title: 'My Book',
        author: 'Author Name',
        body_font: 'Noto Sans',
        header_font: 'Noto Sans',
        title_font: 'Noto Sans',
        author_font: 'Noto Sans',
        subtitle_font: 'Noto Sans',
        title_font_size: 24,
        author_font_size: 18,
        title_author_spacing: 20,
        font_size: 12,
        h1_font_size: 20,
        h2_font_size: 16,
        h3_font_size: 14,
        h4_font_size: 12,
        line_height: 1.5,
        image_flatten_bg_color: 'FFFFFF',
        page_numbers: true,
        page_number_font_size: 9,
        page_content_bottom_gap: 0,
        blank_page_after_cover: false,
        table_of_contents: false,
        toc_font_size: 10,
        subtitle_font_size: 12,
        subtitle_bold: false,
        title_spacing_after: 20,
        subtitle_spacing_after: 10,
        list_bullet_indent: 18,
        list_number_indent: 18,
        list_bullet_offset: 10,
        list_marker_gap: 4,
        list_item_spacing: 6,
        list_margin_top: 8,
        list_margin_bottom: 8,
        blockquote_bg_color: 'EEEEEE',
        blockquote_image_flatten_bg_color: 'EEEEEE',
        blockquote_padding: 12,
        blockquote_padding_left: 12,
        blockquote_padding_right: 12,
        blockquote_padding_top: 12,
        blockquote_padding_bottom: 12,
        blockquote_margin_top: 10,
        blockquote_margin_bottom: 10,
        blockquote_header_font_size: 14,
        blockquote_header_gap: 6,
        alt_blockquote_bg_color: 'F5F5F5',
        alt_blockquote_image_flatten_bg_color: 'F5F5F5',
        alt_blockquote_padding: 12,
        alt_blockquote_padding_left: 12,
        alt_blockquote_padding_right: 12,
        alt_blockquote_padding_top: 12,
        alt_blockquote_padding_bottom: 12,
        alt_blockquote_margin_top: 10,
        alt_blockquote_margin_bottom: 10,
        alt_blockquote_header_font_size: 14,
        alt_blockquote_header_gap: 6,
        exercise_blockquote_bg_color: 'EEF3FF',
        exercise_blockquote_image_flatten_bg_color: 'EEF3FF',
        exercise_blockquote_padding: 14,
        exercise_blockquote_padding_left: 12,
        exercise_blockquote_padding_right: 16,
        exercise_blockquote_padding_top: 12,
        exercise_blockquote_padding_bottom: 10,
        exercise_blockquote_margin_top: 12,
        exercise_blockquote_margin_bottom: 12,
        exercise_blockquote_image: 'assets/clock.png',
        exercise_blockquote_image_width: 28,
        exercise_blockquote_image_height: 28,
        exercise_blockquote_image_gap: 8,
        exercise_blockquote_image_voffset: 0,
        exercise_blockquote_header_font_size: 14,
        exercise_blockquote_header_gap: 6
      }.to_yaml
    end

    def self.sample_chapter
      template_path = File.expand_path('../templates/01_introduction.md', __dir__)
      return File.read(template_path) if File.exist?(template_path)

      <<~CHAPTER
        # Introduction

        This is a sample chapter for your book.

        ## Section 1

        Start writing your content here...
      CHAPTER
    end

    private

    def load_config
      config = YAML.load_file('config/book.yml')
      config = config.transform_keys { |k| k.to_s.sub(/\A:/, '').to_sym }
      config[:body_font] = config.fetch(:body_font, 'Noto Sans')
      config[:header_font] = config.fetch(:header_font, config[:body_font])
      config[:title_font] = config.fetch(:title_font, config[:header_font])
      config[:author_font] = config.fetch(:author_font, config[:body_font])
      config[:subtitle_font] = config.fetch(:subtitle_font, config[:header_font])
      config[:title_font_size] = config.fetch(:title_font_size, 24)
      config[:author_font_size] = config.fetch(:author_font_size, 18)
      config[:title_author_spacing] = config.fetch(:title_author_spacing, 20)
      config
    end

    def skip_cover?
      return false if @options.nil?
      @options.no_cover == true || @options.no_cover == false
    end

    def render_cover_and_blank(pdf, config)
      return if skip_cover?
      generate_cover(pdf, config)
      pdf.start_new_page if config[:blank_page_after_cover]
    end

    def render_page_numbers(pdf, config, toc_offset: 0)
      return unless config[:page_numbers]
      page_number_font_size = config.fetch(:page_number_font_size, 9)
      page_number_y = pdf.bounds.bottom + 10
      skipped_pages = 0
      skipped_pages += 1 unless skip_cover?
      skipped_pages += 1 if !skip_cover? && config[:blank_page_after_cover]
      skipped_pages += toc_offset
      start_count_at = 1 - skipped_pages
      page_filter = if skipped_pages.zero?
                      ->(_pg) { true }
                    else
                      ->(pg) { pg > skipped_pages }
                    end
      pdf.number_pages '<page>',
                       start_count_at: start_count_at,
                       page_filter: page_filter,
                       align: :center,
                       size: page_number_font_size,
                       at: [0, page_number_y],
                       width: pdf.bounds.width
    end

    def collect_chapters(chapters, config)
      chapters.map do |path|
        content = File.read(path)
        title = nil
        subtitle = nil

        content.each_line do |line|
          stripped = line.strip
          if stripped =~ /\A#\s+(.+)\z/ && title.nil?
            title = Regexp.last_match(1).strip
          elsif stripped =~ SUBTITLE_COMMENT && title && subtitle.nil?
            subtitle = Regexp.last_match(1).strip
          end
        end

        { file: path, title: title || File.basename(path, '.md'), subtitle: subtitle, page: 0 }
      end
    end

    def estimate_toc_page_count
      (@chapters_info.size / 25.0).ceil
    end

    def generate_toc_page(pdf, config)
      pdf.start_new_page
      toc_font_size = config.fetch(:toc_font_size, 10)
      font_name = config[:subtitle_font] || 'Noto Sans Mono'

      pdf.font(font_name) do
        pdf.move_down 40
        pdf.text 'TABLE OF CONTENTS', size: toc_font_size + 4, style: :bold, align: :center
        pdf.move_down 30

        char_width = pdf.width_of('M', size: toc_font_size)
        page_num_area_width = pdf.width_of('  000', size: toc_font_size)
        dot_width = pdf.width_of('.', size: toc_font_size)

        @chapters_info.each do |ch|
          label = ch[:subtitle] ? "#{ch[:title]}: #{ch[:subtitle]}" : ch[:title]
          label_width = pdf.width_of(label, size: toc_font_size)
          available_for_dots = pdf.bounds.width - label_width - page_num_area_width
          num_dots = [(available_for_dots / dot_width).floor, 3].max
          dots = '.' * num_dots
          page_str = ch[:page].to_s.rjust(3)
          line = "#{label} #{dots} #{page_str}"
          pdf.text line, size: toc_font_size
          pdf.move_down 4
        end
      end
    end

    def render_chapter_content(pdf, content, config)
      content_bottom_gap = [config.fetch(:page_content_bottom_gap, 0).to_f, 0.0].max

      if content_bottom_gap > 0
        max_gap = [pdf.bounds.height - 1, 0].max
        gap = [content_bottom_gap, max_gap].min
        pdf.bounding_box(
          [pdf.bounds.left, pdf.bounds.top],
          width: pdf.bounds.width,
          height: pdf.bounds.height - gap
        ) do
          generate_chapter(pdf, content, config)
        end
      else
        generate_chapter(pdf, content, config)
      end
    end

    def generate_chapters(pdf, chapters, config, toc_offset: 0)
      chapters.each do |chapter|
        pdf.start_new_page
        content = File.read(chapter)
        render_chapter_content(pdf, content, config)
      end
    end

    def generate_cover(pdf, config)
      pdf.move_down 200
      title_font = config[:title_font]
      title_font_size = config[:title_font_size]
      if title_font
        pdf.font(title_font) do
          pdf.text config[:title], align: :center, size: title_font_size, style: :bold
        end
      else
        pdf.text config[:title], align: :center, size: title_font_size, style: :bold
      end

      pdf.move_down config[:title_author_spacing]
      author_font = config[:author_font]
      author_font_size = config[:author_font_size]
      if author_font
        pdf.font(author_font) do
          pdf.text config[:author], align: :center, size: author_font_size
        end
      else
        pdf.text config[:author], align: :center, size: author_font_size
      end

      pdf.move_down 10
      pdf.text "Version #{config[:version]}", align: :center, size: 12 if config[:version]
    end

    def generate_chapter(pdf, content, config)
      converter = PDFConverter.new(pdf, config)
      converter.convert(content)
    end
  end
end
