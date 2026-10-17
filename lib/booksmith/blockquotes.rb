module Booksmith
  module Blockquotes
    private

    def render_blockquote(el, style_name)
      bg_color = blockquote_style_value(style_name, :bg_color, 'EEEEEE')
      padding_left = blockquote_padding(style_name, :left)
      padding_right = blockquote_padding(style_name, :right)
      padding_top = blockquote_padding(style_name, :top)
      padding_bottom = blockquote_padding(style_name, :bottom)
      margin_top = blockquote_style_value(style_name, :margin_top, 10).to_f
      margin_bot = blockquote_style_value(style_name, :margin_bottom, 10).to_f
      content_width = @pdf.bounds.width - padding_left - padding_right
      header_el, body_els = split_blockquote_children(el)

      @pdf.move_down margin_top

      box_height = measure_blockquote_height(el, content_width, style_name) + padding_top + padding_bottom

      saved = @pdf.fill_color
      @pdf.fill_color bg_color
      @pdf.fill_rectangle([@pdf.bounds.left, @pdf.cursor], @pdf.bounds.width, box_height)
      @pdf.fill_color saved

      @pdf.move_down padding_top
      with_image_flatten_bg(blockquote_image_flatten_color(style_name)) do
        @pdf.indent(padding_left, padding_right) do
          render_blockquote_title_row(header_el, style_name) if header_el
          body_els.each { |child| convert_element(child) }
        end
      end
      @pdf.move_down padding_bottom
      @pdf.move_down margin_bot
    end

    def render_exercise_blockquote(el)
      bg_color   = blockquote_style_value(:exercise_blockquote, :bg_color, 'EEF3FF')
      padding_left   = blockquote_padding(:exercise_blockquote, :left)
      padding_right  = blockquote_padding(:exercise_blockquote, :right)
      padding_top    = blockquote_padding(:exercise_blockquote, :top)
      padding_bottom = blockquote_padding(:exercise_blockquote, :bottom)
      margin_top = blockquote_style_value(:exercise_blockquote, :margin_top, 12).to_f
      margin_bot = blockquote_style_value(:exercise_blockquote, :margin_bottom, 12).to_f
      content_width = @pdf.bounds.width - padding_left - padding_right

      header_el, body_els = split_exercise_children(el)

      @pdf.move_down margin_top

      box_height = measure_exercise_height(content_width, header_el, body_els) + padding_top + padding_bottom
      top_cursor = @pdf.cursor

      saved = @pdf.fill_color
      @pdf.fill_color bg_color
      @pdf.fill_rectangle([@pdf.bounds.left, top_cursor], @pdf.bounds.width, box_height)
      @pdf.fill_color saved

      @pdf.move_down padding_top
      with_image_flatten_bg(blockquote_image_flatten_color(:exercise_blockquote)) do
        @pdf.indent(padding_left, padding_right) do
          render_exercise_title_row(header_el)
          body_els.each { |child| convert_element(child) }
        end
      end
      @pdf.move_down padding_bottom
      @pdf.move_down margin_bot
    end

    def alt_blockquote?(element)
      classes = element.attr.fetch('class', '').split
      classes.include?('alt_blockquote')
    end

    def exercise_blockquote?(element)
      element.attr.fetch('class', '').split.include?('exercise_blockquote')
    end

    def blockquote_header_paragraph?(element)
      return false unless element&.type == :p

      inline = element.children.reject { |c| c.type == :blank || (c.type == :text && c.value.strip.empty?) }
      inline.length == 1 && inline.first.type == :strong
    end

    def split_blockquote_children(el)
      children = el.children.reject { |c| c.type == :blank }
      return [nil, children] if children.empty?
      return [children.first, children.drop(1)] if blockquote_header_paragraph?(children.first)

      [nil, children]
    end

    def split_exercise_children(el)
      children = el.children.reject { |c| c.type == :blank }
      [children.first, children.drop(1)]
    end

    def blockquote_style_value(style_name, setting, default)
      key = :"#{style_name}_#{setting}"
      fallback_key = :"blockquote_#{setting}"

      return @config[key] if @config.key?(key)
      return @config[fallback_key] if style_name != :blockquote && @config.key?(fallback_key)

      default
    end

    def blockquote_padding(style_name, side)
      per_side_key = :"#{style_name}_padding_#{side}"
      return @config[per_side_key].to_f if @config.key?(per_side_key)

      if style_name != :blockquote
        fallback_per_side = :"blockquote_padding_#{side}"
        return @config[fallback_per_side].to_f if @config.key?(fallback_per_side)
      end

      default_padding = style_name == :exercise_blockquote ? 14 : 12
      blockquote_style_value(style_name, :padding, default_padding).to_f
    end

    def blockquote_header_font_size(style_name)
      blockquote_style_value(style_name, :header_font_size, @config[:font_size] + 4).to_f
    end

    def exercise_header_font_size
      blockquote_header_font_size(:exercise_blockquote)
    end

    def exercise_title_row_height(img_height, title_size, header_text, title_width)
      header_height = @pdf.height_of(header_text, size: title_size, style: :bold, width: title_width)
      [img_height, header_height].max
    end

    def render_blockquote_title_row(header_el, style_name)
      header_text = plain_text(header_el)
      title_size = blockquote_header_font_size(style_name)
      header_gap = blockquote_style_value(style_name, :header_gap, 6).to_f
      row_height = @pdf.height_of(header_text, size: title_size, style: :bold, width: @pdf.bounds.width)

      @pdf.text_box(
        header_text,
        at: [@pdf.bounds.left, @pdf.cursor],
        width: @pdf.bounds.width,
        height: row_height,
        size: title_size,
        style: :bold,
        valign: :top
      )
      @pdf.move_down row_height + header_gap
    end

    def render_exercise_title_row(header_el)
      header_text = plain_text(header_el)
      title_size = exercise_header_font_size
      img_width = blockquote_style_value(:exercise_blockquote, :image_width, 28).to_f
      img_height = blockquote_style_value(:exercise_blockquote, :image_height, img_width).to_f
      img_gap = blockquote_style_value(:exercise_blockquote, :image_gap, 8).to_f
      img_voffset = blockquote_style_value(:exercise_blockquote, :image_voffset, 0).to_f
      header_gap = blockquote_style_value(:exercise_blockquote, :header_gap, 6).to_f
      title_width = [@pdf.bounds.width - img_width - img_gap, 1].max
      row_height = exercise_title_row_height(img_height, title_size, header_text, title_width)

      @pdf.bounding_box([@pdf.bounds.left, @pdf.cursor], width: @pdf.bounds.width, height: row_height) do
        image_path = exercise_image_path
        if image_path
          @pdf.bounding_box([0, row_height + img_voffset], width: img_width, height: row_height) do
            @pdf.image(image_path, fit: [img_width, img_height], position: :center, vposition: :center)
          end
        end

        @pdf.text_box(
          header_text,
          at: [img_width + img_gap, row_height],
          width: title_width,
          height: row_height,
          size: title_size,
          style: :bold,
          valign: :center
        )
      end

      @pdf.move_down header_gap
    end

    def exercise_image_path
      path = @config.fetch(:exercise_blockquote_image, 'assets/question_mark.png')
      expanded = File.expand_path(path, Dir.pwd)
      return nil unless File.exist?(expanded)

      bg_color = blockquote_image_flatten_color(:exercise_blockquote)
      prepare_png_path(expanded, background_color: bg_color)
    end

    def measure_blockquote_height(el, content_width, style_name = :blockquote)
      header_el, body_els = split_blockquote_children(el)
      scratch = create_scratch_document(content_width)
      flatten_bg = blockquote_image_flatten_color(style_name)
      converter = PDFConverter.new(scratch, @config, image_flatten_bg: flatten_bg)
      start_y = scratch.cursor
      if header_el
        converter.send(:render_blockquote_title_row, header_el, style_name)
        body_els.each { |child| converter.send(:convert_element, child) }
      else
        body_els.each { |child| converter.send(:convert_element, child) }
      end
      [start_y - scratch.cursor, 0].max
    end

    def measure_exercise_height(content_width, header_el, body_els)
      scratch = create_scratch_document(content_width)
      flatten_bg = blockquote_image_flatten_color(:exercise_blockquote)
      converter = PDFConverter.new(scratch, @config, image_flatten_bg: flatten_bg)
      start_y = scratch.cursor
      converter.send(:render_exercise_title_row, header_el)
      body_els.each { |child| converter.send(:convert_element, child) }
      [start_y - scratch.cursor, 0].max
    end

    def create_scratch_document(content_width)
      scratch = Prawn::Document.new(
        page_size: [content_width + 2, 5000], margin: [0, 1, 0, 1]
      )
      FontPaths.register(scratch)
      scratch.font(@config.fetch(:body_font, 'Noto Sans'))
      scratch
    end
  end
end
