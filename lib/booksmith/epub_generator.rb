require 'gepub'
require 'kramdown'
require 'yaml'
require 'fileutils'
require 'securerandom'
require 'stringio'
require 'ostruct'

require_relative 'font_paths'
require_relative 'headers'

module Booksmith
  class EpubGenerator
    SUBTITLE_COMMENT = /\A<!--\s*subtitle:\s*(.*?)\s*-->\z/i
    PAGE_BREAK_COMMENT = /\A<!--\s*PAGE_BREAK\s*-->\z/i

    def initialize(options = nil)
      @options = options || OpenStruct.new
    end

    def generate
      config = load_config
      chapters = Dir.glob('chapters/*.md').sort

      book = GEPUB::Book.new
      book.title = config[:title] || 'Untitled Book'
      book.creator = config[:author] || 'Unknown Author'
      book.language = config[:language] || 'en'
      book.identifier = config[:identifier] || "urn:uuid:#{SecureRandom.uuid}"
      book.date = config[:date] || Time.now.strftime('%Y-%m-%d')

      added_assets = {}

      # 1. Embed Fonts
      embed_fonts(book, added_assets)

      # 2. Add Stylesheet
      embed_stylesheet(book, config)

      # 3. Add Exercise Icon
      exercise_icon_filename = embed_exercise_icon(book, config, added_assets)

      # 4. Add Cover Image if configured
      embed_cover_image(book, config, added_assets)

      # 5. Process Chapters
      processed_chapters = process_chapters(chapters, config, exercise_icon_filename, book, added_assets)

      # 6. Build Navigation and Spine
      book.ordered do
        unless skip_cover?
          cover_xhtml = generate_cover_page(config)
          cover_item = book.add_item('text/cover.xhtml', content: StringIO.new(cover_xhtml))
          cover_item.toc_text('Cover')
        end

        processed_chapters.each do |ch|
          item = book.add_item("text/#{ch[:filename]}", content: StringIO.new(ch[:xhtml]))
          item.toc_text(ch[:toc_title])
        end
      end

      output_path = @options.output || 'book.epub'
      book.generate_epub(output_path)
      puts "✅ EPUB generated successfully at #{output_path}!"
    end

    private

    def skip_cover?
      return false if @options.nil?
      # OptionParser sets no_cover = false when --no-cover flag is passed
      @options.no_cover == true || @options.no_cover == false
    end

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
      config[:subtitle_font_size] = config.fetch(:subtitle_font_size, 12)
      config
    end

    def embed_fonts(book, added_assets)
      FontPaths.all_files.each do |font_path|
        next unless File.file?(font_path)

        filename = File.basename(font_path)
        href = "fonts/#{filename}"
        next if added_assets[href]

        added_assets[href] = true
        item = book.add_item(href, content: File.open(font_path, 'rb'))
        item.media_type = 'font/ttf'
      end
    end

    def embed_stylesheet(book, config)
      css_content = generate_css(config)
      book.add_item('css/styles.css', content: StringIO.new(css_content))
    end

    def embed_exercise_icon(book, config, added_assets)
      icon_path = config[:exercise_blockquote_image] || 'assets/clock.png'
      return nil unless File.file?(icon_path)

      filename = File.basename(icon_path)
      href = "images/#{filename}"
      unless added_assets[href]
        added_assets[href] = true
        book.add_item(href, content: File.open(icon_path, 'rb'))
      end
      filename
    end

    def embed_cover_image(book, config, added_assets)
      cover_image_path = config[:cover_image]
      return unless cover_image_path && File.file?(cover_image_path)

      filename = File.basename(cover_image_path)
      href = "images/#{filename}"
      return if added_assets[href]

      added_assets[href] = true
      book.add_item(href, content: File.open(cover_image_path, 'rb')).cover_image
    end

    def process_chapters(chapters, config, exercise_icon_filename, book, added_assets)
      chapters.each_with_index.map do |chapter_path, idx|
        raw_content = File.read(chapter_path)
        content = Headers.normalize_consecutive_headers(raw_content)

        title, subtitle = extract_title_and_subtitle(content, chapter_path)
        toc_title = subtitle ? "#{title}: #{subtitle}" : title

        chapter_metrics = measure_chapter_images(content, config)

        doc = Kramdown::Document.new(content)
        html = doc.to_html

        processed_html = transform_html(html, title, subtitle, exercise_icon_filename, book, added_assets, chapter_metrics)
        xhtml = wrap_in_xhtml(title, processed_html)

        filename = "chapter_#{format('%02d', idx)}.xhtml"
        { filename: filename, xhtml: xhtml, toc_title: toc_title }
      end
    end

    def extract_title_and_subtitle(content, file_path)
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

      [title || File.basename(file_path, '.md'), subtitle]
    end

    def transform_html(html, title, subtitle, exercise_icon_filename, book, added_assets, chapter_metrics = {})
      result = html.dup

      # 1. Transform chapter header with subtitle
      header_replaced = false
      result = result.sub(%r{<h1([^>]*)>(.*?)</h1>\s*<!--\s*subtitle:\s*(.*?)\s*-->}mi) do
        h1_attrs = Regexp.last_match(1)
        h1_text = Regexp.last_match(2)
        sub_text = Regexp.last_match(3)
        header_replaced = true
        <<~HTML.strip
          <div class="chapter-header">
            <h1#{h1_attrs} class="chapter-title">#{h1_text}</h1>
            <p class="chapter-subtitle">#{sub_text}</p>
          </div>
        HTML
      end

      unless header_replaced
        result = result.sub(%r{<h1([^>]*)>(.*?)</h1>}m) do
          h1_attrs = Regexp.last_match(1)
          h1_text = Regexp.last_match(2)
          subtitle_part = subtitle ? %(\n  <p class="chapter-subtitle">#{subtitle}</p>) : ''
          <<~HTML.strip
            <div class="chapter-header">
              <h1#{h1_attrs} class="chapter-title">#{h1_text}</h1>#{subtitle_part}
            </div>
          HTML
        end
      end

      # Remove leftover standalone subtitle comments if any
      result = result.gsub(%r{<!--\s*subtitle:\s*.*?\s*-->}mi, '')

      # 2. Transform PAGE_BREAK comments
      result = result.gsub(%r{<!--\s*PAGE_BREAK\s*-->}i, '<div class="page-break"></div>')

      # 3. Transform images and register them in the EPUB
      result = transform_images(result, book, added_assets, chapter_metrics)

      # 4. Transform blockquotes
      result = transform_blockquotes(result, exercise_icon_filename)

      result
    end

    def transform_blockquotes(html, exercise_icon_filename)
      html.gsub(%r{<blockquote(\s+class="([^"]*)")?>(.*?)</blockquote>}m) do
        attrs = Regexp.last_match(1) || ''
        classes = (Regexp.last_match(2) || '').split
        inner = Regexp.last_match(3)
        is_exercise = classes.include?('exercise_blockquote')

        # Check if first paragraph starts with bold text
        if inner =~ %r{\A\s*<p>\s*<strong>(.*?)</strong>(?:\s*<br\s*/?>|\s*\n)?\s*(.*?)\s*</p>(.*)\z}m
          header_text = Regexp.last_match(1)
          p_rest = Regexp.last_match(2)
          remaining = Regexp.last_match(3)

          header_html = if is_exercise && exercise_icon_filename
            %(<div class="blockquote-header"><img src="../images/#{exercise_icon_filename}" class="exercise-icon" alt="" /><span>#{header_text}</span></div>)
          else
            %(<div class="blockquote-header"><span>#{header_text}</span></div>)
          end

          body_html = (p_rest && !p_rest.empty?) ? %(<p>#{p_rest}</p>#{remaining}) : remaining
          %(<blockquote#{attrs}>\n  #{header_html}\n  #{body_html.strip}\n</blockquote>)
        elsif is_exercise && exercise_icon_filename
          icon_html = %(<div class="blockquote-icon-row"><img src="../images/#{exercise_icon_filename}" class="exercise-icon" alt="" /></div>)
          %(<blockquote#{attrs}>\n  #{icon_html}\n  #{inner.strip}\n</blockquote>)
        else
          %(<blockquote#{attrs}>#{inner}</blockquote>)
        end
      end
    end

    def transform_images(html, book, added_assets, chapter_metrics = {})
      # First transform paragraph-wrapped images
      result = html.gsub(%r{<p>\s*(<img\b[^>]*/>)\s*</p>}m) do
        img_tag = Regexp.last_match(1)
        convert_single_image(img_tag, book, added_assets, chapter_metrics)
      end

      # Then transform any remaining standalone images outside image-container
      result.gsub(%r{(<div class="image-container"[^>]*>.*?</div>)|(<img\b[^>]*/>)}m) do
        if Regexp.last_match(1)
          Regexp.last_match(1)
        else
          convert_single_image(Regexp.last_match(2), book, added_assets, chapter_metrics)
        end
      end
    end

    def convert_single_image(img_tag, book, added_assets, chapter_metrics = {})
      src_match = img_tag.match(%r{src="([^"]+)"})
      return img_tag unless src_match

      original_src = src_match[1]
      resolved_path = resolve_image_path(original_src)
      return img_tag unless resolved_path && File.file?(resolved_path)

      filename = File.basename(resolved_path)
      epub_image_href = "images/#{filename}"

      unless added_assets[epub_image_href]
        added_assets[epub_image_href] = true
        book.add_item(epub_image_href, content: File.open(resolved_path, 'rb'))
      end

      new_src = "../images/#{filename}"

      metric = chapter_metrics[original_src]
      if metric
        width_pct = metric[:pct]
        max_w_px = metric[:rendered_width].round
        margin_top = [metric[:top], 30.0].min.round
        margin_bottom = [metric[:bottom], 20.0].min.round
      else
        width_match = img_tag.match(/width=(\d+(?:\.\d+)?)/)
        w = width_match ? width_match[1].to_f : 400.0
        width_pct = [(w / 475.28 * 100.0).round(1), 100.0].min
        max_w_px = w.round
        top_match = img_tag.match(/top=(\d+(?:\.\d+)?)/)
        margin_top = top_match ? [top_match[1].to_f, 30.0].min.round : 10
        bot_match = img_tag.match(/bottom=(\d+(?:\.\d+)?)/)
        margin_bottom = bot_match ? [bot_match[1].to_f, 20.0].min.round : 10
      end

      alt_match = img_tag.match(/alt="([^"]*)"/)
      alt_attr = alt_match ? %(alt="#{alt_match[1]}") : 'alt=""'

      # Container styles: constrain width and center horizontally
      container_style = %(style="width: #{width_pct}%; max-width: #{max_w_px}px; margin: #{margin_top}px auto #{margin_bottom}px auto;")

      # Image styles: fit container width, preserve aspect ratio, capped at 42vh
      img_style = %(style="width: 100%; max-width: 100%; max-height: 42vh; height: auto; object-fit: contain; display: block; margin: 0 auto;")

      new_tag = %(<img src="#{new_src}" #{alt_attr} width="#{max_w_px}" #{img_style} class="book-image" />)
      %(<div class="image-container" #{container_style}>#{new_tag}</div>)
    end

    def resolve_image_path(src)
      return src if File.file?(src)

      candidate = File.join(Dir.pwd, src)
      return candidate if File.file?(candidate)

      candidate = File.join(Dir.pwd, 'assets', File.basename(src))
      return candidate if File.file?(candidate)

      nil
    end

    def measure_chapter_images(content, config)
      margins = [50, 60, 50, 60]
      pdf = Prawn::Document.new(page_size: 'A4', margin: margins)
      FontPaths.register(pdf)
      pdf.font config[:body_font]

      normalized = Headers.normalize_consecutive_headers(content)
      doc = Kramdown::Document.new(normalized)
      converter = PDFConverter.new(pdf, config)

      metrics = {}
      doc.root.children.each do |el|
        img = converter.send(:image_child, el)
        if img
          opts = img.attr['title'].to_s
          src = img.attr['src']
          w = opts[/width=(\d+(?:\.\d+)?)/, 1]&.to_f
          top = opts[/top=(\d+(?:\.\d+)?)/, 1]&.to_f || 0
          bottom = opts[/bottom=(\d+(?:\.\d+)?)/, 1]&.to_f || 0
          cursor_before = pdf.cursor
          max_w = w || pdf.bounds.width
          max_h = [cursor_before - top - 20, 50.0].max

          resolved = resolve_image_path(src)
          if resolved && File.file?(resolved)
            dims = image_dimensions(resolved)
            if dims && dims[0] > 0 && dims[1] > 0
              orig_w, orig_h = dims[0].to_f, dims[1].to_f
              scale = [max_w / orig_w, max_h / orig_h].min
              rendered_w = orig_w * scale
              rendered_h = orig_h * scale
              col_w = pdf.bounds.width.to_f
              pct = [(rendered_w / col_w * 100.0).round(1), 100.0].min
              metrics[src] = {
                rendered_width: rendered_w.round(1),
                rendered_height: rendered_h.round(1),
                pct: pct,
                top: top,
                bottom: bottom
              }
            end
          end
        end
        converter.send(:convert_element, el)
      end
      metrics
    rescue => _e
      {}
    end

    def image_dimensions(path)
      return nil unless File.file?(path)

      if path.downcase.end_with?('.png')
        data = File.binread(path, 24)
        if data && data.bytesize >= 24 && data[0..7] == "\x89PNG\r\n\x1a\n".b
          return data[16..23].unpack('NN')
        end
      end

      output = `magick identify -format "%w %h" "#{path}" 2>/dev/null`
      if output && !output.empty?
        parts = output.split.map(&:to_i)
        return parts if parts.length == 2 && parts[0] > 0
      end

      nil
    end

    def wrap_in_xhtml(title, body_content)
      escaped_title = escape_html(title)
      <<~XHTML
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head>
          <meta charset="utf-8"/>
          <title>#{escaped_title}</title>
          <link rel="stylesheet" type="text/css" href="../css/styles.css"/>
        </head>
        <body>
          #{body_content}
        </body>
        </html>
      XHTML
    end

    def generate_cover_page(config)
      title = escape_html(config[:title] || 'Untitled')
      author = escape_html(config[:author] || '')
      version = config[:version] ? escape_html("Version #{config[:version]}") : nil

      version_html = version ? %(<div class="cover-version">#{version}</div>) : ''

      <<~XHTML
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="en">
        <head>
          <meta charset="utf-8"/>
          <title>#{title}</title>
          <link rel="stylesheet" type="text/css" href="../css/styles.css"/>
        </head>
        <body>
          <div class="cover-page">
            <h1 class="cover-title">#{title}</h1>
            <div class="cover-author">#{author}</div>
            #{version_html}
          </div>
        </body>
        </html>
      XHTML
    end

    def generate_css(config)
      font_size = config.fetch(:font_size, 10)
      line_height = config.fetch(:line_height, 1.5)
      h1_size = config.fetch(:h1_font_size, 20)
      h2_size = config.fetch(:h2_font_size, 18)
      h3_size = config.fetch(:h3_font_size, 14)
      h4_size = config.fetch(:h4_font_size, 12)
      subtitle_size = config.fetch(:subtitle_font_size, 12)
      subtitle_weight = config[:subtitle_bold] ? 'bold' : 'normal'
      title_font_size = config.fetch(:title_font_size, 24)
      author_font_size = config.fetch(:author_font_size, 18)

      bq_bg = config.fetch(:blockquote_bg_color, 'EEEEEE')
      bq_pt = config.fetch(:blockquote_padding_top, 20)
      bq_pr = config.fetch(:blockquote_padding_right, 12)
      bq_pb = config.fetch(:blockquote_padding_bottom, 10)
      bq_pl = config.fetch(:blockquote_padding_left, 12)
      bq_header_size = config.fetch(:blockquote_header_font_size, 14)

      alt_bq_bg = config.fetch(:alt_blockquote_bg_color, 'F5F5F5')
      alt_bq_pt = config.fetch(:alt_blockquote_padding_top, 18)
      alt_bq_pr = config.fetch(:alt_blockquote_padding_right, 12)
      alt_bq_pb = config.fetch(:alt_blockquote_padding_bottom, 8)
      alt_bq_pl = config.fetch(:alt_blockquote_padding_left, 12)

      ex_bq_bg = config.fetch(:exercise_blockquote_bg_color, 'EEF3FF')
      ex_bq_pt = config.fetch(:exercise_blockquote_padding_top, 18)
      ex_bq_pr = config.fetch(:exercise_blockquote_padding_right, 16)
      ex_bq_pb = config.fetch(:exercise_blockquote_padding_bottom, 10)
      ex_bq_pl = config.fetch(:exercise_blockquote_padding_left, 12)
      ex_icon_width = config.fetch(:exercise_blockquote_image_width, 18)
      ex_icon_height = config.fetch(:exercise_blockquote_image_height, 18)

      <<~CSS
        @font-face {
          font-family: 'Noto Sans';
          font-style: normal;
          font-weight: 400;
          src: url('../fonts/NotoSans-Regular.ttf');
        }
        @font-face {
          font-family: 'Noto Sans';
          font-style: normal;
          font-weight: 700;
          src: url('../fonts/NotoSans-Bold.ttf');
        }
        @font-face {
          font-family: 'Noto Sans';
          font-style: italic;
          font-weight: 400;
          src: url('../fonts/NotoSans-Italic.ttf');
        }
        @font-face {
          font-family: 'Noto Sans';
          font-style: italic;
          font-weight: 700;
          src: url('../fonts/NotoSans-BoldItalic.ttf');
        }
        @font-face {
          font-family: 'Noto Sans Mono';
          font-style: normal;
          font-weight: 400;
          src: url('../fonts/NotoSansMono-Regular.ttf');
        }
        @font-face {
          font-family: 'Noto Sans Mono';
          font-style: normal;
          font-weight: 700;
          src: url('../fonts/NotoSansMono-Bold.ttf');
        }

        body {
          font-family: 'Noto Sans', system-ui, -apple-system, sans-serif;
          font-size: #{font_size}pt;
          line-height: 1.4;
          color: #222222;
          margin: 0;
          padding: 0 0.5em;
        }

        h1, h2, h3, h4, h5, h6 {
          font-family: 'Noto Sans', sans-serif;
          font-weight: bold;
          line-height: 1.25;
          margin-top: 1.4em;
          margin-bottom: 0.5em;
        }

        h1 { font-size: #{h1_size}pt; }
        h2 { font-size: #{h2_size}pt; }
        h3 { font-size: #{h3_size}pt; }
        h4 { font-size: #{h4_size}pt; }

        .chapter-header {
          margin-top: 0.5em;
          margin-bottom: 1.2em;
        }

        .chapter-title {
          font-size: #{h1_size}pt;
          margin: 0 0 0.3em 0;
        }

        .chapter-subtitle {
          font-family: 'Noto Sans Mono', monospace;
          font-size: #{subtitle_size}pt;
          font-weight: #{subtitle_weight};
          color: #555555;
          margin: 0 0 1.2em 0;
        }

        p {
          margin-top: 0;
          margin-bottom: 1em;
        }

        ul, ol {
          margin-top: 0.5em;
          margin-bottom: 1em;
          padding-left: 1.8em;
        }

        li {
          margin-bottom: 0.4em;
        }

        pre, code {
          font-family: 'Noto Sans Mono', monospace;
        }

        pre {
          background-color: #f7f7f7;
          border: 1px solid #e5e5e5;
          border-radius: 4px;
          padding: 10px 14px;
          overflow-x: auto;
          font-size: 0.9em;
          line-height: 1.4;
        }

        code {
          background-color: #f0f0f0;
          padding: 0.15em 0.35em;
          border-radius: 3px;
          font-size: 0.9em;
        }

        pre code {
          background-color: transparent;
          padding: 0;
        }

        blockquote {
          background-color: ##{bq_bg};
          margin: 1.2em 0;
          padding: #{bq_pt}px #{bq_pr}px #{bq_pb}px #{bq_pl}px;
          border-radius: 4px;
        }

        blockquote.alt_blockquote {
          background-color: ##{alt_bq_bg};
          padding: #{alt_bq_pt}px #{alt_bq_pr}px #{alt_bq_pb}px #{alt_bq_pl}px;
        }

        blockquote.exercise_blockquote {
          background-color: ##{ex_bq_bg};
          padding: #{ex_bq_pt}px #{ex_bq_pr}px #{ex_bq_pb}px #{ex_bq_pl}px;
        }

        .blockquote-header {
          font-size: #{bq_header_size}pt;
          font-weight: bold;
          margin-bottom: 0.5em;
          display: flex;
          align-items: center;
        }

        .exercise-icon {
          width: #{ex_icon_width}px;
          height: #{ex_icon_height}px;
          vertical-align: middle;
          margin-right: 8px;
          display: inline-block;
        }

        .blockquote-icon-row {
          margin-bottom: 0.5em;
        }

        .page-break {
          page-break-after: always;
          break-after: page;
        }

        .image-container {
          text-align: center;
          margin-left: auto;
          margin-right: auto;
        }

        .book-image {
          max-width: 100%;
          height: auto;
          display: block;
          margin: 0 auto;
        }

        /* Cover page */
        .cover-page {
          text-align: center;
          padding-top: 25vh;
        }

        .cover-title {
          font-family: 'Noto Sans Mono', monospace;
          font-size: #{title_font_size}pt;
          font-weight: bold;
          margin-bottom: 20px;
        }

        .cover-author {
          font-family: 'Noto Sans Mono', monospace;
          font-size: #{author_font_size}pt;
          color: #444444;
          margin-bottom: 15px;
        }

        .cover-version {
          font-size: 12pt;
          color: #888888;
        }
      CSS
    end

    def escape_html(str)
      str.to_s
         .gsub('&', '&amp;')
         .gsub('<', '&lt;')
         .gsub('>', '&gt;')
         .gsub('"', '&quot;')
         .gsub("'", '&#39;')
    end
  end
end
