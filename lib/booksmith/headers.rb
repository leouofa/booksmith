module Booksmith
  module Headers
    private

    SUBTITLE_COMMENT = /\A<!--\s*subtitle:\s*(.*?)\s*-->\z/i
    PAGE_BREAK_COMMENT = /\A<!--\s*PAGE_BREAK\s*-->\z/i

    # Kramdown requires a blank line between consecutive headers.
    def self.normalize_consecutive_headers(content)
      lines = content.lines
      normalized = []
      lines.each_with_index do |line, idx|
        normalized << line
        next_line = lines[idx + 1]
        if line.match?(/\A\#{1,6}\s/) && next_line&.match?(/\A\#{1,6}\s/)
          normalized << "\n"
        end
      end
      normalized.join
    end

    def normalize_consecutive_headers(content)
      Headers.normalize_consecutive_headers(content)
    end

    def subtitle_comment?(el)
      el&.type == :xml_comment && el.value.to_s =~ SUBTITLE_COMMENT
    end

    def subtitle_comment_text(el)
      el.value.to_s[SUBTITLE_COMMENT, 1]&.strip
    end

    def render_subtitle(text)
      size = @config.fetch(:subtitle_font_size, @config[:h4_font_size])
      style = @config.fetch(:subtitle_bold, false) ? :bold : nil
      font_name = @config[:subtitle_font]
      if font_name
        @pdf.font(font_name) do
          @pdf.text text, size: size, style: style
        end
      else
        @pdf.text text, size: size, style: style
      end
    end

    def render_header(el, prev:, next_el:)
      prev_is_page_break = prev&.type == :xml_comment && prev.value.to_s =~ PAGE_BREAK_COMMENT
      if prev&.type == :header || prev_is_page_break
        @pdf.move_down 0
      else
        @pdf.move_down 20
      end

      level = el.options[:level]

      header_sizes = {
        1 => @config[:h1_font_size],
        2 => @config[:h2_font_size],
        3 => @config[:h3_font_size],
        4 => @config[:h4_font_size]
      }

      size = header_sizes[level]
      raise KeyError, "Missing required header font size config for H#{level} (:h#{level}_font_size)" unless size

      font_name = @config[:header_font]
      if font_name
        @pdf.font(font_name) do
          @pdf.text el.options[:raw_text], size: size, style: :bold
        end
      else
        @pdf.text el.options[:raw_text], size: size, style: :bold
      end

      title_spacing_after = @config.fetch(:title_spacing_after, 20)
      if level == 1 && subtitle_comment?(next_el)
        @pdf.move_down 0
      elsif next_el&.type == :header
        @pdf.move_down 0
      elsif level == 1
        @pdf.move_down title_spacing_after
      else
        @pdf.move_down 14
      end
    end

    def render_xml_comment(el, prev:)
      if el.value.to_s =~ PAGE_BREAK_COMMENT
        @pdf.start_new_page
      elsif prev&.type == :header && prev.options[:level] == 1 && (text = subtitle_comment_text(el))
        render_subtitle(text)
        @pdf.move_down @config.fetch(:subtitle_spacing_after, 10)
      end
    end
  end
end
