require 'digest/md5'
require 'fileutils'

module Booksmith
  module Images
    private

    def image_child(el)
      non_blank = el.children.reject { |c| c.type == :blank || (c.type == :text && c.value.strip.empty?) }
      return nil unless non_blank.length == 1 && non_blank.first.type == :img
      non_blank.first
    end

    def render_image(img_el)
      src = img_el.attr['src']
      path = File.expand_path(src, Dir.pwd)
      return unless File.exist?(path)

      opts = img_el.attr['title'].to_s
      margin_top    = opts[/top=(\d+(?:\.\d+)?)/,    1]&.to_f || 0
      margin_bottom = opts[/bottom=(\d+(?:\.\d+)?)/, 1]&.to_f || 0
      width         = opts[/width=(\d+(?:\.\d+)?)/,  1]&.to_f
      flatten_bg = image_flatten_bg_color(bg_override: opts[/bg=([0-9A-Fa-f]{6})/, 1])

      @pdf.move_down margin_top if margin_top > 0
      max_w = width || @pdf.bounds.width
      max_h = @pdf.cursor - 20
      @pdf.image(prepare_png_path(path, background_color: flatten_bg), fit: [max_w, max_h], position: :center)
      @pdf.move_down margin_bottom if margin_bottom > 0
    end

    def image_flatten_bg_color(bg_override: nil)
      return bg_override if bg_override
      return @image_flatten_bg if @image_flatten_bg

      @config.fetch(:image_flatten_bg_color, 'FFFFFF')
    end

    def blockquote_image_flatten_color(style_name)
      flatten_key = :"#{style_name}_image_flatten_bg_color"
      return @config[flatten_key] if @config.key?(flatten_key)

      blockquote_style_value(style_name, :bg_color, 'EEEEEE')
    end

    def with_image_flatten_bg(color)
      previous = @image_flatten_bg
      @image_flatten_bg = color
      yield
    ensure
      @image_flatten_bg = previous
    end

    def magick_available?
      return @magick_available unless @magick_available.nil?

      @magick_available = system('which magick > /dev/null 2>&1')
    end

    # Some PNG exports bake a visible checkerboard into opaque pixels instead of
    # using a real alpha channel. Flatten those onto the target background.
    def prepare_png_path(path, background_color:)
      return path unless path.downcase.end_with?('.png')
      return path unless magick_available?

      bg_hex = background_color.to_s.delete_prefix('#').upcase
      cache_dir = File.join(Dir.pwd, '.booksmith-cache', 'images')
      FileUtils.mkdir_p(cache_dir)

      cache_name = "#{Digest::MD5.hexdigest(path)}_#{bg_hex}_#{File.mtime(path).to_i}.png"
      cached = File.join(cache_dir, cache_name)
      return cached if File.exist?(cached)

      success = system(
        'magick', path,
        '-fuzz', '12%',
        '-transparent', 'white',
        '-transparent', '#EBEBEB',
        '-transparent', '#EAEAEA',
        '-background', "##{bg_hex}",
        '-alpha', 'remove',
        '-compose', 'Copy',
        '-flatten',
        cached,
        out: File::NULL,
        err: File::NULL
      )

      success && File.exist?(cached) ? cached : path
    end
  end
end
