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
          # Single image: Arabic label on right, LTR value (price) on left.
          write_arabic_row_image(left.to_s, right.to_s)
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

      # Three-column receipt row: label (item name) | center (qty) | value (price).
      # In RTL image mode: label on right, qty in centre-left zone, value on left.
      def row3(label, center, value)
        if @use_images && (label.to_s.match?(ARABIC_PATTERN) || value.to_s.match?(ARABIC_PATTERN))
          write_arabic_row3_image(label.to_s, center.to_s, value.to_s)
        else
          label_str  = prepare_text(label)
          center_str = center.to_s
          value_str  = prepare_text(value)
          # RTL: value | center | label;  LTR: label | center | value
          left_str, right_str = @rtl ? [value_str, label_str] : [label_str, value_str]
          total = display_width(left_str) + display_width(center_str) + display_width(right_str)
          gap   = [(@width - total) / 2, 1].max
          write_line("#{left_str}#{' ' * gap}#{center_str}#{' ' * gap}#{right_str}")
        end
      end

      # Render a modifier/add-on line inside the item-name column with column borders.
      def modifier_text(line = "")
        str = line.to_s
        if @use_images
          visual = Bidi.visual_for_print(str, reshape: true)
          bytes  = ArabicImageRenderer.render_modifier_row(visual, doc_width: @width)
          return @buffer << bytes.b if bytes
        end
        # Text fallback
        @rtl ? (align(:right); text(str); align(:left)) : text("  #{str}")
      end

      # Full-width horizontal line rendered as an image (used between table rows).
      def separator
        bytes = ArabicImageRenderer.render_separator(doc_width: @width)
        bytes ? @buffer << bytes.b : rule
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

      # Print a logo image from a file path or URL.
      # Falls back silently if ImageMagick or the source is unavailable.
      def logo(source)
        return if source.blank?

        bytes = ArabicImageRenderer.render_logo(source, doc_width: @width)
        @buffer << bytes.b if bytes
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

      # Write Arabic text as a raster image line.
      # Pre-processes with reshape + bidi so ImageMagick (LTR renderer) displays
      # correctly: reshape assigns correct glyph forms, bidi reorders to visual order.
      def write_arabic_image(text, align: :right)
        visual = Bidi.visual_for_print(text, reshape: true)
        bytes  = ArabicImageRenderer.render_line(visual, doc_width: @width, align: align)
        if bytes
          @buffer << bytes.b
        else
          write_line(prepare_text(text))
        end
      end

      # Render a receipt row as a single image: Arabic label on the right,
      # LTR value (price) on the left — both on the same baseline.
      # Only the Arabic label is reshaped/reordered; the price is passed as-is.
      def write_arabic_row_image(arabic_label, ltr_value)
        visual_label = Bidi.visual_for_print(arabic_label, reshape: true)
        bytes = ArabicImageRenderer.render_row(visual_label, ltr_value, doc_width: @width)
        if bytes
          @buffer << bytes.b
        else
          left_str  = @rtl ? prepare_text(arabic_label) : prepare_text(ltr_value.to_s)
          right_str = @rtl ? prepare_text(ltr_value.to_s) : prepare_text(arabic_label)
          space     = [@width - display_width(left_str) - display_width(right_str), 1].max
          write_line("#{left_str}#{' ' * space}#{right_str}")
        end
      end

      def display_width(value)
        value.to_s.length
      end

      def write_arabic_row3_image(label, center, value)
        visual_label  = Bidi.visual_for_print(label,  reshape: true)
        visual_center = Bidi.visual_for_print(center, reshape: true)
        # Price column is always LTR (Latin digits). Only apply bidi when the
        # value is pure Arabic text (e.g. the "السعر" column header).
        visual_value  = value.match?(/[a-zA-Z0-9]/) ? value : Bidi.visual_for_print(value, reshape: true)
        bytes = ArabicImageRenderer.render_row3(visual_label, visual_center, visual_value, doc_width: @width)
        if bytes
          @buffer << bytes.b
        else
          write_arabic_row_image("#{label} (#{center})", value)
        end
      end
    end
  end
end
