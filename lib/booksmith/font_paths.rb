module Booksmith
  module FontPaths
    NOTO_SANS_FILES = {
      normal: 'NotoSans-Regular.ttf',
      bold: 'NotoSans-Bold.ttf',
      italic: 'NotoSans-Italic.ttf',
      bold_italic: 'NotoSans-BoldItalic.ttf'
    }.freeze

    NOTO_SANS_MONO_FILES = {
      normal: 'NotoSansMono-Regular.ttf',
      bold: 'NotoSansMono-Bold.ttf'
    }.freeze

    def self.search_dirs
      [
        File.join(Dir.pwd, 'assets', 'fonts'),
        File.expand_path('../fonts', __dir__),
        File.expand_path('~/Library/Fonts'),
        '/usr/share/fonts/noto',
        '/usr/share/fonts/truetype/noto',
        '/usr/local/share/fonts/noto',
        *Dir.glob('/opt/homebrew/Caskroom/font-noto-sans/*/NotoSans/unhinted/ttf'),
        *Dir.glob('/opt/homebrew/Caskroom/font-noto-sans-mono/*/NotoSansMono/unhinted/ttf'),
        *Dir.glob('/usr/local/Caskroom/font-noto-sans/*/NotoSans/unhinted/ttf'),
        *Dir.glob('/usr/local/Caskroom/font-noto-sans-mono/*/NotoSansMono/unhinted/ttf')
      ]
    end

    def self.resolve(filename)
      search_dirs.each do |dir|
        path = File.join(dir, filename)
        return path if File.file?(path)
      end

      raise <<~MSG.strip
        #{filename} not found. Install Noto fonts (e.g. `brew install --cask font-noto-sans font-noto-sans-mono`) or add font files to assets/fonts/.
      MSG
    end

    def self.families
      {
        'Noto Sans' => NOTO_SANS_FILES.transform_values { |file| resolve(file) },
        'Noto Sans Mono' => NOTO_SANS_MONO_FILES.transform_values { |file| resolve(file) }
      }
    end

    def self.all_files
      families.values.flat_map(&:values).uniq
    end

    def self.register(pdf)
      pdf.font_families.update(families)
    end
  end
end
