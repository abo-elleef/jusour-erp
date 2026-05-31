# frozen_string_literal: true

module Printing
  module Escpos
    class Document
      ESC = "\x1B"
      GS = "\x1D"

      def initialize(width: 42)
        @width = width
        @buffer = +""
        init
      end

      def text(line = "")
        @buffer << sanitize(line) << "\n"
      end

      def blank(lines = 1)
        lines.times { text }
      end

      def row(left, right = "")
        left_str = sanitize(left.to_s)
        right_str = sanitize(right.to_s)
        space = @width - left_str.length - right_str.length
        space = 1 if space < 1
        text("#{left_str}#{' ' * space}#{right_str}")
      end

      def rule(char = "-")
        text(char * @width)
      end

      def bold(on = true)
        @buffer << ESC << "E" << (on ? "\x01" : "\x00")
      end

      def align(mode)
        code = { left: 0, center: 1, right: 2 }.fetch(mode)
        @buffer << ESC << "a" << code.chr
      end

      def double_height(on = true)
        @buffer << GS << "!" << (on ? "\x11" : "\x00")
      end

      def cut
        @buffer << GS << "V" << "\x00"
      end

      def to_bytes
        @buffer.force_encoding(Encoding::BINARY)
      end

      private

      def init
        @buffer << ESC << "@"
      end

      def sanitize(value)
        value.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?")
      end
    end
  end
end
