# frozen_string_literal: true

module Printing
  module Escpos
    class Document
      ESC = "\x1B"
      GS  = "\x1D"

      ARABIC_PATTERN = /\p{Arabic}/

      def initialize(width: 42, charset: nil)
        @width = width
        @buffer = +""
        @charset_config = Charset.resolve(charset)
        @rtl = @charset_config[:reshape]
        # Image rendering is used when Arabic font is available (always preferred
        # for Arabic because ESC/POS printers can't shape Arabic glyphs themselves).
        @use_images = @rtl && ArabicImageRenderer.arabic_font.present?
        @current_align = :left
        init
      end

      def text(line = "")
        str = line.to_s
        if @use_images && str.match?(ARABIC_PATTERN)
          write_arabic_image(str, align: @current_align)
        else
          write_line(prepare_text(str))
        end
      end

      def blank(lines = 1)
        lines.times { write_line("") }
      end

      def row(left, right = "")
        if @use_images && (left.to_s.match?(ARABIC_PATTERN) || right.to_s.match?(ARABIC_PATTERN))
          # Render as a two-part image: price on left, Arabic label on right
          price_str  = right.to_s   # price is always LTR
          label_str  = left.to_s
          label_str, price_str = price_str, label_str unless @rtl
          write_arabic_row_image(label_str, price_str)
        else
          left_str  = prepare_text(left)
          right_str = prepare_text(right)
          left_str, right_str = right_str, left_str if @rtl

          left_len  = display_width(left_str)
          right_len = display_width(right_str)
          space     = @width - left_len - right_len
          space     = 1 if space < 1
          write_line("#{left_str}#{' ' * space}#{right_str}")
        end
      end

      def rule(char = "-")
        write_line(char * @width)
      end

      def bold(on = true)
        @buffer << ESC << "E" << (on ? "\x01" : "\x00")
      end

      def align(mode)
        @current_align = mode
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
        return if code_page.zero?

        @buffer << ESC << "t" << code_page.chr
      end

      def rtl_align_mode(mode)
        return mode unless @rtl

        case mode
        when :left  then :right
        when :right then :left
        else mode
        end
      end

      def prepare_text(value)
        return value.to_s unless @rtl

        Bidi.visual_for_print(value, reshape: @charset_config[:reshape])
      end

      def write_line(line)
        @buffer << encode_text(line) << "\n"
      end

      def encode_text(value)
        str = value.to_s
        if @charset_config[:encoding] == Encoding::UTF_8
          str.encode(Encoding::UTF_8)
        else
          str.encode(
            @charset_config[:encoding],
            invalid: :replace,
            undef: :replace,
            replace: "?"
          )
        end
      end

      # Write Arabic text as a raster image line (handles shaping + RTL).
      def write_arabic_image(text, align: :right)
        img_align = @rtl ? rtl_align_mode(align) : align
        bytes = ArabicImageRenderer.render_line(text, doc_width: @width, align: img_align)
        if bytes
          @buffer << bytes.b
        else
          # Fallback: render as text if image rendering fails
          write_line(prepare_text(text))
        end
      end

      # Render a label+price row: price printed as text on one side,
      # Arabic label as an image on the other.
      def write_arabic_row_image(arabic_label, ltr_value)
        # Encode the LTR value (price/number) as plain text padded to fit
        value_enc = encode_text(ltr_value.to_s)
        value_len = ltr_value.to_s.length

        # Render the Arabic label occupying the remaining width as an image
        label_px_width = ArabicImageRenderer::PAPER_PX_WIDTH.fetch(@width, 576)
        char_px        = label_px_width / @width
        label_px       = label_px_width - (value_len * char_px)
        label_px       = [label_px, char_px * 4].max  # at least 4 chars wide

        img_bytes = ArabicImageRenderer.render_line(
          arabic_label,
          doc_width: @width,
          align: :right
        )

        if img_bytes
          # Print the price as plain text first (LTR side), then the image
          # For RTL: image (Arabic) is on the right, price on the left.
          # We print them on separate lines since mixing raster+text on one line
          # isn't reliably supported across ESC/POS implementations.
          @buffer << encode_text(ltr_value.to_s) << "\n"
          @buffer << img_bytes.b
        else
          # Fallback to text row
          left_str  = @rtl ? prepare_text(arabic_label) : prepare_text(ltr_value.to_s)
          right_str = @rtl ? prepare_text(ltr_value.to_s) : prepare_text(arabic_label)
          space     = [@width - display_width(left_str) - display_width(right_str), 1].max
          write_line("#{left_str}#{' ' * space}#{right_str}")
        end
      end

      def display_width(value)
        value.to_s.length
      end
    end
  end
end
