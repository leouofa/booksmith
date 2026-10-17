module Booksmith
  module Lists
    private

    def render_list(el)
      list_indent = list_indent_for(el.type)
      list_bullet_offset = @config.fetch(:list_bullet_offset, 10)
      list_marker_gap = @config.fetch(:list_marker_gap, 4).to_f
      list_item_spacing = @config.fetch(:list_item_spacing, 6)
      list_margin_top = @config.fetch(:list_margin_top, 8)
      list_margin_bottom = @config.fetch(:list_margin_bottom, 8)

      @list_level += 1
      @pdf.move_down list_margin_top if @list_level == 1

      el.children.each_with_index do |item, index|
        marker = el.type == :ul ? '•' : "#{index + 1}."
        indent = @list_level * list_indent

        @pdf.indent(indent) do
          ensure_space_for_list_item
          render_list_marker(marker, list_bullet_offset, align: el.type == :ul ? :center : :right)
          @pdf.indent(list_bullet_offset + list_marker_gap) { convert_element(item) }
        end
        @pdf.move_down list_item_spacing unless index == el.children.length - 1
      end

      @list_level -= 1
      @pdf.move_down list_margin_bottom if @list_level == 0
    end

    def render_list_item(el)
      el.children.each { |child| convert_element(child) }
    end

    def list_indent_for(list_type)
      key = list_type == :ul ? :list_bullet_indent : :list_number_indent
      @config.fetch(key, @config.fetch(:list_indent, 18)).to_f
    end

    def ensure_space_for_list_item
      font_size = @config[:font_size].to_f
      min_height = font_size * @config[:line_height].to_f
      @pdf.start_new_page if @pdf.cursor <= @pdf.bounds.bottom + min_height
    end

    def render_list_marker(marker, offset, align: :right)
      font_size = @config[:font_size].to_f
      body_font = @config.fetch(:body_font, 'Noto Sans')

      @pdf.font(body_font, size: font_size) do
        @pdf.formatted_text_box(
          [{ text: marker, size: font_size, font: body_font }],
          at: [@pdf.bounds.left, @pdf.cursor],
          width: offset,
          align: align,
          leading: @config[:line_height]
        )
      end
    end
  end
end
