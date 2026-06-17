# frozen_string_literal: true

require "bidi"

module Printing
  module Escpos
    module Bidi
      ARABIC_PATTERN = /\p{Arabic}/

      module_function

      def visual_for_print(text)
        string = text.to_s
        return string unless string.match?(ARABIC_PATTERN)

        ::Bidi.new.to_visual(string, "RTL")
      end
    end
  end
end
