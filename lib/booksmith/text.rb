module Booksmith
  module Text
    SMART_QUOTES = {
      ldquo: "\u201c", rdquo: "\u201d",
      lsquo: "\u2018", rsquo: "\u2019",
      mdash: "\u2014", ndash: "\u2013",
      laquo: "\u00ab", raquo: "\u00bb"
    }.freeze

    private

    def extract_text(element, styles: nil)
      formatted_text = []

      element.children.each do |child|
        case child.type
        when :text
          entry = { text: child.value }
          entry[:styles] = styles if styles && !styles.empty?
          formatted_text << entry
        when :strong
          new_styles = (styles || []) + [:bold]
          formatted_text.concat(extract_text(child, styles: new_styles))
        when :em
          new_styles = (styles || []) + [:italic]
          formatted_text.concat(extract_text(child, styles: new_styles))
        when :codespan
          entry = { text: child.value, font: 'Noto Sans Mono', size: @config[:font_size] - 2 }
          entry[:styles] = styles if styles && !styles.empty?
          formatted_text << entry
        when :smart_quote
          char = SMART_QUOTES[child.value] || '?'
          entry = { text: char }
          entry[:styles] = styles if styles && !styles.empty?
          formatted_text << entry
        when :a
          new_styles = (styles || []) + [:underline]
          extract_text(child, styles: new_styles).each do |entry|
            entry[:color] = '0000FF'
            formatted_text << entry
          end
        else
          # Ignore unsupported inline types for now
        end
      end

      formatted_text
    end

    def plain_text(element)
      return '' unless element

      extract_text(element).map { |entry| entry[:text] }.join
    end
  end
end
