# frozen_string_literal: true

module Printing
  module Escpos
    class Document
      ESC = "\x1B"
      GS = "\x1D"

      def initialize(width: 42, charset: nil)
        @width = width
        @buffer = +""
        @charset_config = Charset.resolve(charset)
        @rtl = @charset_config.equal?(Charset::ARABIC)
        init
      end

      def text(line = "")
        write_line(prepare_text(line))
      end

      def blank(lines = 1)
        lines.times { text }
      end

      def row(left, right = "")
        left_str = prepare_text(left)
        right_str = prepare_text(right)
        left_str, right_str = right_str, left_str if @rtl

        left_len = display_width(left_str)
        right_len = display_width(right_str)
        space = @width - left_len - right_len
        space = 1 if space < 1
        write_line("#{left_str}#{' ' * space}#{right_str}")
      end

      def rule(char = "-")
        text(char * @width)
      end

      def bold(on = true)
        @buffer << ESC << "E" << (on ? "\x01" : "\x00")
      end

      def align(mode)
        mode = rtl_align_mode(mode)
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
        select_code_page
      end

      def select_code_page
        code_page = Charset.code_page_for(@charset_config)
        @buffer << ESC << "t" << code_page.chr
      end

      def rtl_align_mode(mode)
        return mode unless @rtl

        case mode
        when :left then :right
        when :right then :left
        else mode
        end
      end

      def prepare_text(value)
        return value.to_s unless @rtl

        Bidi.visual_for_print(value)
      end

      def write_line(line)
        @buffer << encode_text(line) << "\n"
      end

      def encode_text(value)
        value.to_s.encode(
          @charset_config[:encoding],
          invalid: :replace,
          undef: :replace,
          replace: "?"
        )
      end

      def display_width(value)
        value.to_s.length
      end
    end
  end
end
