# frozen_string_literal: true

require_relative "arabic_reshaper"
require_relative "arabic_image_renderer"

module Printing
  module Escpos
    module Bidi
      ARABIC_PATTERN = /\p{Arabic}/

      # Latin words and numbers keep their own left-to-right order inside an
      # Arabic line, so "10:48", "12.50" and "Big Mac" each print as one unit.
      LTR_RUN = %r{[A-Za-z0-9٠-٩]+(?:[ .:,/'&-]+[A-Za-z0-9٠-٩]+)*}

      # A reversed line flips which way brackets open; swapping them puts them
      # back around their content.
      MIRRORED = {
        "(" => ")", ")" => "(", "[" => "]", "]" => "[", "{" => "}", "}" => "{",
        "<" => ">", ">" => "<", "«" => "»", "»" => "«"
      }.freeze

      module_function

      # Reshape Arabic letters to their contextual forms (connected script),
      # then reorder characters to visual (right-to-left) order for printing.
      # Each print line is a single line, so line breaks collapse to spaces.
      def visual_for_print(text, reshape: true)
        string = text.to_s.squish
        return string unless string.match?(ARABIC_PATTERN)

        string = ArabicReshaper.reshape(string) if reshape
        to_visual(string)
      end

      # Visual order of a right-to-left line drawn left to right: every
      # character is reversed except the Latin/number runs, which stay whole.
      def to_visual(string)
        string.scan(/#{LTR_RUN.source}|./m).reverse.map { |token| MIRRORED.fetch(token, token) }.join
      end
    end
  end
end
