# frozen_string_literal: true

require "bidi"
require_relative "arabic_reshaper"

module Printing
  module Escpos
    module Bidi
      ARABIC_PATTERN = /\p{Arabic}/

      module_function

      # Reshape Arabic letters to their contextual forms (connected script),
      # then reorder characters to visual (right-to-left) order for printing.
      def visual_for_print(text, reshape: true)
        string = text.to_s
        return string unless string.match?(ARABIC_PATTERN)

        string = ArabicReshaper.reshape(string) if reshape
        ::Bidi.new.to_visual(string, "RTL")
      end
    end
  end
end
